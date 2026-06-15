-- Lightweight first-party funnel analytics for TestFlight launch.

CREATE TABLE IF NOT EXISTS public.analytics_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_name TEXT NOT NULL CHECK (
        event_name ~ '^[a-z][a-z0-9_]{1,63}$'
    ),
    properties JSONB NOT NULL DEFAULT '{}'::jsonb,
    client_event_id TEXT,
    platform TEXT,
    app_version TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_insert_own_analytics_events" ON public.analytics_events;
CREATE POLICY "users_insert_own_analytics_events"
    ON public.analytics_events FOR INSERT
    WITH CHECK (auth.uid() = user_id OR auth.role() = 'service_role');

DROP POLICY IF EXISTS "users_read_own_analytics_events" ON public.analytics_events;
CREATE POLICY "users_read_own_analytics_events"
    ON public.analytics_events FOR SELECT
    USING (auth.uid() = user_id OR auth.role() = 'service_role');

DROP POLICY IF EXISTS "service_role_manage_analytics_events" ON public.analytics_events;
CREATE POLICY "service_role_manage_analytics_events"
    ON public.analytics_events FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_analytics_events_user_created
    ON public.analytics_events(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_analytics_events_name_created
    ON public.analytics_events(event_name, created_at DESC);
