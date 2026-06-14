import asyncio
import logging
from fastapi import APIRouter, Request, HTTPException, Depends, Query
from datetime import datetime
from ..services.polygon import (
    fetch_price_history,
    fetch_aggs,
    history_covers_days,
    normalize_price_history,
    store_prices,
)

logger = logging.getLogger(__name__)

router = APIRouter()


def get_user_id(request: Request) -> str:
    return request.state.user_id


def _polygon_backfill(ticker: str, days: int) -> list[dict]:
    """Blocking Polygon fetch + store. Rate-limited (5s/call), so this must
    never run on the user-facing request path. Returns normalized prices."""
    aggs = fetch_aggs(ticker, days)
    if not aggs:
        return []
    formatted_prices = [
        {
            "ticker": ticker,
            "price": agg["c"],
            "recorded_at": datetime.fromtimestamp(agg["t"] / 1000).isoformat(),
        }
        for agg in aggs
    ]
    store_prices(ticker, aggs)
    return normalize_price_history(formatted_prices)


async def _backfill_in_background(ticker: str, days: int) -> None:
    try:
        await asyncio.to_thread(_polygon_backfill, ticker, days)
    except Exception as exc:  # never surface background failures
        logger.warning("price_backfill_failed ticker=%s error=%s", ticker, exc)


@router.get("/{ticker}")
async def get_price_history(
    ticker: str,
    days: int = Query(default=30, ge=1, le=365),
    user_id: str = Depends(get_user_id),
):
    ticker = ticker.upper()
    history = await asyncio.to_thread(fetch_price_history, ticker, days)

    if history:
        # Serve stored history immediately. If it does not yet span the full
        # window, refresh from Polygon in the background so the next load is
        # complete, but never block the user on the rate-limited Polygon call.
        if not history_covers_days(history, days):
            asyncio.create_task(_backfill_in_background(ticker, days))
        return {"ticker": ticker, "prices": history}

    # No stored history at all (rare): one-time synchronous fetch so the first
    # viewer of a brand-new ticker still gets a chart.
    prices = await asyncio.to_thread(_polygon_backfill, ticker, days)
    return {"ticker": ticker, "prices": prices}
