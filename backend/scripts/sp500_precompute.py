"""S&P 500 risk rating precomputation script.

Runs full AI analysis for all S&P 500 tickers with safety controls:
- Skips tickers refreshed in last 24h
- Batches of 15 with rate limiting between batches
- Stops on 5 consecutive model failures
- Logs progress continuously

Usage (from inside backend container):
    python -m scripts.sp500_precompute
    python -m scripts.sp500_precompute --limit 50        # just 50 tickers
    python -m scripts.sp500_precompute --batch-size 10   # smaller batches
    python -m scripts.sp500_precompute --skip-structural  # skip metadata refresh
"""

import argparse
import asyncio
import json
import sys
import time

_BATCH_DEFAULT = 15
_SKIP_STRUCTURAL_DEFAULT = False
_CONSECUTIVE_FAIL_LIMIT = 5
_INTER_BATCH_DELAY = 5


def _print_summary(result: dict) -> None:
    status = result.get("status", "unknown")
    requested = result.get("requested", 0)
    refreshed = result.get("refreshed", 0)
    failed = result.get("failed", [])
    print(f"  Result: status={status} refreshed={refreshed}/{requested} failures={len(failed)}", flush=True)
    if failed:
        for f in failed[:5]:
            ticker = f.get("ticker", f.get("batch", "?"))
            err = f.get("error", "unknown")[:120]
            print(f"    FAIL: {ticker}: {err}", flush=True)


def _check_db_health() -> bool:
    try:
        from app.services.supabase import get_supabase
        sb = get_supabase()
        result = sb.table("ticker_universe").select("ticker").eq("index_membership", "SP500").eq("is_active", True).limit(1).execute()
        return bool(result.data)
    except Exception as e:
        print(f"  DB health check FAILED: {e}", flush=True)
        return False


def _count_fresh_snapshots() -> int:
    try:
        from app.services.supabase import get_supabase
        from datetime import date
        sb = get_supabase()
        today = date.today().isoformat()
        result = sb.table("ticker_risk_snapshots").select("ticker", count="exact").eq("snapshot_date", today).like("methodology_version", "%ai%").execute()
        return result.count if hasattr(result, 'count') else len(result.data or [])
    except Exception:
        return 0


