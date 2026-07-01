from __future__ import annotations

from datetime import date, datetime
import io
import logging
import re
import xml.etree.ElementTree as ET
from typing import Any
import zipfile

import requests

from app.services.supabase import get_supabase


logger = logging.getLogger(__name__)

# Last updated: 2026-06-17. Refresh periodically — these are used only as
# a fallback when live-fetch from issuer APIs fails.
ETF_STATIC_SEEDS: dict[str, list[tuple[str, float]]] = {
    "SPY":  [("AAPL",7.1),("MSFT",6.8),("NVDA",6.2),("AMZN",3.8),("META",2.9),("AVGO",2.2),("GOOGL",2.1),("GOOG",1.8),("BRK.B",1.7),("TSLA",1.6)],
    "VOO":  [("AAPL",7.1),("MSFT",6.8),("NVDA",6.2),("AMZN",3.8),("META",2.9),("AVGO",2.2),("GOOGL",2.1),("GOOG",1.8),("BRK.B",1.7),("TSLA",1.6)],
    "IVV":  [("AAPL",7.1),("MSFT",6.8),("NVDA",6.2),("AMZN",3.8),("META",2.9),("AVGO",2.2),("GOOGL",2.1),("GOOG",1.8),("BRK.B",1.7),("TSLA",1.6)],
    "QQQ":  [("NVDA",9.2),("MSFT",8.1),("AAPL",7.9),("AMZN",5.2),("AVGO",4.6),("META",4.2),("NFLX",2.7),("COST",2.6),("GOOGL",2.5),("GOOG",2.4)],
    "VTI":  [("AAPL",6.2),("MSFT",5.8),("NVDA",5.4),("AMZN",3.2),("META",2.5),("AVGO",1.9),("GOOGL",1.8),("GOOG",1.6),("BRK.B",1.5),("TSLA",1.4)],
    "IWM":  [("FTAI",0.6),("SPSC",0.5),("RMBS",0.5),("CORT",0.5),("VRRM",0.4),("SKYW",0.4),("YELP",0.4),("CRVL",0.4),("MGNI",0.4),("PLXS",0.4)],
    "SOXX": [("NVDA",8.5),("AVGO",8.3),("AMD",5.4),("INTC",4.9),("QCOM",4.7),("TXN",4.6),("MU",4.5),("AMAT",4.4),("KLAC",4.1),("LRCX",4.0)],
    "SCHD": [("AVGO",4.8),("CVX",4.4),("PFE",4.2),("HD",4.0),("UPS",3.9),("T",3.8),("KO",3.7),("ABBV",3.6),("CSCO",3.5),("IBM",3.4)],
    "ARKK": [("TSLA",10.5),("ROKU",7.3),("COIN",6.8),("SQ",6.2),("PATH",5.5),("EXAS",4.8),("BEAM",4.5),("HOOD",4.2),("TDOC",4.0),("TWLO",3.8)],
    "XLK":  [("MSFT",22.5),("NVDA",21.4),("AAPL",5.1),("AVGO",4.6),("ORCL",4.1),("CRM",3.4),("ACN",2.8),("AMD",2.6),("ADBE",2.4),("QCOM",2.3)],
    "XLF":  [("BRK.B",13.6),("JPM",12.8),("V",8.4),("MA",7.1),("BAC",4.9),("WFC",4.7),("GS",3.3),("MS",3.0),("C",2.8),("AXP",2.6)],
    "XLE":  [("XOM",22.5),("CVX",15.8),("EOG",5.1),("COP",4.9),("SLB",4.5),("MPC",3.9),("PSX",3.5),("PXD",3.2),("OXY",3.0),("VLO",2.9)],
    "XLV":  [("LLY",12.7),("UNH",11.9),("ABBV",6.8),("JNJ",6.2),("MRK",5.9),("TMO",4.2),("ABT",4.1),("DHR",3.8),("BMY",3.2),("AMGN",3.0)],
    "XLI":  [("GE",5.3),("RTX",4.9),("CAT",4.7),("UNP",4.5),("HON",4.2),("LMT",4.0),("DE",3.8),("ETN",3.6),("BA",3.3),("UPS",3.0)],
    "XLC":  [("META",22.1),("GOOGL",11.0),("GOOG",9.5),("NFLX",5.1),("T",4.5),("VZ",4.2),("DIS",4.0),("CMCSA",3.8),("EA",2.4),("TTWO",1.9)],
    "XLY":  [("AMZN",23.5),("TSLA",13.2),("HD",7.4),("MCD",5.3),("NKE",3.8),("LOW",3.5),("SBUX",3.2),("BKNG",3.0),("TJX",2.8),("GM",2.1)],
    "XLP":  [("PG",16.2),("KO",10.8),("PEP",10.1),("COST",9.7),("WMT",7.6),("PM",5.3),("MO",4.5),("MDLZ",3.6),("CL",3.3),("KMB",2.8)],
    "XLU":  [("NEE",15.0),("SO",7.5),("DUK",7.2),("D",5.6),("AEP",5.3),("EXC",5.0),("SRE",4.8),("PCG",4.2),("PEG",4.0),("XEL",3.9)],
    "XLRE": [("PLD",11.1),("AMT",8.8),("EQIX",7.7),("WELL",5.5),("SPG",5.3),("DLR",5.0),("O",4.7),("AVB",4.2),("EQR",4.0),("PSA",3.9)],
    "XLB":  [("LIN",16.3),("APD",6.5),("SHW",6.2),("ECL",5.8),("FCX",4.9),("NUE",4.3),("NEM",4.1),("CTVA",3.7),("IFF",3.2),("VMC",3.0)],
    # Bond / fixed-income ETFs have no equity holdings — holdings_risk falls back to structural
    "TLT":  [],
    "AGG":  [],
    "BND":  [],
    "HYG":  [],
    "LQD":  [],
    "BIL":  [],
    "SHY":  [],
    # Gold / commodity ETFs
    "GLD":  [],
    "IAU":  [],
    "SLV":  [],
    "USO":  [],
    # International equity ETFs
    "EFA":  [],
    "IEFA": [],
    "EEM":  [],
    # REITs
    "VNQ":  [("PLD",9.2),("AMT",6.5),("EQIX",5.9),("WELL",5.2),("SPG",4.9),("DLR",4.5),("O",4.3),("AVB",4.1),("EQR",3.9),("PSA",3.7)],
    # Mid-cap
    "IJH":  [],
}

