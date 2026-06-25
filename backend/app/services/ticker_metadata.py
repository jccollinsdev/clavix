from __future__ import annotations
import os
import requests
import time
from threading import Lock
from supabase import create_client, Client
from datetime import datetime, timedelta, timezone
from typing import Optional
from ..config import get_settings
from .polygon import polygon_get

POLYGON_BASE_URL = "https://api.polygon.io/v1"
FINNHUB_BASE_URL = "https://finnhub.io/api/v1"

MAX_RETRIES = 5
RETRY_BASE_DELAY = 5.0

# Minimum spacing between successive calls to a provider, in seconds.
# Finnhub's free tier allows 60 calls/min, so calls must be >=1s apart; we use
# 1.05s (~57/min) for headroom. The old global 0.12s (~500/min) burst past the
# quota after ~100 tickers and 429-failed the rest of the daily universe
# recompute. Override per provider via env if you move to a paid plan.
_MIN_CALL_SPACING_BY_SERVICE = {
    "finnhub": float(os.getenv("FINNHUB_MIN_CALL_SPACING", "1.05")),
    "polygon": float(os.getenv("POLYGON_MIN_CALL_SPACING", "0.12")),
}
_DEFAULT_MIN_CALL_SPACING = 0.12

_last_api_call = {"finnhub": 0.0, "polygon": 0.0}
_service_rate_limit_locks = {"finnhub": Lock(), "polygon": Lock()}

STATIC_METADATA_TTL = timedelta(days=7)
QUOTE_METADATA_TTL = timedelta(hours=24)

_PERSISTABLE_TICKER_METADATA_FIELDS = {
    "ticker",
    "company_name",
    "asset_class",
    "exchange",
    "sector",
    "industry",
    "market_cap",
    "market_cap_bucket",
    "float_shares",
    "avg_daily_dollar_volume",
    "beta",
    "pe_ratio",
    "week_52_high",
    "week_52_low",
    "price",
    "price_as_of",
    "avg_volume",
    "previous_close",
    "open_price",
    "day_high",
    "day_low",
    "last_price_source",
    "volatility_proxy",
    "profitability_profile",
    "leverage_profile",
    "debt_to_equity",
    "fcf_margin",
    "interest_coverage",
    "current_ratio",
    "revenue_growth_trend",
    "fundamentals_updated_at",
    "macro_sensitivity",
    "spread_proxy",
    "is_supported",
    "updated_at",
}

_FINANCIAL_HEALTH_FIELDS = (
    "debt_to_equity",
    "fcf_margin",
    "interest_coverage",
    "current_ratio",
    "revenue_growth_trend",
    "profitability_profile",
    "leverage_profile",
)

KNOWN_ETF_TICKERS = frozenset(
    {
        "AGG",
        "ARKK",
        "BIL",
        "BND",
        "EEM",
        "EFA",
        "GLD",
        "HYG",
        "IAU",
        "IEFA",
        "IJH",
        "IVV",
        "IWM",
        "LQD",
        "QQQ",
        "SCHD",
        "SHY",
        "SLV",
        "SOXX",
        "SPY",
        "TLT",
        "USO",
        "VNQ",
        "VOO",
        "VTI",
        "XLB",
        "XLC",
        "XLE",
        "XLF",
        "XLI",
        "XLK",
        "XLP",
        "XLRE",
        "XLU",
        "XLV",
        "XLY",
    }
)


def _parse_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        normalized = str(value).replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except Exception:
        return None


def _is_recent(existing: dict, field: str, ttl: timedelta) -> bool:
    if existing.get(field) is None:
        return False
    updated_at = _parse_timestamp(existing.get("updated_at"))
    if updated_at is None:
        return False
    return datetime.now(timezone.utc) - updated_at <= ttl


