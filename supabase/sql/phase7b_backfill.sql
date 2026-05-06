-- ============================================================================
-- Phase 7B — Shared Ticker Event Backfill Plan
-- Purpose: Map existing event_analyses rows into shared_ticker_events,
--          grouping by ticker + event_hash to deduplicate position-level dupes.
--
-- CRITICAL: ALL queries below are read-only dry-run SELECTs.
--           The UPSERT query (section 5) is COMMENTED OUT.
--           Do NOT run the apply until dry-run is reviewed and approved.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. How many unique ticker:event_hash pairs exist?
-- ============================================================================

SELECT COUNT(DISTINCT CONCAT(p.ticker, ':', ea.event_hash)) AS unique_shared_rows,
       COUNT(DISTINCT p.ticker) AS unique_tickers,
       COUNT(DISTINCT ea.event_hash) AS unique_hashes
FROM event_analyses ea
JOIN positions p ON p.id = ea.position_id
WHERE p.ticker IS NOT NULL;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Which tickers have the most duplicate events?
-- ============================================================================

SELECT p.ticker,
       COUNT(DISTINCT ea.id) AS row_count,
       COUNT(DISTINCT ea.event_hash) AS unique_hashes,
       ROUND(AVG(CAST(ea.confidence AS NUMERIC)), 2) AS avg_confidence
FROM event_analyses ea
JOIN positions p ON p.id = ea.position_id
WHERE p.ticker IS NOT NULL
GROUP BY p.ticker
ORDER BY row_count DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Sample: best row per (ticker, event_hash) — what would be upserted
-- ============================================================================

WITH best_row AS (
    SELECT DISTINCT ON (p.ticker, ea.event_hash)
        p.ticker,
        ea.event_hash,
        ea.title,
        ea.source,
        ea.source_url,
        ea.published_at,
        ea.event_type,
        ea.significance,
        ea.analysis_source,
        ea.what_happened,
        ea.tldr,
        ea.what_it_means,
        ea.long_analysis,
        ea.confidence,
        ea.risk_direction,
        ea.impact_horizon,
        ea.scenario_summary,
        ea.key_implications,
        ea.recommended_followups,
        ea.analysis_run_id,
        ea.created_at,
        COUNT(*) OVER (PARTITION BY p.ticker, ea.event_hash) AS duplicate_count
    FROM event_analyses ea
    JOIN positions p ON p.id = ea.position_id
    WHERE p.ticker IS NOT NULL
    ORDER BY p.ticker, ea.event_hash, ea.confidence DESC NULLS LAST, ea.created_at DESC
)
SELECT * FROM best_row
ORDER BY duplicate_count DESC, ticker
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Ticker coverage summary
-- ============================================================================

SELECT COUNT(DISTINCT ticker) AS tickers_with_events FROM shared_ticker_events;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. APPLY: Backfill from event_analyses (COMMENTED OUT — DO NOT RUN YET)
-- ============================================================================

/*
WITH best_row AS (
    SELECT DISTINCT ON (p.ticker, ea.event_hash)
        p.ticker AS ticker,
        ea.event_hash AS event_hash,
        ea.external_event_id AS external_event_id,
        ea.title AS title,
        ea.summary AS summary,
        ea.source AS source,
        ea.source_url AS source_url,
        ea.published_at AS published_at,
        ea.event_type AS event_type,
        ea.significance AS significance,
        ea.classification AS classification,
        ea.analysis_source AS analysis_source,
        ea.what_happened AS what_happened,
        ea.tldr AS tldr,
        ea.what_it_means AS what_it_means,
        ea.long_analysis AS long_analysis,
        ea.confidence AS confidence,
        ea.impact_horizon AS impact_horizon,
        ea.risk_direction AS risk_direction,
        ea.scenario_summary AS scenario_summary,
        ea.key_implications AS key_implications,
        ea.recommended_followups AS follow_up_notes,
        ea.analysis_run_id AS analysis_run_id,
        'backfilled' AS provenance,
        ea.created_at AS created_at
    FROM event_analyses ea
    JOIN positions p ON p.id = ea.position_id
    WHERE p.ticker IS NOT NULL
    ORDER BY p.ticker, ea.event_hash, ea.confidence DESC NULLS LAST, ea.created_at DESC
)
INSERT INTO shared_ticker_events (
    ticker, event_hash, external_event_id, title, summary, source, source_url,
    published_at, event_type, significance, classification, analysis_source,
    what_happened, tldr, what_it_means, long_analysis, confidence,
    impact_horizon, risk_direction, scenario_summary, key_implications,
    follow_up_notes, analysis_run_id, provenance, created_at, updated_at
)
SELECT
    ticker, event_hash, external_event_id, title, summary, source, source_url,
    published_at, event_type, significance, classification, analysis_source,
    what_happened, tldr, what_it_means, long_analysis, confidence,
    impact_horizon, risk_direction, scenario_summary, key_implications,
    follow_up_notes, analysis_run_id, provenance, created_at, now()
FROM best_row
ON CONFLICT (ticker, event_hash) DO NOTHING;
*/


-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. ROLLBACK
-- ============================================================================
-- Truncate shared_ticker_events (or drop and recreate) to remove backfilled rows.
-- No impact on event_analyses or any other production table.


-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. AFFECTED TABLES
-- ============================================================================
-- WRITES: shared_ticker_events (new rows added via backfill)
-- READS:  event_analyses, positions (joined for ticker mapping)
-- NO changes to: event_analyses, positions, risk_scores, ticker_risk_snapshots,
--                digests, alerts, analysis_runs, position_analyses
