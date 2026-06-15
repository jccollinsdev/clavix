-- Persist the exact financial-health inputs used by the v2 scorer so daily
-- recomputes can reuse weekly fundamentals instead of sampling Finnhub live.

ALTER TABLE public.ticker_metadata
    ADD COLUMN IF NOT EXISTS debt_to_equity NUMERIC,
    ADD COLUMN IF NOT EXISTS fcf_margin NUMERIC,
    ADD COLUMN IF NOT EXISTS interest_coverage NUMERIC,
    ADD COLUMN IF NOT EXISTS current_ratio NUMERIC,
    ADD COLUMN IF NOT EXISTS revenue_growth_trend NUMERIC,
    ADD COLUMN IF NOT EXISTS fundamentals_updated_at TIMESTAMPTZ;

UPDATE public.ticker_metadata
SET fundamentals_updated_at = COALESCE(fundamentals_updated_at, updated_at, created_at, now())
WHERE fundamentals_updated_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_ticker_metadata_fundamentals_updated_at
    ON public.ticker_metadata(fundamentals_updated_at DESC);
