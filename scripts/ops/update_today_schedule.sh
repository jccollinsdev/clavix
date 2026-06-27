#!/bin/bash

set -euo pipefail

LIFE_PLANNER_DIR="/Users/sansarkarki/Documents/Life Planner"
DATE_ARG="${1:-$(date +%Y-%m-%d)}"
MODE_ARG="${2:-launch}"

exec "$LIFE_PLANNER_DIR/run_clavix_founder.sh" "$DATE_ARG" "$MODE_ARG"
