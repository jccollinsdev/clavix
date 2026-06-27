#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
cd "$BACKEND_DIR"

if [ -n "${PYTHON:-}" ]; then
  PYTHON_BIN="$PYTHON"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
else
  PYTHON_BIN="python"
fi

echo "[nightly_ops] starting"

if [ -f "$BACKEND_DIR/.venv/bin/activate" ]; then
  # Prefer the repo-local virtualenv when present.
  # shellcheck disable=SC1091
  source "$BACKEND_DIR/.venv/bin/activate"
  PYTHON_BIN="python"
fi

echo "[nightly_ops] running daily_earnings_calendar_refresh"
export PYTHONPATH="$BACKEND_DIR${PYTHONPATH:+:$PYTHONPATH}"
CALENDAR_OUTPUT="$("$PYTHON_BIN" -m app.jobs.run daily_earnings_calendar_refresh)"
echo "$CALENDAR_OUTPUT"

if echo "$CALENDAR_OUTPUT" | grep -q '"status": *"failed"'; then
  echo "[nightly_ops] calendar schedule generation failed" >&2
  exit 1
fi

if echo "$CALENDAR_OUTPUT" | grep -q '"status": *"unknown_job"'; then
  echo "[nightly_ops] calendar job is not registered" >&2
  exit 1
fi

if [ -n "${NOTION_DAILY_OPS_REPORT_ID:-}" ]; then
  echo "[nightly_ops] notion report publishing is not implemented in this repository; NOTION_DAILY_OPS_REPORT_ID is set but no publisher exists" >&2
  exit 1
fi

echo "[nightly_ops] Notion Daily Ops report publisher not found in repo"
echo "[nightly_ops] next-day calendar schedule generation completed"
echo "[nightly_ops] done"
