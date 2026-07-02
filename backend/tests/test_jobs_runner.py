import sys
import types
from unittest.mock import patch
from types import SimpleNamespace

_fake_supabase_module = types.ModuleType("supabase")
_fake_supabase_module.create_client = lambda *args, **kwargs: None
_fake_supabase_module.Client = object
sys.modules.setdefault("supabase", _fake_supabase_module)

from app.jobs import run as job_runner


class _FakeQuery:
    def __init__(self, table_name: str, db: "FakeSupabase"):
        self.table_name = table_name
        self.db = db
        self.payload = None
        self.filters = {}
        self.neq_filters = {}
        self.mode = None
        self._order = None
        self._limit = None

    def insert(self, payload):
        self.mode = "insert"
        self.payload = payload
        return self

    def update(self, payload):
        self.mode = "update"
        self.payload = payload
        return self

    def select(self, *_columns):
        self.mode = "select"
        return self

    def eq(self, key, value):
        self.filters[key] = value
        return self

    def neq(self, key, value):
        self.neq_filters[key] = value
        return self

    def order(self, column, desc=False):
        self._order = (column, desc)
        return self

    def limit(self, count):
        self._limit = count
        return self

    def execute(self):
        if self.mode == "insert":
            row = {"id": f"run-{len(self.db.rows) + 1}", **self.payload}
            self.db.rows.append(row)
            return SimpleNamespace(data=[row])
        if self.mode == "update":
            row_id = self.filters.get("id")
            for row in self.db.rows:
                if row.get("id") == row_id:
                    row.update(self.payload)
                    return SimpleNamespace(data=[row])
            return SimpleNamespace(data=[])
        if self.mode == "select":
            rows = [
                r
                for r in self.db.rows
                if all(r.get(k) == v for k, v in self.filters.items())
                and all(r.get(k) != v for k, v in self.neq_filters.items())
            ]
            if self._order is not None:
                column, desc = self._order
                rows = sorted(rows, key=lambda r: r.get(column) or "", reverse=desc)
            if self._limit is not None:
                rows = rows[: self._limit]
            return SimpleNamespace(data=rows)
        return SimpleNamespace(data=[])


class _FakeRpc:
    def __init__(self, value):
        self.value = value

    def execute(self):
        return SimpleNamespace(data=self.value)


class FakeSupabase:
    def __init__(self, lock_value=True):
        self.lock_value = lock_value
        self.rows = []
        self.rpc_calls = []

    def table(self, table_name):
        assert table_name == "job_runs"
        return _FakeQuery(table_name, self)

    def rpc(self, name, params):
        self.rpc_calls.append((name, params))
        if name == "clavix_try_job_lock":
            return _FakeRpc(self.lock_value)
        return _FakeRpc(True)


def test_job_runner_dry_run_does_not_touch_db():
    result = job_runner.main(["daily_macro_snapshot", "--dry-run"])

    assert result == 0


def test_run_job_records_skipped_lock():
    fake_supabase = FakeSupabase(lock_value=False)

    with patch.object(job_runner, "get_supabase", return_value=fake_supabase):
        result = job_runner.run_job_sync("daily_macro_snapshot")

    assert result["status"] == "skipped_lock"
    assert fake_supabase.rows[0]["status"] == "skipped_lock"
    assert fake_supabase.rows[0]["items_skipped"] == 1


def test_run_job_records_success_and_releases_lock():
    fake_supabase = FakeSupabase(lock_value=True)

    def fake_handler():
        return {"status": "completed", "items_processed": 11}

    spec = job_runner.JobSpec("fake_job", "daily", fake_handler)
    with (
        patch.object(job_runner, "get_supabase", return_value=fake_supabase),
        patch.dict(job_runner.JOB_REGISTRY, {"fake_job": spec}),
    ):
        result = job_runner.run_job_sync("fake_job")

    assert result["status"] == "completed"
    assert result["items_processed"] == 11
    rpc_names = [name for name, _params in fake_supabase.rpc_calls]
    assert rpc_names == ["clavix_try_job_lock", "clavix_release_job_lock"]
    # acquire and release must target the SAME holder token, else the lease
    # can never be released (the leak this replaced).
    acquire_params = fake_supabase.rpc_calls[0][1]
    release_params = fake_supabase.rpc_calls[1][1]
    assert acquire_params["p_holder"] == release_params["p_holder"]