def _fundamentals_are_fresh(existing: dict | None) -> bool:
    if not existing:
        return False
    has_cached_fundamental_shape = any(
        existing.get(field) is not None for field in _FINANCIAL_HEALTH_FIELDS
    ) or existing.get("fundamentals_updated_at") is not None
    if not has_cached_fundamental_shape:
        return False
    updated_at = _parse_timestamp(
        existing.get("fundamentals_updated_at") or existing.get("updated_at")
    )
    if updated_at is None:
        return False
    return datetime.now(timezone.utc) - updated_at <= STATIC_METADATA_TTL


def _reuse_cached_metadata(
    existing: dict | None,
    *,
    prefer_cached_fundamentals: bool = False,
) -> dict | None:
    if not existing:
        return None

    static_fresh = all(
        _is_recent(existing, field, STATIC_METADATA_TTL)
        for field in ("company_name", "sector", "industry", "market_cap")
    )
    quote_fresh = all(
        _is_recent(existing, field, QUOTE_METADATA_TTL)
        for field in ("price", "previous_close", "day_high", "day_low")
    )

    if static_fresh and quote_fresh:
        return existing
    if prefer_cached_fundamentals and static_fresh and _fundamentals_are_fresh(existing):
        return existing
    return None


def _rate_limit(service: str):
    spacing = _MIN_CALL_SPACING_BY_SERVICE.get(service, _DEFAULT_MIN_CALL_SPACING)
    lock = _service_rate_limit_locks.setdefault(service, Lock())
    with lock:
        now = time.monotonic()
        elapsed = now - _last_api_call.get(service, 0)
        if elapsed < spacing:
            time.sleep(spacing - elapsed)
        _last_api_call[service] = time.monotonic()


def _retry_request(fn, *args, **kwargs):
    """Execute fn(*args, **kwargs) with exponential backoff on 429/500/503."""
    last_exc = None
    for attempt in range(MAX_RETRIES):
        try:
            result = fn(*args, **kwargs)
            if hasattr(result, "status_code"):
                if result.status_code == 429:
                    delay = RETRY_BASE_DELAY * (2**attempt)
                    print(
                        f"429 rate limit, sleeping {delay:.1f}s before retry {attempt + 1}"
                    )
                    time.sleep(delay)
                    last_exc = Exception(f"429 rate limit on attempt {attempt + 1}")
                    continue
                if result.status_code == 500 or result.status_code == 503:
                    delay = RETRY_BASE_DELAY * (2**attempt)
                    time.sleep(delay)
                    last_exc = Exception(
                        f"{result.status_code} server error on attempt {attempt + 1}"
                    )
                    continue
                if result.status_code != 200:
                    return result
            return result
        except Exception as e:
            last_exc = e
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_BASE_DELAY * (2**attempt)
                time.sleep(delay)
    if last_exc:
        raise last_exc
    return None


def get_polygon_client() -> str:
    return get_settings().polygon_api_key


def get_finnhub_client() -> str:
    return get_settings().finnhub_api_key


def get_supabase_admin() -> Client:
    return create_client(
        os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    )


def fetch_ticker_details_from_polygon(ticker: str) -> dict | None:
    api_key = get_polygon_client()
    if not api_key:
        return None

    try:
        url = f"{POLYGON_BASE_URL}/meta/symbols/{ticker.upper()}"
        params = {"apiKey": api_key}
        resp = polygon_get(url, params=params, timeout=10)
        if resp is None:
            return None
        if resp.status_code == 200:
            data = resp.json()
            return {
                "name": data.get("name"),
                "symbol": data.get("symbol"),
                "exchange": data.get("exchange"),
                "asset_class": _map_polygon_type_to_asset_class(data.get("type")),
            }
        return None
    except Exception as e:
        print(f"Error fetching Polygon ticker details for {ticker}: {e}")
        return None