# Store the full constituent list where the issuer publishes it (SSGA/Invesco give
# every holding). The universal fallback (stockanalysis) returns the top 25.
TOP_HOLDINGS_LIMIT = 600
REQUEST_HEADERS = {"User-Agent": "Mozilla/5.0"}
BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"
    ),
    "Accept": "application/json",
}

# State Street SPDR family — one XLSX URL pattern covers the whole family and
# returns every constituent (full holdings, not a top-N slice).
SSGA_TICKERS = {
    "SPY", "SPLG", "SPYG", "SPYV", "MDY", "DIA",
    "XLK", "XLF", "XLE", "XLV", "XLI", "XLC", "XLY", "XLP", "XLU", "XLRE", "XLB",
}
SSGA_HOLDINGS_URL = (
    "https://www.ssga.com/library-content/products/fund-data/etfs/us/"
    "holdings-daily-us-en-{ticker}.xlsx"
)
VANGUARD_PORT_IDS = {"VTI": "0970"}
INVESCO_HOLDINGS_URL = (
    "https://dng-api.invesco.com/cache/v1/accounts/en_US/shareclasses/{ticker}/holdings/fund"
    "?idType=ticker&interval=monthly&productType=ETF&loadType=initial"
)
VANGUARD_HOLDINGS_URL = (
    "https://advisors.vanguard.com/investments/products/holdings/latest/{port_id}"
)
# Universal fund-profile + holdings source. Returns top-25 holdings plus the true
# constituent count, full sector map, category, and an issuer-style description.
STOCKANALYSIS_URL = "https://stockanalysis.com/api/symbol/e/{ticker}/holdings"

