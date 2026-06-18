from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException

from app.routes import trigger


class _Result:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, rows):
        self.rows = list(rows)

    def select(self, *_args, **_kwargs):
        return self

    def eq(self, *_args, **_kwargs):
        return self

    def gte(self, *_args, **_kwargs):
        return self

    def order(self, *_args, **_kwargs):
        return self

    def limit(self, value):
        self.rows = self.rows[:value]
        return self

    def execute(self):
        return _Result(self.rows)


class _DB:
    def __init__(self, analysis_runs):
        self.analysis_runs = analysis_runs

    def table(self, name):
        if name == "analysis_runs":
            return _Query(self.analysis_runs)
        return _Query([])


@pytest.mark.asyncio
async def test_trigger_analysis_enforces_short_cooldown(monkeypatch):
    now = datetime.now(timezone.utc)
    db = _DB([{"id": "run-1", "started_at": (now - timedelta(minutes=5)).isoformat()}])
    monkeypatch.setattr(trigger, "get_supabase", lambda: db)

    with pytest.raises(HTTPException) as exc:
        await trigger.trigger_analysis(user_id="user-1")

    assert exc.value.status_code == 429
    assert "cooling down" in exc.value.detail


@pytest.mark.asyncio
async def test_trigger_analysis_keeps_three_per_day_limit(monkeypatch):
    now = datetime.now(timezone.utc)
    db = _DB(
        [
            {"id": "run-1", "started_at": (now - timedelta(minutes=20)).isoformat()},
            {"id": "run-2", "started_at": (now - timedelta(hours=2)).isoformat()},
            {"id": "run-3", "started_at": (now - timedelta(hours=4)).isoformat()},
        ]
    )
    monkeypatch.setattr(trigger, "get_supabase", lambda: db)

    with pytest.raises(HTTPException) as exc:
        await trigger.trigger_analysis(user_id="user-1")

    assert exc.value.status_code == 429
    assert "3 requests per 24 hours" in exc.value.detail