def fetch_ticker_details_from_finnhub(ticker: str) -> dict | None:
    api_key = get_finnhub_client()
    if not api_key:
        return None

    _rate_limit("finnhub")
    try:
        profile_url = f"{FINNHUB_BASE_URL}/stock/profile2"
        metrics_url = f"{FINNHUB_BASE_URL}/stock/metric"
        quote_url = f"{FINNHUB_BASE_URL}/quote"
        ticker_upper = ticker.upper()

        profile_resp = _retry_request(
            requests.get,
            profile_url,
            params={"symbol": ticker_upper, "token": api_key},
            timeout=10,
        )
        _rate_limit("finnhub")
        metrics_resp = _retry_request(
            requests.get,
            metrics_url,
            params={"symbol": ticker_upper, "token": api_key, "metric": "all"},
            timeout=10,
        )
        _rate_limit("finnhub")
        quote_resp = _retry_request(
            requests.get,
            quote_url,
            params={"symbol": ticker_upper, "token": api_key},
            timeout=10,
        )

        if not profile_resp or not metrics_resp or not quote_resp:
            print(f"Retry failed for Finnhub ticker details for {ticker}")
            return None

        profile_data = profile_resp.json() if profile_resp.status_code == 200 else {}
        metrics_data = metrics_resp.json() if metrics_resp.status_code == 200 else {}
        quote_data = quote_resp.json() if quote_resp.status_code == 200 else {}
        metric_values = metrics_data.get("metric", {})

        market_cap = profile_data.get("marketCapitalization")
        if market_cap:
            market_cap = float(market_cap) * 1e6

        avg_volume = None
        if "volAvg" in metric_values:
            avg_volume = metric_values["volAvg"]

        ten_day_avg = None
        if "10DayAverageTradingVolume" in metric_values:
            ten_day_avg = metric_values["10DayAverageTradingVolume"]

        price_for_volume = quote_data.get("c") or profile_data.get("price")
        if ten_day_avg and price_for_volume:
            avg_daily_dollar_volume = float(ten_day_avg) * 1e6 * float(price_for_volume)
        elif avg_volume and price_for_volume:
            avg_daily_dollar_volume = float(avg_volume) * 1e6 * float(price_for_volume)
        else:
            avg_daily_dollar_volume = None

        beta = metric_values.get("beta")
        float_shares = metric_values.get("sharesFloat")

        debt_to_equity = _metric_as_float(metric_values, "totalDebt/totalEquityAnnual")
        if debt_to_equity is None:
            debt_to_equity = _metric_as_float(metric_values, "longTermDebt/equityAnnual")

        fcf_margin = None
        fcf = _metric_as_float(metric_values, "freeCashFlowAnnual")
        rev = _metric_as_float(metric_values, "revenueAnnual")
        if fcf is not None and rev and rev > 0:
            fcf_margin = fcf / rev
        if fcf_margin is None:
            # Finnhub's free basic-financials does NOT expose freeCashFlowAnnual/revenueAnnual,
            # but it does expose P/FCF-per-share and revenue-per-share. Derive the margin as
            # fcf_per_share / revenue_per_share, where fcf_per_share = price / pfcfShare.
            price_for_fcf = _safe_metric_float(quote_data.get("c")) or _safe_metric_float(
                profile_data.get("price")
            )
            pfcf = _metric_as_float(metric_values, "pfcfShareTTM") or _metric_as_float(
                metric_values, "pfcfShareAnnual"
            )
            rev_ps = _metric_as_float(metric_values, "revenuePerShareTTM") or _metric_as_float(
                metric_values, "revenuePerShareAnnual"
            )
            if price_for_fcf and pfcf and pfcf != 0 and rev_ps and rev_ps > 0:
                fcf_per_share = price_for_fcf / pfcf
                fcf_margin = round(fcf_per_share / rev_ps, 4)

        # Finnhub free tier exposes interest coverage as netInterestCoverage{Annual,TTM};
        # the older interestCoverageAnnual key does not exist (it was 100% NULL). Try the
        # real keys first, then fall back to EBIT/interest-expense.
        interest_coverage = None
        for _ic_key in (
            "netInterestCoverageAnnual",
            "netInterestCoverageTTM",
            "interestCoverageAnnual",
            "interestCoverageQuarterly",
        ):
            raw = metric_values.get(_ic_key)
            if raw is not None:
                interest_coverage = _safe_metric_float(raw)
                if interest_coverage is not None:
                    break
        if interest_coverage is None:
            ebit_raw = _metric_as_float(metric_values, "ebitAnnual")
            int_exp_raw = _metric_as_float(metric_values, "interestExpenseAnnual")
            if ebit_raw is not None and int_exp_raw is not None and int_exp_raw > 0:
                interest_coverage = round(ebit_raw / int_exp_raw, 2)

        current_ratio = _metric_as_float(metric_values, "currentRatioAnnual")
        if current_ratio is None:
            current_ratio = _metric_as_float(metric_values, "currentRatioQuarterly")

        revenue_growth_trend = None
        rev_growth_yoy = _metric_as_float(metric_values, "revenueGrowthQuarterlyYoy")
        rev_growth_3y = _metric_as_float(metric_values, "revenueGrowth3Y")
        if rev_growth_yoy is not None:
            revenue_growth_trend = rev_growth_yoy
        elif rev_growth_3y is not None:
            revenue_growth_trend = rev_growth_3y

        profitability_profile = _get_profitability_profile(
            _metric_as_float(metric_values, "netProfitMarginAnnual"),
            _metric_as_float(metric_values, "roeAnnual"),
        )
        leverage_profile = _get_leverage_profile(debt_to_equity)
        macro_sens = _get_macro_sensitivity(beta)

        return {
            "company_name": profile_data.get("name"),
            "ticker": ticker.upper(),
            "exchange": profile_data.get("exchange"),
            "sector": profile_data.get("finnhubIndustry") or profile_data.get("sector"),
            "industry": profile_data.get("industry"),
            "market_cap": market_cap,
            "avg_daily_dollar_volume": avg_daily_dollar_volume,
            "beta": beta,
            "float_shares": float_shares,
            "asset_class": _infer_asset_class_from_finnhub(ticker_upper, profile_data),
            "pe_ratio": metric_values.get("peTTM")
            or metric_values.get("peNormalizedAnnual"),
            "week_52_high": metric_values.get("52WeekHigh"),
            "week_52_low": metric_values.get("52WeekLow"),
            "price": quote_data.get("c"),
            "previous_close": quote_data.get("pc"),
            "open_price": quote_data.get("o"),
            "day_high": quote_data.get("h"),
            "day_low": quote_data.get("l"),
            "price_as_of": datetime.utcnow().isoformat(),
            "avg_volume": avg_volume or ten_day_avg,
            "last_price_source": "finnhub",
            "is_supported": True,

            "debt_to_equity": debt_to_equity,
            "fcf_margin": fcf_margin,
            "interest_coverage": interest_coverage,
            "current_ratio": current_ratio,
            "revenue_growth_trend": revenue_growth_trend,
            "profitability_profile": profitability_profile,
            "leverage_profile": leverage_profile,
            "macro_sensitivity": macro_sens,
        }
    except Exception as e:
        print(f"Error fetching Finnhub ticker details for {ticker}: {e}")
        return None


