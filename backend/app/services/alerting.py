"""Centralized external alerting: Sentry + optional Slack webhook + dead-man heartbeat.

Design goal: the codebase must run safely with NO external services wired up. Every
function here is best-effort and never raises. Each channel activates only when its
env var is present, so a fresh checkout (or a CI run) silently no-ops instead of
breaking.

To actually receive pages, the operator provisions (all free):
  - SENTRY_DSN ................ Sentry project DSN (error aggregation + cron monitors)
  - CLAVIX_SLACK_WEBHOOK_URL .. Slack incoming webhook (https://hooks.slack.com/...)
  - CLAVIX_HEARTBEAT_URL ...... a healthchecks.io (or similar) ping URL; ops_monitor
                                pings it every run, so its ABSENCE is what pages you
                                (a true dead-man's switch the host itself cannot fake).
"""
from __future__ import annotations

import logging
import os

import requests

logger = logging.getLogger(__name__)

_ERROR_LEVELS = {"error", "critical", "fatal"}


def _env(name: str) -> str:
    return os.getenv(name, "").strip()


def send_alert(title: str, *, level: str = "error", context: dict | None = None) -> None:
    """Fan a single alert out to log + Sentry + Slack. Best-effort, never raises.

    `level` is one of: info, warning, error, critical, fatal.
    `context` is a small dict of key/value detail rendered into each channel.
    """
    context = context or {}

    # 1. Always log loudly — this is the one channel that needs no provisioning and
    #    is visible in `docker logs` and job_runs investigations.
    log_fn = logger.error if level in _ERROR_LEVELS else logger.warning
    ctx_str = str(context)[:1000]
    log_fn("[ALERT] %s | %s", title, ctx_str)

    # 2. Sentry — no-op if the SDK is absent or SENTRY_DSN is unset.
    try:
        import sentry_sdk  # type: ignore

        sentry_level = level if level in {"info", "warning", "error", "fatal"} else "error"
        sentry_sdk.capture_message(title, level=sentry_level, extras={"context": context})
    except Exception:
        pass

    # 3. Slack incoming webhook — no-op if CLAVIX_SLACK_WEBHOOK_URL is unset.
    url = _env("CLAVIX_SLACK_WEBHOOK_URL")
    if url:
        emoji = ":rotating_light:" if level in _ERROR_LEVELS else ":warning:"
        lines = [f"{emoji} *{title}*"]
        for key, value in context.items():
            lines.append(f"• {key}: {value}")
        text = "\n".join(lines)[:3500]
        try:
            requests.post(url, json={"text": text}, timeout=8)
        except Exception as exc:  # pragma: no cover - network dependent
            logger.warning("[ALERT] Slack webhook POST failed: %s", exc)


def ping_heartbeat(*, failed: bool = False) -> None:
    """Ping the dead-man's-switch URL (healthchecks.io style). Best-effort, never raises.

    A monitor like healthchecks.io expects a ping on a schedule and pages the operator
    when one is MISSING — so this catches the case the host itself cannot self-report
    (cron died, container down, whole box offline). Append /fail to signal a bad run.
    """
    base = _env("CLAVIX_HEARTBEAT_URL")
    if not base:
        return
    url = base.rstrip("/") + "/fail" if failed else base
    try:
        requests.get(url, timeout=8)
    except Exception as exc:  # pragma: no cover - network dependent
        logger.warning("[ALERT] heartbeat ping failed: %s", exc)