# Curated "what it is" labels. stockanalysis.category is a Morningstar-style box
# (e.g. "Large Value"); these give the plain-English theme the UI leads with.
ETF_THEMES: dict[str, dict[str, str]] = {
    "SPY":  {"theme": "Broad US large-cap", "benchmark": "S&P 500", "kind": "equity"},
    "VOO":  {"theme": "Broad US large-cap", "benchmark": "S&P 500", "kind": "equity"},
    "IVV":  {"theme": "Broad US large-cap", "benchmark": "S&P 500", "kind": "equity"},
    "SPLG": {"theme": "Broad US large-cap", "benchmark": "S&P 500", "kind": "equity"},
    "VTI":  {"theme": "Total US market", "benchmark": "CRSP US Total Market", "kind": "equity"},
    "QQQ":  {"theme": "Large-cap growth & tech", "benchmark": "Nasdaq-100", "kind": "equity"},
    "QQQM": {"theme": "Large-cap growth & tech", "benchmark": "Nasdaq-100", "kind": "equity"},
    "IWM":  {"theme": "US small-cap", "benchmark": "Russell 2000", "kind": "equity"},
    "IJH":  {"theme": "US mid-cap", "benchmark": "S&P MidCap 400", "kind": "equity"},
    "MDY":  {"theme": "US mid-cap", "benchmark": "S&P MidCap 400", "kind": "equity"},
    "DIA":  {"theme": "US blue-chip", "benchmark": "Dow Jones Industrial Average", "kind": "equity"},
    "SOXX": {"theme": "Semiconductors", "benchmark": "ICE Semiconductor Index", "kind": "equity"},
    "SCHD": {"theme": "US dividend equity", "benchmark": "Dow Jones US Dividend 100", "kind": "equity"},
    "ARKK": {"theme": "Disruptive innovation (active)", "benchmark": "Actively managed", "kind": "equity"},
    "VNQ":  {"theme": "US real estate (REITs)", "benchmark": "MSCI US IMI Real Estate 25/50", "kind": "equity"},
    "XLK":  {"theme": "Technology sector", "benchmark": "Technology Select Sector", "kind": "sector"},
    "XLF":  {"theme": "Financials sector", "benchmark": "Financial Select Sector", "kind": "sector"},
    "XLE":  {"theme": "Energy sector", "benchmark": "Energy Select Sector", "kind": "sector"},
    "XLV":  {"theme": "Health Care sector", "benchmark": "Health Care Select Sector", "kind": "sector"},
    "XLI":  {"theme": "Industrials sector", "benchmark": "Industrial Select Sector", "kind": "sector"},
    "XLC":  {"theme": "Communication Services sector", "benchmark": "Communication Services Select Sector", "kind": "sector"},
    "XLY":  {"theme": "Consumer Discretionary sector", "benchmark": "Consumer Discretionary Select Sector", "kind": "sector"},
    "XLP":  {"theme": "Consumer Staples sector", "benchmark": "Consumer Staples Select Sector", "kind": "sector"},
    "XLU":  {"theme": "Utilities sector", "benchmark": "Utilities Select Sector", "kind": "sector"},
    "XLRE": {"theme": "Real Estate sector", "benchmark": "Real Estate Select Sector", "kind": "sector"},
    "XLB":  {"theme": "Materials sector", "benchmark": "Materials Select Sector", "kind": "sector"},
    "TLT":  {"theme": "Long-term US Treasuries", "benchmark": "ICE 20+ Year Treasury", "kind": "bond"},
    "IEF":  {"theme": "Intermediate US Treasuries", "benchmark": "ICE 7-10 Year Treasury", "kind": "bond"},
    "AGG":  {"theme": "US aggregate bonds", "benchmark": "Bloomberg US Aggregate Bond", "kind": "bond"},
    "BND":  {"theme": "US aggregate bonds", "benchmark": "Bloomberg US Aggregate Bond", "kind": "bond"},
    "HYG":  {"theme": "High-yield corporate bonds", "benchmark": "iBoxx High Yield Corporate", "kind": "bond"},
    "LQD":  {"theme": "Investment-grade corporate bonds", "benchmark": "iBoxx Investment Grade Corporate", "kind": "bond"},
    "BIL":  {"theme": "US Treasury bills", "benchmark": "Bloomberg 1-3 Month T-Bill", "kind": "bond"},
    "SHY":  {"theme": "Short-term US Treasuries", "benchmark": "ICE 1-3 Year Treasury", "kind": "bond"},
    "GLD":  {"theme": "Gold bullion", "benchmark": "LBMA Gold Price", "kind": "commodity"},
    "IAU":  {"theme": "Gold bullion", "benchmark": "LBMA Gold Price", "kind": "commodity"},
    "SLV":  {"theme": "Silver bullion", "benchmark": "LBMA Silver Price", "kind": "commodity"},
    "USO":  {"theme": "Crude oil futures", "benchmark": "WTI crude oil", "kind": "commodity"},
    "EFA":  {"theme": "Developed international equity", "benchmark": "MSCI EAFE", "kind": "international"},
    "IEFA": {"theme": "Developed international equity", "benchmark": "MSCI EAFE IMI", "kind": "international"},
    "EEM":  {"theme": "Emerging-markets equity", "benchmark": "MSCI Emerging Markets", "kind": "international"},
}