def fetch_market_cap_from_polygon(ticker: str) -> float | None:
    api_key = get_polygon_client()
    if not api_key:
        return None

    try:
        url = f"{POLYGON_BASE_URL}/meta/symbols/{ticker.upper()}"
        params = {"apiKey": api_key}
        resp = polygon_get(url, params=params, timeout=10)
        if resp is None:
            return None
        if resp.status_code == 200:
            data = resp.json()
            mc = data.get("market_cap")
            if mc:
                return float(mc)
        return None
    except Exception as e:
        print(f"Error fetching market cap for {ticker}: {e}")
        return None


def fetch_volatility_proxy(ticker: str, days: int = 30) -> float | None:
    from .polygon import fetch_aggs

    aggs = fetch_aggs(ticker, days)
    if not aggs or len(aggs) < 5:
        return None

    returns = []
    for i in range(1, len(aggs)):
        prev_close = aggs[i - 1].get("c", 0)
        curr_close = aggs[i].get("c", 0)
        if prev_close > 0:
            ret = (curr_close - prev_close) / prev_close
            returns.append(ret)

    if not returns:
        return None

    import statistics

    std_dev = statistics.stdev(returns) if len(returns) > 1 else 0
    return std_dev


def _map_polygon_type_to_asset_class(type_str: str | None) -> str:
    if not type_str:
        return "other"
    type_lower = type_str.lower()
    if "etf" in type_lower:
        return "etf"
    if "common" in type_lower:
        return "large_cap_equity"
    if "adr" in type_lower or "gdr" in type_lower:
        return "adr"
    return "other"


