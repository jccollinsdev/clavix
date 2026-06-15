# Report 3: Backend Management and Operations Runbook (2026-06-14)

You asked, directly: how will we manage the backend in production, and are we even managing it? Honest answer: today the backend is **operated reactively, not monitored**. It runs reliably on its own (RestartCount 0, 14-day host uptime), but nobody and nothing is watching it. The recompute failed silently for five straight days before a human happened to look. This report is the plan to change that, scaled to where you are (one tester now, a small launch soon).

---

## 1. What "managing the backend" means here, and the current gaps

| Capability | Today | Gap |
|---|---|---|
| Service up/down detection | None automated | If the droplet or container hangs, you find out by opening the app |
| Container auto-recovery | `unless-stopped` only | Recovers from a clean exit, not from a hang or a wedged event loop |
| Scheduled-job failure alerts | None | Recompute failed 5 days silently |
| Error aggregation | Sentry hooks exist in `backend/app/main.py` and `config.py` | Confirm the DSN is set and events actually arrive |
| Metrics and dashboards | None | No request rate, latency, or error-rate view |
| Log retention and search | `docker logs` only (ephemeral) | Logs vanish on redeploy; no history |
| Backups | Supabase plan includes them; backend is stateless | Confirm Supabase backup cadence and test a restore once |
| Deploy process | Manual SSH `git pull` plus `docker compose` | Works, but no rollback step and no post-deploy verification gate |
| Capacity headroom | 1.9 GB RAM, single vCPU, single droplet | No redundancy; fine for beta, thin for scale |

The good news: the architecture is forgiving. Most heavy work is precomputed batch jobs, not per-request, and reads are served fast from Supabase behind Cloudflare. So you do not need a complex platform. You need three cheap things: an uptime check, a job-failure alert, and confirmed error aggregation.

---

## 2. The minimum monitoring to add before the beta (about half a day)

### 2.1 External uptime check (highest value, lowest effort)
Point a free external monitor (UptimeRobot, Better Stack, or Cronitor free tier) at `https://clavis.andoverdigital.com/health` every 1 to 5 minutes, alerting to email or SMS on two consecutive failures. This is the single most important addition: it tells you the app is down before your tester does. The `/health` endpoint already reports apns, snaptrade, minimax, and supabase status, so a content check on `"status":"ok"` also catches partial degradation.

### 2.2 Scheduled-job failure alert
The recompute failing silently for five days is the clearest "we are not managing this" signal. Add a job-failure notification: when a `job_runs` row finishes with `status = failed` (or `items_failed` over a threshold), send a message (email, or a Slack or Telegram webhook). Two ways to do it, pick one:
- In-process: after each scheduled job writes its `job_runs` row, if it failed, post to a webhook. Smallest change.
- External: a tiny cron (or a Supabase scheduled function) that queries `job_runs` for failures in the last 24 hours and alerts. Decouples alerting from the job that might be broken.
Pair this with the `error_json` capture from report 2 so the alert carries the actual exception.

### 2.3 Confirm Sentry is live
Sentry is referenced in the backend. Verify the DSN env var is set in the container and trigger a test error to confirm events arrive. If it is wired, you already have error aggregation for free; you just need to know it works. Add a Sentry release tag on deploy so you can tie errors to commits.

---

## 3. Deploy and rollback (make the current process safe)

Current deploy (from CLAUDE.md), which is fine as the mechanism:
```
ssh clavix-vps 'cd /opt/clavis && sudo -n git pull origin main && sudo -n docker compose restart backend'
```
Note: tonight's container history shows several rebuilds, so the real path rebuilds the image. Standardize on:
```
ssh clavix-vps 'cd /opt/clavis && sudo -n git pull origin main && sudo -n docker compose up -d --build backend'
```
Add two guardrails:
- **Post-deploy verification gate.** After deploy, automatically `curl /health` and run `python -m app.scripts.verify_data_truth` (already exists). If either fails, you know immediately.
- **Rollback step.** Record the previous commit SHA before pulling. Rollback is `git checkout <prev_sha> && docker compose up -d --build backend`. Write the two SHAs to a known file on each deploy so rollback is one command under stress.

Also note the VPS is currently 2 commits behind local `main`, but both are iOS-only, so the backend is effectively current. Keep an eye on backend-affecting commits actually reaching the droplet.

---

## 4. Data freshness as an operational concern

Freshness is your trust currency, so treat it as an SLO, not a hope.
- **Define the SLO:** every universe ticker has a snapshot no older than N days (start with N = 2 on weekdays).
- **Measure it:** the freshness query in report 2 is the SLO check. Run it daily as part of the job-failure alert; if more than, say, 5% of the universe is older than N days, alert.
- **Protect the input:** the recompute survives only by throttling to 60/min on the Finnhub free tier, which makes it take about 140 minutes and stay fragile. Before public launch, move Finnhub and Polygon to paid tiers (see report 5) so freshness does not depend on a fragile throttle. Until then, the throttle plus the job-failure alert is an acceptable beta posture.

---

## 5. Scaling and resilience (what to do, and when)

You do not need this for the beta. Plan it for public launch.

- **Single droplet is a single point of failure.** One box, one container, behind Cloudflare Tunnel. If the droplet dies, the app is down with no failover. For a paid product this is the main resilience gap. Mitigations, cheapest first: enable DigitalOcean droplet backups (a few dollars a month), document a rebuild-from-repo procedure, and only later consider a second droplet or a managed platform.
- **Vertical headroom is thin.** 1.9 GB RAM and a single vCPU run a 140-minute CPU-bound recompute. With a handful of users this is fine because the heavy work is batch and the reads are precomputed. Resize the droplet (more RAM and vCPU) before the recompute and live traffic start to overlap badly, which is a "hundreds of active users" problem, not a beta problem.
- **Reads scale well.** Because grades, digests, and news are precomputed into Supabase and served fast, read traffic scales with Supabase and Cloudflare, not with your droplet. The constraint at scale is the batch pipeline and the data-API quotas, not request serving.
- **Supabase tier:** you are on the $25 plan, which includes daily backups and point-in-time recovery. Confirm the retention window and do one test restore so you know it works before you depend on it.

---

## 6. The standing operations checklist (after launch)

Daily (automated, you only look when alerted):
- `/health` is ok (external monitor).
- No `job_runs` failures in the last 24 hours.
- Universe freshness within SLO.

Weekly (5 minutes by hand, or automated):
- Skim Sentry for new error signatures.
- Confirm digests and alerts generated for all active users.
- Check disk and memory headroom on the droplet (`df -h`, `free -h`).

Per deploy:
- Record prev SHA, deploy with `--build`, run the post-deploy health and data-truth checks, watch Sentry for a spike.

This is a lightweight regime that fits a solo operator and turns "we hope it is fine" into "we are told when it is not."