def _active_etfs(supabase) -> list[str]:
    # Run for all known ETFs in the universe, not just user-held ones,
    # so the SP500 scoring path always has fresh holdings data.
    known = set(ETF_STATIC_SEEDS.keys()) | set(ETF_THEMES.keys())
    try:
        rows = (
            supabase.table("ticker_metadata")
            .select("ticker")
            .eq("asset_class", "etf")
            .execute()
            .data
            or []
        )
        for row in rows:
            t = str(row.get("ticker") or "").upper()
            if t:
                known.add(t)
    except Exception:
        pass
    return sorted(known)


def _rows_for_holdings(
    ticker: str,
    holdings: list[tuple[str, float]],
    *,
    as_of: str,
    source: str,
) -> list[dict[str, Any]]:
    return [
        {
            "etf_ticker": ticker.upper(),
            "holding_ticker": holding,
            "weight_pct": weight,
            "rank": index + 1,
            "source": source,
            "as_of": as_of,
        }
        for index, (holding, weight) in enumerate(holdings[:TOP_HOLDINGS_LIMIT])
    ]


def _fallback_rows(ticker: str, as_of: str | None = None) -> list[dict[str, Any]]:
    return _rows_for_holdings(
        ticker,
        ETF_STATIC_SEEDS.get(ticker.upper(), []),
        as_of=as_of or date.today().isoformat(),
        source="static_seed",
    )


def _parse_pct(raw: Any) -> float | None:
    if raw is None:
        return None
    try:
        return float(str(raw).replace("%", "").replace(",", "").strip())
    except (TypeError, ValueError):
        return None


_TICKER_RE = re.compile(r"^[A-Z]{1,6}(\.[A-Z]{1,2})?$")


def _clean_symbol(raw: Any) -> str | None:
    """Normalize a holding symbol, rejecting cash/derivative/mutual-fund rows.

    Vendors interleave non-equity lines (e.g. "!MUTF/VRTPX", "CASH_USD", "-")
    with the constituent list; those must never surface as holdings.
    """
    sym = str(raw or "").lstrip("$").strip().upper()
    if not sym or not _TICKER_RE.match(sym):
        return None
    if sym in {"CASH", "USD", "N/A"}:
        return None
    return sym