async def run(args: argparse.Namespace) -> None:
    from app.pipeline.scheduler import run_sp500_full_ai_analysis_fast
    from app.services.ticker_cache_service import list_active_sp500_tickers, ensure_sp500_universe_seeded
    from app.services.supabase import get_supabase

    batch_size = args.batch_size
    limit = args.limit
    skip_structural = args.skip_structural

    print("=" * 70, flush=True)
    print("S&P 500 RISK RATING PRECOMPUTATION", flush=True)
    print("=" * 70, flush=True)

    if not _check_db_health():
        print("ABORT: Database health check failed. Cannot proceed.", flush=True)
        sys.exit(1)

    sb = get_supabase()
    ensure_sp500_universe_seeded(sb)
    all_tickers = list_active_sp500_tickers(sb, limit=None)
    print(f"Universe: {len(all_tickers)} active S&P 500 tickers", flush=True)

    if limit:
        all_tickers = all_tickers[:limit]
        print(f"Limit applied: processing first {limit} tickers", flush=True)

    fresh_ai = _count_fresh_snapshots()
    print(f"AI-scored snapshots already fresh today: {fresh_ai}", flush=True)
    print(f"Batch size: {batch_size}", flush=True)
    print(f"Skip structural: {skip_structural}", flush=True)
    print(f"Consecutive fail limit: {_CONSECUTIVE_FAIL_LIMIT}", flush=True)
    print(f"Inter-batch delay: {_INTER_BATCH_DELAY}s", flush=True)
    print("-" * 70, flush=True)

    total_batches = (len(all_tickers) + batch_size - 1) // batch_size
    print(f"Total batches: {total_batches}", flush=True)
    print()

    success_count = 0
    failure_count = 0
    consecutive_failures = 0
    total_start = time.time()

    for batch_idx in range(0, len(all_tickers), batch_size):
        batch_num = batch_idx // batch_size + 1
        batch_tickers = all_tickers[batch_idx:batch_idx + batch_size]
        batch_start = time.time()

        elapsed_total = time.time() - total_start
        rate = batch_idx / elapsed_total if elapsed_total > 0 else 0
        eta_remaining = (len(all_tickers) - batch_idx) / rate if rate > 0 else 0

        print(f"[Batch {batch_num}/{total_batches}] Tickers: {', '.join(batch_tickers[:5])}{'...' if len(batch_tickers) > 5 else ''} ({len(batch_tickers)} tickers)", flush=True)
        print(f"  Progress: {batch_idx}/{len(all_tickers)} | Success: {success_count} | Fail: {failure_count} | ConsecFail: {consecutive_failures} | ETA: {eta_remaining/60:.1f}min", flush=True)

        try:
            result = await run_sp500_full_ai_analysis_fast(
                limit=None,
                job_type="backfill",
                batch_size=len(batch_tickers),
                skip_structural=skip_structural,
                tickers_override=batch_tickers,
            )
            _print_summary(result)

            if result.get("status") == "ok":
                success_count += len(batch_tickers)
                consecutive_failures = 0
            elif result.get("status") == "partial":
                batch_success = result.get("refreshed", 0)
                batch_fail = len(result.get("failed", []))
                success_count += batch_success
                failure_count += batch_fail
                consecutive_failures = batch_fail
            else:
                failure_count += len(batch_tickers)
                consecutive_failures += len(batch_tickers)

        except Exception as exc:
            print(f"  BATCH EXCEPTION: {exc}", flush=True)
            failure_count += len(batch_tickers)
            consecutive_failures += len(batch_tickers)

        if not _check_db_health():
            print("ABORT: DB write error detected. Stopping immediately.", flush=True)
            break

        if consecutive_failures >= _CONSECUTIVE_FAIL_LIMIT:
            print(f"ABORT: {_CONSECUTIVE_FAIL_LIMIT} consecutive failures. Stopping immediately.", flush=True)
            break

        batch_elapsed = time.time() - batch_start
        print(f"  Batch took {batch_elapsed:.1f}s", flush=True)

        if batch_idx + batch_size < len(all_tickers):
            print(f"  Sleeping {_INTER_BATCH_DELAY}s before next batch...", flush=True)
            await asyncio.sleep(_INTER_BATCH_DELAY)

        print(flush=True)

    total_elapsed = time.time() - total_start
    fresh_ai_final = _count_fresh_snapshots()

    print("=" * 70, flush=True)
    print("FINAL REPORT", flush=True)
    print("=" * 70, flush=True)
    print(f"Total tickers processed: {min(batch_idx + batch_size, len(all_tickers))}/{len(all_tickers)}", flush=True)
    print(f"Successes: {success_count}", flush=True)
    print(f"Failures: {failure_count}", flush=True)
    print(f"Fresh AI snapshots today (final): {fresh_ai_final}", flush=True)
    print(f"Total elapsed: {total_elapsed/60:.1f} minutes", flush=True)

    if failure_count == 0 and consecutive_failures < _CONSECUTIVE_FAIL_LIMIT:
        print("\nSTATUS: READY — All tickers have fresh AI risk ratings.", flush=True)
    else:
        print(f"\nSTATUS: PARTIAL — {failure_count} failures. Review logs and re-run for failed tickers.", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="S&P 500 risk rating precomputation")
    parser.add_argument("--limit", type=int, default=None, help="Max tickers to process")
    parser.add_argument("--batch-size", type=int, default=_BATCH_DEFAULT, help="Tickers per batch")
    parser.add_argument("--skip-structural", action="store_true", default=_SKIP_STRUCTURAL_DEFAULT, help="Skip metadata refresh step")
    args = parser.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()