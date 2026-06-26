# Clavix Backend Operations Runbook

Last updated: 2026-06-25. Companion to the action plan
(`docs/AUDITS/CLAVIX_BACKEND_ACTION_PLAN_2026-06-25.md`). Captures how the backend
is deployed, recovered, and monitored, plus the non-obvious gotchas found while
hardening it.

## Topology
- Backend: Python/FastAPI in Docker Compose on a single 2 GB DigitalOcean droplet
  (`sansar@134.122.114.241`, key `~/.ssh/id_ed25519`). Container `clavis-backend-1`.
- Code is volume-mounted (`./backend/app:/app/app`), so a job started with
  `docker exec python -m app.jobs.run <job>` always runs the on-disk (deployed) code.
- Data: Supabase Postgres (project `uwvwulhkxtzabykelvam`). Service-role access from
  the backend; ad-hoc reads/DML via the Supabase SQL tooling.
- The running backend == this repo (deploys rsync the repo to `/opt/clavis`).

## Deploy and rollback
- Push to `main` triggers `.github/workflows/deploy-prod.yml`:
  1. Snapshot the current release to `/opt/clavis_backups/release_<ts>.tar.gz`
     (symlinked `last_stable.tar.gz`); keeps the last 5.
  2. `rsync -az --delete` the repo to `/opt/clavis` (explicit excludes; `.env`,
     `apns/`, `RELEASE_SHA` preserved).
  3. `docker compose up -d --build`, install cron, health-gate on
     `https://clavis.andoverdigital.com/health` (20 tries x 5s).
  4. On success: stamp `/opt/clavis/RELEASE_SHA` with the deployed commit.
  5. On any failure: auto-restore `last_stable.tar.gz`, rebuild, re-health-check.
- Manual rollback: `tar xzf /opt/clavis_backups/last_stable.tar.gz -C /opt/clavis && docker compose up -d --build`.

## Disaster recovery (RPO/RTO)
- Code: recoverable from git + the on-box `/opt/clavis_backups` tarballs (RTO ~5 min).
- Data: Supabase Point-In-Time Recovery is the system of record for the DB. **Operator
  action (one-time, not code):** confirm the Supabase PITR window covers >= 7 days, and
  enable DigitalOcean weekly droplet snapshots (~$1-2/mo) for whole-box recovery.
- Most pipeline state is reconstructable: a full universe recompute rebuilds every
  ticker snapshot from source tables in ~20-30 min (see below).

## Jobs
Run any job: `docker exec clavis-backend-1 python -m app.jobs.run <job_id>`.
Key jobs: `daily_macro_snapshot` (FRED), `daily_sector_snapshot` (Polygon ETFs),
`daily_composite_recompute_universe`, `daily_eod_price_capture`,
`active_ticker_news_refresh` (in-process, 4h), `daily_ops_monitor`,
`weekly_fundamentals_sweep`, and the manual `prices_history_backfill`.

### Full universe recompute
`COMPOSITE_RECOMPUTE_FORCE_REFRESH=true COMPOSITE_RECOMPUTE_CONCURRENCY=6 \
 docker exec -d clavis-backend-1 ... python -m app.jobs.run daily_composite_recompute_universe`
- Bounded-concurrency (default 6) + persisted-first price reads make this Supabase-bound
  (~20-30 min) instead of Polygon-bound (~110 min) — **provided** `prices` has >= ~60
  days of history per ticker.
- A dependency guard aborts the run if `macro_regime_snapshots` / `sector_regime_snapshots`
  are stale (> 4 days), to avoid stamping stale inputs as fresh. Bypass for backfills with
  `COMPOSITE_RECOMPUTE_SKIP_DEPENDENCY_GUARD=true`.

### Prices history backfill (`prices_history_backfill`)
- Uses Polygon GROUPED-DAILY (one call returns the whole market for a date), self-paced
  to ~5/min, idempotent (skips existing (ticker, day)). Run when a meaningful share of
  the universe has < 60 days in `prices` (otherwise recompute falls back to per-ticker
  Polygon and slows to the rate limit). `PRICES_BACKFILL_DAYS` controls the window.

## Monitoring and alerting
- `daily_ops_monitor` checks: job cadence, recompute completeness (latest batch + freshness),
  dimension distribution collapse, news coverage, source-vs-snapshot consistency
  (news/macro), and provider degradation (low-success sweeps). It emits a real alert via
  `app/services/alerting.py` only on CRITICAL issues and pings a dead-man's-switch heartbeat
  every run.
- **Operator action (one-time, not code) to receive pages — all free, all optional:**
  set in `backend/.env`: `SENTRY_DSN`, `CLAVIX_SLACK_WEBHOOK_URL` (Slack incoming webhook),
  `CLAVIX_HEARTBEAT_URL` (healthchecks.io ping URL; its absence is what pages you if the
  whole box dies). With none set, alerts still log loudly inside the container.

## Gotchas (hard-won)
- **FRED + custom User-Agent**: FRED's Akamai edge silently tarpits (read-timeout) any
  request carrying a custom `User-Agent` from this host; the default `python-requests` UA
  works. `app/services/fred.py` therefore sets no UA. Do not add one.
- **Docker bridge MTU**: the `clavis-network` bridge is pinned to MTU 1400
  (`docker-compose.yml`); some Akamai-served upstreams blackhole PMTU on the NAT'd bridge,
  so full-size response packets are dropped and reads hang. Keep the cap.
- **Polygon auth cascade**: a single 403 on `polygon_get` trips a shared 5-minute auth
  cooldown that synthesizes 403s for all subsequent calls. The grouped-daily backfill
  deliberately bypasses `polygon_get` (direct request) so an unfinalized-day 403 cannot
  cascade. Be wary of this when adding new Polygon endpoints.
- **Advisory-lock leak over the pooler**: job locks use session-scoped
  `pg_try_advisory_lock` via Supabase RPC; acquire and release can land on different pooled
  backends, so a lock occasionally leaks until its backend recycles (minutes), causing a
  job to `skipped_lock`. Transient and caught by the cadence monitor; a durable fix
  (TTL row-lock) is deferred.
- **2 GB host**: the container is capped at `mem_limit 1500m`; run only ONE heavy
  `docker exec` job at a time. Two concurrent heavy jobs OOM-kill children.

## Deliberately deferred (with reason)
- **Paid data (Polygon Pro ~$250/mo, deeper Finnhub ~$40/mo)**: ~18x the current ~$68/mo
  data spend; unjustified at 2 users. Gate on ~15 Pro subscribers. Keep
  `ENABLE_INTRADAY_SNAPSHOTS` false until then. Real options IV waits on this.
- **Schema drops (legacy `event_analyses` dual-write, 11 always-empty article columns)**:
  need a 2-week clean window + a guard test first; dropping now risks an in-flight writer.
- **APScheduler migration off crontab**: higher effort; the P0 dependency guard already
  covers the urgent half (no recompute on stale inputs).
- **Deep-analysis tier + earnings-shock alerts**: new product surface (new alert type),
  needs product decisions and adds LLM cost; revisit post-launch.
