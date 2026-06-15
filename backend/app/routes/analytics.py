from __future__ import annotations

import re
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..services.supabase import get_supabase


router = APIRouter()

_EVENT_NAME_RE = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
_MAX_PROPERTIES = 50


class AnalyticsEventCreate(BaseModel):
    event_name: str
    properties: dict[str, Any] | None = None
    client_event_id: str | None = None
    platform: str | None = None
    app_version: str | None = None


def _trim_properties(properties: dict[str, Any] | None) -> dict[str, Any]:
    if not properties:
        return {}
    trimmed: dict[str, Any] = {}
    for key, value in properties.items():
        if len(trimmed) >= _MAX_PROPERTIES:
            break
        clean_key = str(key).strip()[:64]
        if not clean_key:
            continue
        trimmed[clean_key] = value
    return trimmed


@router.post("/event")
async def create_analytics_event(event: AnalyticsEventCreate, request: Request):
    user_id = request.state.user_id
    event_name = event.event_name.strip().lower()
    if not _EVENT_NAME_RE.match(event_name):
        raise HTTPException(status_code=400, detail="Invalid analytics event name")

    payload = {
        "user_id": user_id,
        "event_name": event_name,
        "properties": _trim_properties(event.properties),
        "client_event_id": event.client_event_id or str(uuid4()),
        "platform": event.platform,
        "app_version": event.app_version,
    }
    get_supabase().table("analytics_events").insert(payload).execute()
    return {"ok": True}