def _parse_xlsx_rows(content: bytes) -> list[list[str]]:
    workbook = zipfile.ZipFile(io.BytesIO(content))
    ns = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    shared_strings: list[str] = []
    if "xl/sharedStrings.xml" in workbook.namelist():
        root = ET.fromstring(workbook.read("xl/sharedStrings.xml"))
        for item in root.findall("a:si", ns):
            shared_strings.append("".join(node.text or "" for node in item.findall(".//a:t", ns)))

    sheet = ET.fromstring(workbook.read("xl/worksheets/sheet1.xml"))
    rows: list[list[str]] = []
    for row in sheet.findall(".//a:sheetData/a:row", ns):
        values: list[str] = []
        for cell in row.findall("a:c", ns):
            cell_type = cell.attrib.get("t")
            raw = cell.find("a:v", ns)
            text = raw.text if raw is not None else ""
            if cell_type == "s" and text:
                text = shared_strings[int(text)]
            values.append(text)
        rows.append(values)
    return rows


def _fetch_ssga_holdings(ticker: str) -> list[dict[str, Any]]:
    """Full constituent list for any State Street SPDR fund."""
    upper = ticker.upper()
    if upper not in SSGA_TICKERS:
        return []
    response = requests.get(
        SSGA_HOLDINGS_URL.format(ticker=upper.lower()),
        timeout=20,
        headers=REQUEST_HEADERS,
    )
    if response.status_code != 200:
        return []

    rows = _parse_xlsx_rows(response.content)
    as_of = date.today().isoformat()
    holdings_started = False
    holdings: list[tuple[str, float]] = []
    for row in rows:
        if len(row) >= 2 and row[0] == "Holdings:":
            match = re.search(r"As of (\d{1,2}-[A-Za-z]{3}-\d{4})", row[1] or "")
            if match:
                as_of = datetime.strptime(match.group(1), "%d-%b-%Y").date().isoformat()
        elif row[:5] == ["Name", "Ticker", "Identifier", "SEDOL", "Weight"]:
            holdings_started = True
        elif holdings_started:
            if len(row) < 5 or not row[1]:
                break
            weight = _parse_pct(row[4])
            sym = _clean_symbol(row[1])
            if weight is None or sym is None:
                continue
            holdings.append((sym, weight))
            if len(holdings) >= TOP_HOLDINGS_LIMIT:
                break

    return _rows_for_holdings(ticker, holdings, as_of=as_of, source="ssga")


def _fetch_invesco_holdings(ticker: str) -> list[dict[str, Any]]:
    if ticker.upper() != "QQQ":
        return []
    response = requests.get(
        INVESCO_HOLDINGS_URL.format(ticker=ticker.upper()),
        timeout=20,
        headers=REQUEST_HEADERS,
    )
    if response.status_code != 200:
        return []
    payload = response.json() or {}
    as_of = payload.get("effectiveDate") or payload.get("effectiveBusinessDate") or date.today().isoformat()
    holdings = []
    for item in payload.get("holdings") or []:
        holding_ticker = _clean_symbol(item.get("ticker"))
        weight = _parse_pct(item.get("percentageOfTotalNetAssets"))
        if holding_ticker and weight is not None:
            holdings.append((holding_ticker, weight))
        if len(holdings) >= TOP_HOLDINGS_LIMIT:
            break
    return _rows_for_holdings(ticker, holdings, as_of=as_of, source="invesco")


def _fetch_vanguard_holdings(ticker: str) -> list[dict[str, Any]]:
    port_id = VANGUARD_PORT_IDS.get(ticker.upper())
    if not port_id:
        return []
    response = requests.get(
        VANGUARD_HOLDINGS_URL.format(port_id=port_id),
        timeout=20,
        headers={**REQUEST_HEADERS, "X-Consumer-ID": "FPP"},
    )
    if response.status_code != 200:
        return []
    try:
        payload = response.json() or {}
    except ValueError:
        # Vanguard intermittently returns an HTML block/error page instead of JSON.
        # Treat as an empty fetch so run() falls back to the static seed.
        logger.warning("Vanguard holdings returned non-JSON for %s; falling back", ticker)
        return []
    as_of = payload.get("latestEffectiveDate") or date.today().isoformat()
    daily_payload = payload.get(as_of) or {}
    holdings = []
    for item in daily_payload.get("equity") or []:
        holding_ticker = _clean_symbol(item.get("ticker"))
        weight = _parse_pct(item.get("percentOfFunds"))
        if holding_ticker and weight is not None:
            holdings.append((holding_ticker, weight))
        if len(holdings) >= TOP_HOLDINGS_LIMIT:
            break
    return _rows_for_holdings(ticker, holdings, as_of=as_of, source="vanguard")


