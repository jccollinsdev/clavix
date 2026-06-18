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
TOP_HOLDINGS_LIMIT = 25
REQUEST_HEADERS = {"User-Agent": "Mozilla/5.0"}
VANGUARD_PORT_IDS = {"VTI": "0970"}
INVESCO_HOLDINGS_URL = (
    "https://dng-api.invesco.com/cache/v1/accounts/en_US/shareclasses/{ticker}/holdings/fund"
    "?idType=ticker&interval=monthly&productType=ETF&loadType=initial"
)
SSGA_SPY_XLSX_URL = (
    "https://www.ssga.com/library-content/products/fund-data/etfs/us/holdings-daily-us-en-spy.xlsx"
)
VANGUARD_HOLDINGS_URL = (
    "https://advisors.vanguard.com/investments/products/holdings/latest/{port_id}"
)


def _active_etfs(supabase) -> list[str]:
    # Run for all known ETFs in the universe, not just user-held ones,
    # so the SP500 scoring path always has fresh holdings data.
    known = set(ETF_STATIC_SEEDS.keys())
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
    if ticker.upper() != "SPY":
        return []
    response = requests.get(SSGA_SPY_XLSX_URL, timeout=20, headers=REQUEST_HEADERS)
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
            try:
                holdings.append((str(row[1]).upper(), float(row[4])))
            except (TypeError, ValueError):
                continue
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
        holding_ticker = str(item.get("ticker") or "").upper()
        try:
            weight = float(item.get("percentageOfTotalNetAssets"))
        except (TypeError, ValueError):
            continue
        if holding_ticker:
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
    payload = response.json() or {}
    as_of = payload.get("latestEffectiveDate") or date.today().isoformat()
    daily_payload = payload.get(as_of) or {}
    holdings = []
    for item in daily_payload.get("equity") or []:
        holding_ticker = str(item.get("ticker") or "").upper()
        try:
            weight = float(item.get("percentOfFunds"))
        except (TypeError, ValueError):
            continue
        if holding_ticker:
            holdings.append((holding_ticker, weight))
        if len(holdings) >= TOP_HOLDINGS_LIMIT:
            break
    return _rows_for_holdings(ticker, holdings, as_of=as_of, source="vanguard")


def _fetch_live_rows(ticker: str) -> list[dict[str, Any]]:
    upper = ticker.upper()
    if upper == "SPY":
        return _fetch_ssga_holdings(upper)
    if upper == "QQQ":
        return _fetch_invesco_holdings(upper)
    if upper == "VTI":
        return _fetch_vanguard_holdings(upper)
    return []


def run() -> dict[str, Any]:
    supabase = get_supabase()
    all_rows: list[dict[str, Any]] = []
    for ticker in _active_etfs(supabase):
        rows = _fetch_live_rows(ticker)
        if not rows:
            static = ETF_STATIC_SEEDS.get(ticker.upper(), [])
            if static:
                logger.warning("ETF holdings fetch returned empty for %s; using static seed fallback", ticker)
                rows = _fallback_rows(ticker)
            else:
                # Bond/commodity/international ETFs have no meaningful equity holdings
                logger.debug("ETF %s has no holdings to store (bond/commodity/intl fund)", ticker)
        all_rows.extend(rows)

    if all_rows:
        supabase.table("etf_holdings").upsert(
            all_rows,
            on_conflict="etf_ticker,holding_ticker,as_of",
        ).execute()
    return {
        "status": "completed",
        "items_processed": len(all_rows),
        "metadata": {"etfs": sorted({row["etf_ticker"] for row in all_rows})},
    }


def run_from_env() -> dict[str, Any]:
    return run()
