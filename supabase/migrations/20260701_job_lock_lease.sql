-- ============================================================================
-- Job lock lease — replace leaky session-level advisory locks with a
-- pool-safe, TTL'd row lease.
--
-- WHY (production incident, 2026-07-01):
--   run_job() acquired a *session-level* advisory lock
--   (pg_try_advisory_lock over the clavix_try_advisory_lock RPC) through a
--   POOLED PostgREST connection, then tried to release it on a *different*
--   pooled connection. Session-level advisory locks live on the exact backend
--   that took them, so the release ran on the wrong session and no-op'd. An
--   idle PostgREST backend (last query COMMIT) held
--   pg_try_advisory_lock(hashtextextended('clavix_job:daily_composite_recompute_universe',0))
--   -> classid 96847470 / objid 2466089061 -> indefinitely, and every later
--   recompute returned skipped_lock (reason advisory_lock_held) until the
--   backend was manually terminated (pg_terminate_backend).
--
-- FIX:
--   A lease row keyed by lock_name. The lock's state lives in a ROW, not in a
--   backend session, so it is immune to which pooled connection serves each
--   RPC. Normal release deletes the row; a crashed/leaked holder's lease
--   auto-expires after ttl_seconds, so a lock can never wedge the scheduler for
--   more than one cycle.
--
-- The old clavix_try_advisory_lock / clavix_advisory_unlock functions are left
-- in place (unused, deprecated) so this migration is additive and rollback is
-- trivial. All changes here are additive and idempotent.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.job_locks (
    lock_name   TEXT PRIMARY KEY,
    holder      TEXT NOT NULL,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL
);

ALTER TABLE public.job_locks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_manage_job_locks" ON public.job_locks;
CREATE POLICY "service_role_manage_job_locks"
    ON public.job_locks
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE public.job_locks IS
    'Pool-safe TTL lease locks for scheduled jobs. Replaces session-level '
    'pg_advisory_lock, which leaked through the PostgREST connection pool '
    '(2026-07-01 recompute incident).';

-- Acquire (or steal-if-expired) the named lease for p_holder.
-- Returns TRUE iff p_holder now owns a live lease.
--
-- Concurrency: INSERT ... ON CONFLICT DO UPDATE takes a row lock on the
-- conflicting row, so two racing acquirers are serialized. The loser re-reads
-- the row the winner just refreshed, its `jl.expires_at <= v_now` predicate is
-- false, DO UPDATE is skipped, RETURNING yields no row -> returns FALSE.
CREATE OR REPLACE FUNCTION public.clavix_try_job_lock(
    p_lock_name   TEXT,
    p_holder      TEXT,
    p_ttl_seconds INTEGER DEFAULT 7200
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_now    TIMESTAMPTZ := now();
    v_holder TEXT;
BEGIN
    INSERT INTO public.job_locks AS jl (lock_name, holder, acquired_at, expires_at)
    VALUES (
        p_lock_name,
        p_holder,
        v_now,
        v_now + make_interval(secs => GREATEST(p_ttl_seconds, 1))
    )
    ON CONFLICT (lock_name) DO UPDATE
        SET holder      = EXCLUDED.holder,
            acquired_at = EXCLUDED.acquired_at,
            expires_at  = EXCLUDED.expires_at
        WHERE jl.expires_at <= v_now          -- only steal a lease that has expired
    RETURNING jl.holder INTO v_holder;

    -- RETURNING yields our holder when we inserted fresh or stole an expired
    -- lease; it yields NULL when the ON CONFLICT WHERE was false (a live lease
    -- is held by someone else and no row was written).
    RETURN v_holder IS NOT DISTINCT FROM p_holder;
END;
$$;

-- Release the named lease, but only if p_holder still owns it. If our lease
-- already expired and a later run stole it, this deletes nothing (holder
-- mismatch) and returns FALSE, so a leaked/expired release never clobbers the
-- current holder. Returns TRUE iff our own lease row was deleted.
CREATE OR REPLACE FUNCTION public.clavix_release_job_lock(
    p_lock_name TEXT,
    p_holder    TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
AS $$
    WITH del AS (
        DELETE FROM public.job_locks
        WHERE lock_name = p_lock_name
          AND holder = p_holder
        RETURNING 1
    )
    SELECT EXISTS (SELECT 1 FROM del);
$$;

REVOKE ALL ON FUNCTION public.clavix_try_job_lock(TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clavix_release_job_lock(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clavix_try_job_lock(TEXT, TEXT, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.clavix_release_job_lock(TEXT, TEXT) TO service_role;
