-- Deduplicate ticker_risk_snapshots and unify snapshot_type to 'daily'.
--
-- Problem: manual_refresh and backfill rows coexist with daily rows for the
-- same (ticker, snapshot_date), causing duplicate chart points, grade flicker,
-- and ambiguous reads in the score history endpoint.
--
-- Fix:
--   1. Keep the single best row per (ticker, snapshot_date) — highest
--      analysis_as_of, tie-break by type priority then created_at.
--   2. Rename all surviving non-daily rows to 'daily' so snapshot_type is
--      uniform across the table.
--   3. Add a UNIQUE index on (ticker, snapshot_date) to prevent future dupes.

-- Step 1: Delete all but the best row per (ticker, snapshot_date).
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY ticker, snapshot_date
           ORDER BY
             analysis_as_of DESC NULLS LAST,
             CASE snapshot_type
               WHEN 'manual_refresh' THEN 1
               WHEN 'daily'          THEN 2
               WHEN 'backfill'       THEN 3
               ELSE 4
             END ASC,
             created_at DESC NULLS LAST
         ) AS rn
  FROM public.ticker_risk_snapshots
)
DELETE FROM public.ticker_risk_snapshots
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- Step 2: Rename surviving non-daily rows to 'daily'.
UPDATE public.ticker_risk_snapshots
SET snapshot_type = 'daily'
WHERE snapshot_type != 'daily';

-- Step 3: Add a unique index on (ticker, snapshot_date).
CREATE UNIQUE INDEX IF NOT EXISTS idx_ticker_risk_snapshots_ticker_date
  ON public.ticker_risk_snapshots (ticker, snapshot_date);
