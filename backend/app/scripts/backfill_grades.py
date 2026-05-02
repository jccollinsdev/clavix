"""
Backfill risk_scores.grade to match canonical score_to_grade().

Usage (inside Docker):
  python -m app.scripts.backfill_grades                 # dry-run (default)
  python -m app.scripts.backfill_grades --apply           # apply fixes
"""

import argparse
import logging
import sys

from ..pipeline.analysis_utils import score_to_grade
from ..services.supabase import get_supabase

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger(__name__)

TABLE = "risk_scores"
BATCH = 500


def _fetch_batch(supabase, offset: int, limit: int) -> list[dict]:
    return (
        supabase.table(TABLE)
        .select("id,total_score,grade")
        .range(offset, offset + limit - 1)
        .execute()
        .data
    )


def run(dry_run: bool = True) -> dict[str, int]:
    supabase = get_supabase()
    offset = 0
    checked = 0
    mismatches = 0
    updated = 0

    while True:
        rows = _fetch_batch(supabase, offset, BATCH)
        if not rows:
            break

        for row in rows:
            checked += 1
            total_score = row.get("total_score")
            stored_grade = row.get("grade")
            row_id = row.get("id")

            if total_score is None or stored_grade is None:
                continue

            expected = score_to_grade(total_score)
            if stored_grade != expected:
                mismatches += 1
                if not dry_run:
                    supabase.table(TABLE).update({"grade": expected}).eq(
                        "id", row_id
                    ).execute()
                    updated += 1

        offset += BATCH

    return {"checked": checked, "mismatches": mismatches, "updated": updated}


def main():
    parser = argparse.ArgumentParser(description="Backfill risk_scores.grade")
    parser.add_argument(
        "--apply",
        action="store_true",
        default=False,
        help="Apply fixes (default is dry-run)",
    )
    args = parser.parse_args()

    dry_run = not args.apply
    mode = "DRY-RUN" if dry_run else "APPLY"
    log.info("Starting grade backfill [%s]", mode)

    result = run(dry_run=dry_run)

    log.info("Checked:   %d", result["checked"])
    log.info("Mismatches: %d", result["mismatches"])
    log.info("Updated:   %d", result["updated"])

    if dry_run and result["mismatches"] > 0:
        log.info(
            "Re-run with --apply to fix %d mismatched rows.", result["mismatches"]
        )
        sys.exit(1)


if __name__ == "__main__":
    main()