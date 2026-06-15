-- The v2 snapshot schema stores these dimensions in *_dim columns.
-- The legacy non-dim columns have remained null and are no longer selected by code.

ALTER TABLE public.ticker_risk_snapshots
    DROP COLUMN IF EXISTS news_sentiment,
    DROP COLUMN IF EXISTS macro_exposure;
