"""Single source of truth for sector -> ETF proxy mapping.

Historically three copies of this map had drifted apart
(routes/portfolio.py, routes/today.py, pipeline/sector_snapshot.py), which is
how the Semiconductors tile (SOXX) ended up greyed: the reader expected SOXX
but the snapshot writer never fetched it. Everything now imports from here.
"""

from __future__ import annotations

from typing import Any


# sector name (lowercased) -> ETF proxy ticker used for the day-change tint.
SECTOR_ETF_MAP: dict[str, str] = {
    "technology": "XLK",
    "information technology": "XLK",
    "semiconductors": "SOXX",
    "semiconductor": "SOXX",
    "semis": "SOXX",
    "health care": "XLV",
    "healthcare": "XLV",
    "pharmaceuticals": "XLV",
    "biotechnology": "XLV",
    "financials": "XLF",
    "financial services": "XLF",
    "energy": "XLE",
    "oil & gas": "XLE",
    "consumer discretionary": "XLY",
    "consumer staples": "XLP",
    "industrials": "XLI",
    "utilities": "XLU",
    "materials": "XLB",
    "real estate": "XLRE",
    "communication services": "XLC",
    "media": "XLC",
    "interactive media": "XLC",
    "entertainment": "XLC",
    "us total market": "VTI",
}


# (display label, ETF) the daily snapshot job pulls a day-change for. The reader
# above keys by ETF, so SOXX MUST be fetched here or the Semiconductors tile has
# no color. VTI is the broad-market reference shown in the Today sector grid.
SECTOR_ETFS: list[tuple[str, str]] = [
    ("Technology", "XLK"),
    ("Semiconductors", "SOXX"),
    ("Health Care", "XLV"),
    ("Financials", "XLF"),
    ("Energy", "XLE"),
    ("Consumer Discretionary", "XLY"),
    ("Consumer Staples", "XLP"),
    ("Industrials", "XLI"),
    ("Utilities", "XLU"),
    ("Materials", "XLB"),
    ("Real Estate", "XLRE"),
    ("Communication Services", "XLC"),
    ("US Total Market", "VTI"),
]


def etf_for_sector(sector: str | None) -> str | None:
    """Map a free-text sector label to its ETF proxy, or None if unmapped."""
    return SECTOR_ETF_MAP.get(str(sector or "").strip().lower())


def latest_sector_changes(supabase) -> dict[str, float]:
    """Return {ETF: latest day-change-pct} from sector_regime_snapshots.

    Newest snapshot per ETF wins. Tolerates the historical column drift where
    the pipeline wrote `day_change_pct` instead of `etf_day_change_pct`.
    """
    rows = (
        supabase.table("sector_regime_snapshots")
        .select("source_etf,etf_day_change_pct,day_change_pct,snapshot_date")
        .order("snapshot_date", desc=True)
        .limit(80)
        .execute()
        .data
        or []
    )
    out: dict[str, float] = {}
    for row in rows:
        etf = str(row.get("source_etf") or "").upper()
        if not etf or etf in out:
            continue
        change = row.get("etf_day_change_pct")
        if change is None:
            change = row.get("day_change_pct")
        try:
            if change is not None:
                out[etf] = float(change)
        except (TypeError, ValueError):
            continue
    return out


def _coerce_dict(value: Any) -> dict:
    return value if isinstance(value, dict) else {}
