from __future__ import annotations

import logging
import os
import uuid


logger = logging.getLogger(__name__)


def _default_ttl_seconds() -> int:
    """Lease TTL ceiling. Only bounds the *crash/leak* case — a healthy run
    releases immediately on completion. Must comfortably exceed the longest
    expected job runtime: if a job legitimately runs longer than the TTL its
    lease expires and a second scheduled run could steal it, reintroducing
    concurrency. Recompute runs ~30 min, so the 2h default has wide margin.
    """
    try:
        return max(int(os.getenv("JOB_LOCK_TTL_SECONDS", "7200")), 1)
    except (TypeError, ValueError):
        return 7200


class JobLock:
    """Pool-safe job lock backed by a TTL lease row (public.job_locks).

    Replaces session-level pg_advisory_lock, which leaked through Supabase's
    PostgREST connection pool: the lock was taken on one pooled backend and the
    release ran on a different one, so an idle backend held the lock forever and
    every later run returned skipped_lock (2026-07-01 recompute incident). The
    lease lives in a ROW keyed by lock_name, so it is immune to which pooled
    connection serves each RPC, and a crashed holder's lease auto-expires after
    ``ttl_seconds``.
    """

    def __init__(self, supabase, lock_name: str, *, ttl_seconds: int | None = None):
        self.supabase = supabase
        self.lock_name = lock_name
        # Unique per acquisition: release() only ever deletes *our* lease, never
        # one a later run took over after ours expired.
        self.holder = uuid.uuid4().hex
        self.ttl_seconds = (
            ttl_seconds if ttl_seconds is not None else _default_ttl_seconds()
        )
        self.acquired = False

    def acquire(self) -> bool:
        result = (
            self.supabase.rpc(
                "clavix_try_job_lock",
                {
                    "p_lock_name": self.lock_name,
                    "p_holder": self.holder,
                    "p_ttl_seconds": self.ttl_seconds,
                },
            )
            .execute()
            .data
        )
        self.acquired = _rpc_bool(result)
        return self.acquired

    def release(self) -> bool:
        if not self.acquired:
            return False
        try:
            result = (
                self.supabase.rpc(
                    "clavix_release_job_lock",
                    {"p_lock_name": self.lock_name, "p_holder": self.holder},
                )
                .execute()
                .data
            )
            return _rpc_bool(result)
        finally:
            self.acquired = False


# Backwards-compatible alias: older imports referenced PostgresAdvisoryLock.
# The implementation is no longer a session-level advisory lock (see JobLock),
# but the name is kept so external references keep resolving.
PostgresAdvisoryLock = JobLock


def _rpc_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, list) and value:
        first = value[0]
        if isinstance(first, bool):
            return first
        if isinstance(first, dict):
            return bool(next(iter(first.values()), False))
    if isinstance(value, dict):
        return bool(next(iter(value.values()), False))
    return bool(value)