def _parse_stockanalysis_date(raw: Any) -> str:
    for fmt in ("%b %d, %Y", "%B %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(raw).strip(), fmt).date().isoformat()
        except (TypeError, ValueError):
            continue
    return date.today().isoformat()


def _fetch_stockanalysis(ticker: str) -> tuple[list[dict[str, Any]], dict[str, Any] | None]:
    """Universal source: top-25 holdings + full fund profile (sectors, category,
    true constituent count, description). Works for any listed ETF."""
    try:
        response = requests.get(
            STOCKANALYSIS_URL.format(ticker=ticker.upper()),
            timeout=20,
            headers=BROWSER_HEADERS,
        )
    except Exception as exc:
        logger.warning("stockanalysis fetch failed for %s: %s", ticker, exc)
        return [], None
    if response.status_code != 200:
        return [], None
    try:
        data = (response.json() or {}).get("data") or {}
    except ValueError:
        return [], None

    holdings: list[tuple[str, float]] = []
    for item in data.get("holdings") or []:
        sym = _clean_symbol(item.get("s"))
        weight = _parse_pct(item.get("as"))
        if sym and weight is not None:
            holdings.append((sym, weight))

    as_of = _parse_stockanalysis_date(data.get("date"))
    info = data.get("infoTable") or {}
    sectors = [
        {"name": s.get("n"), "weight": _parse_pct(s.get("w"))}
        for s in (data.get("sectors") or [])
        if s.get("n") and _parse_pct(s.get("w")) is not None
    ]
    countries = [
        {"name": c.get("country"), "weight": _parse_pct(c.get("weight"))}
        for c in (data.get("countries") or [])
        if c.get("country") and _parse_pct(c.get("weight")) is not None
    ]
    profile = {
        "category": info.get("category"),
        "total_holdings": _coerce_int(data.get("count") or info.get("count")),
        "top10_weight_pct": _parse_pct(info.get("top10")),
        "aum": _coerce_float(info.get("aum")),
        "pe_ratio": _coerce_float(info.get("peRatio")),
        "sectors": sectors,
        "countries": countries,
        "description": (str(data.get("infoBox") or "").strip() or None),
        "holdings_as_of": as_of,
    }
    return _rows_for_holdings(ticker, holdings, as_of=as_of, source="stockanalysis"), profile


def _coerce_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _coerce_int(value: Any) -> int | None:
    f = _coerce_float(value)
    return int(f) if f is not None else None


def _fetch_issuer_rows(ticker: str) -> list[dict[str, Any]]:
    """Official issuer holdings (full constituent list) where we have a parser."""
    upper = ticker.upper()
    if upper in SSGA_TICKERS:
        return _fetch_ssga_holdings(upper)
    if upper == "QQQ":
        return _fetch_invesco_holdings(upper)
    if upper in VANGUARD_PORT_IDS:
        return _fetch_vanguard_holdings(upper)
    return []


def _profile_row(ticker: str, profile: dict[str, Any] | None) -> dict[str, Any]:
    upper = ticker.upper()
    theme = ETF_THEMES.get(upper, {})
    profile = profile or {}
    return {
        "ticker": upper,
        "category": profile.get("category"),
        "theme": theme.get("theme"),
        "benchmark": theme.get("benchmark"),
        "total_holdings": profile.get("total_holdings"),
        "top10_weight_pct": profile.get("top10_weight_pct"),
        "aum": profile.get("aum"),
        "pe_ratio": profile.get("pe_ratio"),
        "sectors": profile.get("sectors"),
        "countries": profile.get("countries"),
        "holdings_as_of": profile.get("holdings_as_of"),
    }


def run() -> dict[str, Any]:
    supabase = get_supabase()
    all_rows: list[dict[str, Any]] = []
    profile_rows: list[dict[str, Any]] = []
    description_updates: list[dict[str, Any]] = []
    real_tickers: set[str] = set()
    failed: list[str] = []
    for ticker in _active_etfs(supabase):
        upper = ticker.upper()
        # 1) Universal profile + fallback holdings (sectors, category, count, description).
        try:
            sa_rows, profile = _fetch_stockanalysis(upper)
        except Exception as exc:
            logger.warning("stockanalysis fetch failed for %s: %s", upper, exc)
            sa_rows, profile = [], None

        # 2) Prefer the official issuer full-constituent list when available.
        try:
            issuer_rows = _fetch_issuer_rows(upper)
        except Exception as exc:
            logger.warning("ETF issuer holdings fetch failed for %s: %s", upper, exc)
            issuer_rows = []
            failed.append(upper)

        rows = issuer_rows or sa_rows
        is_real = bool(rows)  # issuer or stockanalysis returned live constituents
        if not rows:
            static = ETF_STATIC_SEEDS.get(upper, [])
            if static:
                logger.warning("ETF holdings empty for %s; using static seed fallback", upper)
                rows = _fallback_rows(upper)
            else:
                logger.debug("ETF %s has no equity holdings (bond/commodity/intl fund)", upper)
        if is_real:
            real_tickers.add(upper)
        all_rows.extend(rows)

        # 3) Persist the fund profile (theme/benchmark always; live fields when fetched).
        profile_rows.append(_profile_row(upper, profile))
        desc = (profile or {}).get("description")
        if desc:
            description_updates.append({"ticker": upper, "description": desc})

    # When we have live constituents for a fund, purge its prior rows first so a
    # stale static seed (which we stamp with today's date) can never shadow the
    # real, correctly-dated snapshot when the audit picks the latest as_of.
    for ticker in real_tickers:
        try:
            supabase.table("etf_holdings").delete().eq("etf_ticker", ticker).execute()
        except Exception as exc:
            logger.warning("Failed to purge prior holdings for %s: %s", ticker, exc)
    if all_rows:
        supabase.table("etf_holdings").upsert(
            all_rows,
            on_conflict="etf_ticker,holding_ticker,as_of",
        ).execute()
    # Relative-performance (1/3/5yr vs S&P 500 + sector rank) powers Sector Strength.
    try:
        from app.jobs import etf_performance

        perf_map = etf_performance.build_all([row["ticker"] for row in profile_rows])
        for row in profile_rows:
            perf = perf_map.get(row["ticker"])
            if perf:
                row["performance"] = perf
    except Exception as exc:
        logger.warning("ETF performance computation failed: %s", exc)

    if profile_rows:
        supabase.table("etf_profiles").upsert(profile_rows, on_conflict="ticker").execute()
    # Store the fund "About" text on ticker_metadata alongside stock descriptions.
    for update in description_updates:
        try:
            supabase.table("ticker_metadata").update(
                {
                    "description": update["description"],
                    "description_source": "stockanalysis",
                    "description_updated_at": datetime.utcnow().isoformat(),
                }
            ).eq("ticker", update["ticker"]).execute()
        except Exception as exc:
            logger.warning("ETF description update failed for %s: %s", update["ticker"], exc)

    return {
        "status": "completed",
        "items_processed": len(all_rows),
        "items_failed": len(failed),
        "metadata": {
            "etfs": sorted({row["etf_ticker"] for row in all_rows}),
            "profiles_written": len(profile_rows),
            "descriptions_written": len(description_updates),
            "live_fetch_failed": failed,
        },
    }


def run_from_env() -> dict[str, Any]:
    return run()