def _infer_asset_class_from_finnhub(ticker: str, profile_data: dict) -> str:
    ticker_upper = ticker.upper()
    text = " ".join(
        str(profile_data.get(key) or "")
        for key in ("name", "finnhubIndustry", "sector", "industry")
    ).lower()
    if ticker_upper in KNOWN_ETF_TICKERS or "etf" in text or "exchange traded" in text:
        return "etf"
    return "large_cap_equity"


def _get_market_cap_bucket(market_cap: float | None) -> str | None:
    if market_cap is None:
        return None
    if market_cap >= 500e9:
        return "very_high"
    if market_cap >= 50e9:
        return "high"
    if market_cap >= 10e9:
        return "moderate_high"
    if market_cap >= 2e9:
        return "moderate"
    if market_cap >= 500e6:
        return "low_moderate"
    if market_cap >= 100e6:
        return "low"
    return "very_low"


def _get_profitability_profile(
    profit_margin: float | None,
    roe: float | None,
) -> str:
    if profit_margin is None and roe is None:
        return "mixed"
    if profit_margin is not None and profit_margin > 0.1:
        return "profitable"
    if roe is not None and roe > 0.15:
        return "profitable"
    if profit_margin is not None and profit_margin < 0:
        return "unprofitable"
    return "mixed"


def _get_leverage_profile(debt_to_equity: float | None) -> str:
    if debt_to_equity is None:
        return "moderate"
    if debt_to_equity <= 0.3:
        return "low"
    if debt_to_equity <= 0.7:
        return "low"
    if debt_to_equity <= 1.5:
        return "moderate"
    if debt_to_equity <= 3.0:
        return "high"
    return "very_high"


def _safe_metric_float(value) -> float | None:
    try:
        if value is None or value == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _metric_as_float(metric_values: dict, key: str) -> float | None:
    raw = metric_values.get(key)
    return _safe_metric_float(raw)


def _get_macro_sensitivity(beta) -> str:
    beta_val = _safe_metric_float(beta)
    if beta_val is None:
        return "moderate"
    if beta_val <= 0.6:
        return "low"
    if beta_val <= 1.2:
        return "moderate"
    if beta_val <= 1.8:
        return "high"
    return "very_high"


