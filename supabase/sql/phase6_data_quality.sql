-- ============================================================================
-- Phase 6 SQL Data Quality Package — Event/News/Risk-Driver Audit
-- Purpose: Report on data quality of event_analyses, ticker_news_cache,
--          position_analyses driver fields, and related tables.
--
-- CRITICAL: ALL queries below are READ-ONLY SELECT statements.
--           No production writes, updates, deletes, or migrations.
--           Review counts before any cleanup.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. event_analyses missing canonical analyzed fields
-- ============================================================================

SELECT 'missing_what_happened' AS issue, COUNT(*) AS row_count
FROM event_analyses
WHERE what_happened IS NULL OR what_happened = ''

UNION ALL

SELECT 'missing_tldr', COUNT(*)
FROM event_analyses
WHERE tldr IS NULL OR tldr = ''

UNION ALL

SELECT 'missing_what_it_means', COUNT(*)
FROM event_analyses
WHERE what_it_means IS NULL OR what_it_means = ''

UNION ALL

SELECT 'missing_source_url', COUNT(*)
FROM event_analyses
WHERE source_url IS NULL OR source_url = ''

UNION ALL

SELECT 'missing_analysis_run_id', COUNT(*)
FROM event_analyses
WHERE analysis_run_id IS NULL

ORDER BY row_count DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Duplicate event hashes
-- ============================================================================

SELECT event_hash, COUNT(*) AS duplicate_count
FROM event_analyses
WHERE event_hash IS NOT NULL
GROUP BY event_hash
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Event rows tied only to user positions (not shared/system)
-- ============================================================================

SELECT COUNT(*) AS user_only_event_rows
FROM event_analyses
WHERE position_id IS NOT NULL
  AND position_id NOT ILIKE '%virtual%'
  AND position_id NOT ILIKE '%shared%'
  AND position_id NOT ILIKE '%system%';


-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. ticker_news_cache rows currently acting as analyzed event fallback
--    (these are raw cache rows that get surfaced as events when no
--     event_analyses exists for that ticker)
-- ============================================================================

SELECT COUNT(*) AS raw_news_cache_row_count
FROM ticker_news_cache;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. Sample event_analyses rows missing what_happened (20 samples)
-- ============================================================================

SELECT id, ticker, title, what_happened, tldr, what_it_means,
       source_url, analysis_run_id, created_at
FROM event_analyses
WHERE (what_happened IS NULL OR what_happened = '')
   OR (tldr IS NULL OR tldr = '')
ORDER BY created_at DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. position_analyses missing driver_cards
-- ============================================================================

SELECT
    COUNT(*) AS total_position_analyses,
    COUNT(*) FILTER (WHERE driver_cards IS NULL OR jsonb_array_length(driver_cards) = 0) AS missing_driver_cards,
    COUNT(*) FILTER (WHERE driver_cards_state IS NULL) AS missing_driver_cards_state
FROM position_analyses;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. event_analyses with fabricated tags (empty tags array)
-- ============================================================================

SELECT COUNT(*) AS events_with_empty_tags
FROM event_analyses
WHERE tags IS NULL OR jsonb_array_length(tags) = 0;


-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. event_analyses per ticker (show top 20 most-covered tickers)
-- ============================================================================

SELECT ticker, COUNT(*) AS event_count
FROM event_analyses
GROUP BY ticker
ORDER BY event_count DESC
LIMIT 20;


-- ═══════════════════════════════════════════════════════════════════════════════
-- AFFECTED TABLES SUMMARY
-- ============================================================================
-- event_analyses: canonical analyzed event records
-- ticker_news_cache: raw ingested news/article cache
-- position_analyses: per-position analysis artifacts (driver_cards here)
-- No writes performed — all queries are read-only SELECT statements.
