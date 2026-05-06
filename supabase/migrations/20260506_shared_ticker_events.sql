-- ============================================================================
-- Phase 7B — Canonical Shared Ticker Event Table
-- Purpose: Create the shared_ticker_events table and add back-reference
--          from event_analyses. Additive DDL only — no deletes, no rewrites.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.shared_ticker_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticker TEXT NOT NULL,
    event_hash TEXT NOT NULL,
    external_event_id TEXT,
    news_id UUID REFERENCES public.news_items(id),
    news_cache_id UUID REFERENCES public.ticker_news_cache(id),
    title TEXT NOT NULL,
    summary TEXT,
    source TEXT,
    source_url TEXT,
    published_at TIMESTAMPTZ,
    event_type TEXT,
    significance TEXT CHECK (significance IN ('major', 'minor')),
    classification JSONB,
    analysis_source TEXT,
    what_happened TEXT,
    tldr TEXT,
    what_it_means TEXT,
    long_analysis TEXT,
    confidence NUMERIC CHECK (confidence >= 0 AND confidence <= 1),
    impact_horizon TEXT CHECK (impact_horizon IN ('immediate', 'near_term', 'long_term')),
    risk_direction TEXT CHECK (risk_direction IN ('improving', 'neutral', 'worsening')),
    scenario_summary TEXT,
    key_implications JSONB,
    follow_up_notes JSONB,
    tags JSONB DEFAULT '[]'::jsonb,
    analysis_run_id UUID REFERENCES public.analysis_runs(id),
    factored_into_score BOOLEAN DEFAULT false,
    provenance TEXT DEFAULT 'shared',
    methodology_version TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shared_ticker_events_ticker
    ON public.shared_ticker_events(ticker);
CREATE INDEX IF NOT EXISTS idx_shared_ticker_events_event_hash
    ON public.shared_ticker_events(event_hash);
CREATE INDEX IF NOT EXISTS idx_shared_ticker_events_ticker_date
    ON public.shared_ticker_events(ticker, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_shared_ticker_events_run_id
    ON public.shared_ticker_events(analysis_run_id);
CREATE INDEX IF NOT EXISTS idx_shared_ticker_events_source_url
    ON public.shared_ticker_events(ticker, source_url);

ALTER TABLE public.shared_ticker_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anyone_can_read_shared_ticker_events"
    ON public.shared_ticker_events
    FOR SELECT
    USING (true);

ALTER TABLE public.event_analyses
    ADD COLUMN IF NOT EXISTS shared_event_id UUID
    REFERENCES public.shared_ticker_events(id)
    ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_event_analyses_shared_event_id
    ON public.event_analyses(shared_event_id);
