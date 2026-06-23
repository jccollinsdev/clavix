# Grade Stability Audit and Remediation

**Date:** 2026-06-23

**Scope:** Backend ticker grades and canonical daily snapshot writes

**Status:** Implemented, deployed, and verified

## Executive summary

The existing exponential smoothing and 3-point grade hysteresis are effective in the canonical daily recompute path. In the clearly post-fix production window from June 17 through June 22, only 0.6% to 2.9% of daily ticker transitions changed grade, and none of the observed changes leaked across a boundary on a sub-point score movement.

The audit found two secondary writers that could bypass or undo that protection:

1. A user-triggered portfolio analysis could write a raw LLM grade into `ticker_risk_snapshots`, overwrite the canonical same-day row, and skip hysteresis because its payload does not include `previous_grade`.
2. The system snapshot synchronization path recalculated `grade` from the raw score even though its source was already a complete, canonical, hysteresis-adjusted snapshot.

Both paths are now constrained so the daily recompute remains the authority for the shared ticker snapshot and grade.

## Production evidence

- Across all available history, 18.1% of day-to-day transitions changed grade while the average score movement was 1.57 points. Most of that history predates the existing EMA and hysteresis deployment.
- Clear pre-fix boundary leaks included DHI moving from 70.0 to 69.8 and flipping from A to BBB, followed by a later reversal.
- In the June 17 through June 22 steady-state window, there were no sub-point grade leaks. The remaining changes represented larger moves or correct hysteresis releases.
- The June 23 recompute produced more movement because it folded the completed news backfill into scores. That is a one-time data re-leveling event, not ordinary boundary noise.

## Changes made

### Canonical same-day protection

The portfolio analysis writer now:

- Loads recent ticker history directly from the database.
- Returns without writing when a same-day snapshot already exists.
- Anchors hysteresis to the most recent prior-day stored grade.
- Fails closed when grade history cannot be loaded, because the portfolio path is not authoritative for the shared daily snapshot.
- Uses insert-only behavior instead of upsert. If the canonical recompute wins a race and creates the same `(ticker, snapshot_date)` key after the history check, the unique-key conflict leaves the canonical row untouched.

### Canonical grade preservation during sync

The snapshot synchronization path now preserves `source_snapshot.grade`. It only falls back to `score_to_grade(public_score)` for legacy source data that has no stored grade.

## Verification

The focused backend suite passes:

```text
77 passed, 3 warnings in 0.57s
```

Coverage includes:

- Same-day canonical snapshots cannot be overwritten by portfolio analysis.
- A 0.2-point move from 70.0 to 69.8 remains A when the prior grade is A.
- A real move to 66.0 releases through the hysteresis buffer and becomes BBB.
- A failed history read produces no non-authoritative snapshot write.
- Snapshot synchronization preserves the canonical stored grade even when the raw score maps to another band.
- Existing grade-contract and score-source-of-truth suites remain green.

## Production closeout

- The June 23 universe recompute was allowed to finish before restart. It completed at 2026-06-23 12:21:28 UTC with 375 processed, 171 freshness-skipped, and zero reported failures.
- Two stale refresh locks from the earlier interrupted run caused CMG and EME to be counted without a June 23 snapshot. Both were explicitly refreshed after restart.
- Final verification found 546 snapshots for 546 active tickers, no duplicate ticker rows, and no missing grades.
- Polygon options endpoint 403 responses observed during the recompute are known plan limitations and were non-fatal.
- The production file was compared with the local file before deployment. A rollback copy is retained at `/tmp/scheduler_pre_grade_stability_final.py` on the VPS.
- The public and local production health endpoints returned `{"status":"ok"}` after restart. The running container exposes both grade-stability guards, and its post-restart logs contain no traceback, error, or exception entries.

## Result

The canonical recompute remains the authority for daily ticker grades. Secondary paths can seed a missing snapshot or synchronize a canonical snapshot, but they can no longer remap or overwrite a hysteresis-stabilized same-day grade.
