-- Security housekeeping — 2026-06-03
-- Addresses Supabase advisor warnings for tables with RLS enabled but no policies.
-- All four tables are internal backend-only tables; service_role bypasses RLS
-- and is the only caller. These policies make that intent explicit.

-- data_generation_runs — written/read by backend service_role only
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'data_generation_runs' AND policyname = 'backend_service_role_only'
  ) THEN
    EXECUTE 'CREATE POLICY backend_service_role_only ON public.data_generation_runs FOR ALL TO service_role USING (true)';
  END IF;
END $$;

-- data_generation_run_items — written/read by backend service_role only
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'data_generation_run_items' AND policyname = 'backend_service_role_only'
  ) THEN
    EXECUTE 'CREATE POLICY backend_service_role_only ON public.data_generation_run_items FOR ALL TO service_role USING (true)';
  END IF;
END $$;

-- gnews_wrapper_resolution — backend cache table, no user access
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'gnews_wrapper_resolution' AND policyname = 'backend_service_role_only'
  ) THEN
    EXECUTE 'CREATE POLICY backend_service_role_only ON public.gnews_wrapper_resolution FOR ALL TO service_role USING (true)';
  END IF;
END $$;

-- waitlist_signups — inserted by backend web handler, no anon/user access
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'waitlist_signups' AND policyname = 'backend_service_role_only'
  ) THEN
    EXECUTE 'CREATE POLICY backend_service_role_only ON public.waitlist_signups FOR ALL TO service_role USING (true)';
  END IF;
END $$;

-- Tighten waitlist anon INSERT: replace the always-true policy with a WITH CHECK
-- that enforces basic email length validation.
DROP POLICY IF EXISTS waitlist_insert_anon ON public.waitlist;
CREATE POLICY waitlist_insert_anon ON public.waitlist
  FOR INSERT TO anon
  WITH CHECK (char_length(email::text) BETWEEN 5 AND 320);

COMMENT ON TABLE public.data_generation_runs IS 'Internal job tracking. Backend service_role only — no user access.';
COMMENT ON TABLE public.data_generation_run_items IS 'Internal job item tracking. Backend service_role only — no user access.';
COMMENT ON TABLE public.gnews_wrapper_resolution IS 'GNews URL resolution cache. Backend service_role only — no user access.';
COMMENT ON TABLE public.waitlist_signups IS 'Marketing waitlist. Backend service_role only — no direct user access.';