def build_ticker_metadata(ticker: str, finnhub_data: dict | None = None) -> dict | None:
    finnhub_data = finnhub_data or fetch_ticker_details_from_finnhub(ticker)
    if not finnhub_data:
        return None

    market_cap = finnhub_data.get("market_cap")
    float_shares = finnhub_data.get("float_shares")
    beta = finnhub_data.get("beta")
    volatility = None
    if isinstance(beta, (int, float)):
        volatility = min(max(abs(float(beta)) / 4.0, 0.05), 1.0)

    market_cap_bucket = _get_market_cap_bucket(market_cap)
    profitability_profile = finnhub_data.get("profitability_profile")
    leverage_profile = finnhub_data.get("leverage_profile")

    spread_proxy = None
    if finnhub_data.get("avg_daily_dollar_volume"):
        spread_proxy = 0.001

    now_iso = datetime.now(timezone.utc).isoformat()

    # Only stamp fundamentals as freshly-updated when the refetch produced at least one
    # real fundamental value. A blank refetch used to stamp the row "fresh" anyway, which
    # masked an empty pull and suppressed future backfill (false freshness).
    _has_real_fundamentals = any(
        finnhub_data.get(k) is not None
        for k in (
            "debt_to_equity",
            "fcf_margin",
            "interest_coverage",
            "current_ratio",
            "revenue_growth_trend",
        )
    )

    return {
        "ticker": ticker.upper(),
        "company_name": finnhub_data.get("company_name"),
        "asset_class": finnhub_data.get("asset_class"),
        "exchange": finnhub_data.get("exchange"),
        "sector": finnhub_data.get("sector"),
        "industry": finnhub_data.get("industry"),
        "market_cap": market_cap,
        "market_cap_bucket": market_cap_bucket,
        "float_shares": float_shares,
        "avg_daily_dollar_volume": finnhub_data.get("avg_daily_dollar_volume"),
        "beta": finnhub_data.get("beta"),
        "pe_ratio": finnhub_data.get("pe_ratio"),
        "week_52_high": finnhub_data.get("week_52_high"),
        "week_52_low": finnhub_data.get("week_52_low"),
        "price": finnhub_data.get("price"),
        "price_as_of": finnhub_data.get("price_as_of"),
        "avg_volume": finnhub_data.get("avg_volume"),
        "previous_close": finnhub_data.get("previous_close"),
        "open_price": finnhub_data.get("open_price"),
        "day_high": finnhub_data.get("day_high"),
        "day_low": finnhub_data.get("day_low"),
        "last_price_source": finnhub_data.get("last_price_source"),
        "volatility_proxy": volatility,
        "profitability_profile": profitability_profile,
        "leverage_profile": leverage_profile,
        "debt_to_equity": finnhub_data.get("debt_to_equity"),
        "fcf_margin": finnhub_data.get("fcf_margin"),
        "interest_coverage": finnhub_data.get("interest_coverage"),
        "current_ratio": finnhub_data.get("current_ratio"),
        "revenue_growth_trend": finnhub_data.get("revenue_growth_trend"),
        "fundamentals_updated_at": now_iso if _has_real_fundamentals else None,
        "macro_sensitivity": finnhub_data.get("macro_sensitivity"),
        "spread_proxy": spread_proxy,
        "is_supported": True,
        "updated_at": now_iso,
    }


def upsert_ticker_metadata(
    supabase: Client,
    ticker: str,
    finnhub_data: dict | None = None,
    *,
    prefer_cached_fundamentals: bool = False,
) -> dict | None:
    existing = (
        supabase.table("ticker_metadata")
        .select("*")
        .eq("ticker", ticker.upper())
        .limit(1)
        .execute()
        .data
    )
    existing_row = existing[0] if existing else None
    if finnhub_data is None:
        cached = _reuse_cached_metadata(
            existing_row,
            prefer_cached_fundamentals=prefer_cached_fundamentals,
        )
        if cached:
            return cached

    metadata = build_ticker_metadata(ticker, finnhub_data=finnhub_data)
    if not metadata:
        return None
    persisted_metadata = {
        key: value
        for key, value in metadata.items()
        if key in _PERSISTABLE_TICKER_METADATA_FIELDS
    }

    if existing_row:
        supabase.table("ticker_metadata").update(persisted_metadata).eq(
            "ticker", ticker.upper()
        ).execute()
        return metadata

    supabase.table("ticker_metadata").insert(persisted_metadata).execute()
    return metadata


def refresh_all_positions_metadata(user_id: str) -> int:
    supabase = get_supabase_admin()

    positions = (
        supabase.table("positions")
        .select("id, ticker")
        .eq("user_id", user_id)
        .execute()
        .data
    )

    updated = 0
    for position in positions:
        ticker = position.get("ticker")
        if ticker:
            result = upsert_ticker_metadata(supabase, ticker)
            if result:
                updated += 1

    return updated