def test_lock_key_overrides_lock_name():
    # A job with an explicit lock_key locks on that shared name instead of its
    # own job_id, so siblings mutating the same resource are mutually exclusive.
    fake_supabase = FakeSupabase(lock_value=True)
    spec = job_runner.JobSpec(
        "sibling_job",
        "weekly",
        lambda: {"status": "completed"},
        lock_key="shared_resource",
    )
    with (
        patch.object(job_runner, "get_supabase", return_value=fake_supabase),
        patch.dict(job_runner.JOB_REGISTRY, {"sibling_job": spec}),
    ):
        job_runner.run_job_sync("sibling_job")

    acquire_params = fake_supabase.rpc_calls[0][1]
    assert acquire_params["p_lock_name"] == "clavix_job:shared_resource"


def test_volatility_recompute_shares_composite_lock():
    # weekly_volatility_recompute and daily_composite_recompute_universe both
    # rewrite the whole snapshot table via _composite_recompute; they must lock
    # on the same name so a recompute overrun can never double-run the universe.
    vol = job_runner.JOB_REGISTRY["weekly_volatility_recompute"]
    daily = job_runner.JOB_REGISTRY["daily_composite_recompute_universe"]
    assert vol.handler is daily.handler
    assert (vol.lock_key or vol.job_id) == (daily.lock_key or daily.job_id)
    assert (vol.lock_key or vol.job_id) == "daily_composite_recompute_universe"


def test_skipped_lock_across_cycles_alerts():
    # A prior scheduled cycle already skipped on the lock; this run skipping too
    # means the lock has been held across more than one cycle -> page.
    fake_alerting = types.ModuleType("app.services.alerting")
    alert_calls: list = []
    fake_alerting.send_alert = lambda *args, **kwargs: alert_calls.append((args, kwargs))

    fake_supabase = FakeSupabase(lock_value=False)
    fake_supabase.rows.append(
        {
            "id": "old-1",
            "job_id": "daily_macro_snapshot",
            "status": "skipped_lock",
            "started_at": "2026-07-01T00:00:00+00:00",
        }
    )

    with (
        patch.object(job_runner, "get_supabase", return_value=fake_supabase),
        patch.dict(sys.modules, {"app.services.alerting": fake_alerting}),
    ):
        result = job_runner.run_job_sync("daily_macro_snapshot")

    assert result["status"] == "skipped_lock"
    assert len(alert_calls) == 1
    subject = alert_calls[0][0][0]
    assert "daily_macro_snapshot" in subject
    assert alert_calls[0][1]["context"]["consecutive_skipped_lock"] == 2


def test_single_skipped_lock_does_not_alert():
    # First skip of a cycle is normal contention, not a wedge -> no page.
    fake_alerting = types.ModuleType("app.services.alerting")
    alert_calls: list = []
    fake_alerting.send_alert = lambda *args, **kwargs: alert_calls.append((args, kwargs))

    fake_supabase = FakeSupabase(lock_value=False)

    with (
        patch.object(job_runner, "get_supabase", return_value=fake_supabase),
        patch.dict(sys.modules, {"app.services.alerting": fake_alerting}),
    ):
        result = job_runner.run_job_sync("daily_macro_snapshot")

    assert result["status"] == "skipped_lock"
    assert alert_calls == []


def test_run_job_records_skipped_when_system_scheduler_paused():
    fake_supabase = FakeSupabase(lock_value=True)

    with (
        patch.object(job_runner, "get_supabase", return_value=fake_supabase),
        patch.dict("os.environ", {"PAUSE_SYSTEM_SCHEDULER": "true"}, clear=False),
    ):
        result = job_runner.run_job_sync("daily_macro_snapshot")

    assert result["status"] == "skipped"
    assert fake_supabase.rows[0]["status"] == "skipped"
    assert fake_supabase.rows[0]["items_skipped"] == 1
    assert fake_supabase.rows[0]["metadata"]["reason"] == "system_scheduler_paused"
    assert fake_supabase.rpc_calls == []


def test_run_job_allows_manual_jobs_when_system_scheduler_paused():
    fake_supabase = FakeSupabase(lock_value=True)

    def fake_handler():
        return {"status": "completed", "items_processed": 2}

    spec = job_runner.JobSpec("manual_job", "manual", fake_handler)
    with (
        patch.object(job_runner, "get_supabase", return_value=fake_supabase),
        patch.dict(job_runner.JOB_REGISTRY, {"manual_job": spec}),
        patch.dict("os.environ", {"PAUSE_SYSTEM_SCHEDULER": "true"}, clear=False),
    ):
        result = job_runner.run_job_sync("manual_job")

    assert result["status"] == "completed"
    assert result["items_processed"] == 2
