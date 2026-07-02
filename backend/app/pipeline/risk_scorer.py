from __future__ import annotations

import asyncio
import logging
import math
import os
from datetime import datetime, timezone

from ..services.minimax import chatcompletion_text
from ..services.supabase import get_supabase
from ..services.ticker_metadata import KNOWN_ETF_TICKERS
from .analysis_utils import (
    clamp_score,
    extract_json_object,
    score_to_grade,
    grade_direction,
    format_rationale,
    evidence_strength,
    calculate_weighted_score,
    V2_DIMENSION_KEYS,
)
from .structural_scorer import (
    smooth_score_change,
)

SYSTEM_PROMPT = """You are a risk rating system. Given the position context and event evidence below, score this position across 5 risk dimensions and write a concise risk rationale.

Scale: 0 = penny-stock-like / very risky. 100 = treasury-like / very safe. Higher = lower risk.

Position:
- Ticker: {ticker}
- Shares: {shares} @ ${purchase_price}
- Approximate position value: ${position_value}
- Inferred labels: {labels}
- Position report summary: {summary}

Long-form position report: {long_report}

Scoring criteria:
1. financial_health (0-100): Strong balance sheet, cash flow, coverage ratios → high. Weak fundamentals, high leverage → low.
2. news_sentiment (0-100): Positive/supportive news → high. Negative/dangerous news → low. 50 only when truly balanced.
3. macro_exposure (0-100): Less macro-sensitive / more treasury-like → high. More macro-sensitive / more speculative → low.
4. sector_exposure (0-100): Strong sector with broad participation → high. Weak, concentrated, or volatile sector → low.
5. volatility (0-100): Low, stable, or falling volatility → high. High, rising, or extreme drawdown → low.

How to write "reasoning" — the investor-facing rationale:
FORMAT: Header line + max 2 driver lines. No paragraphs. No hedging.
Example:
C+ — Average (↑ worsening)
Earnings miss on revenue weakness
Sector rotation into defensives

Rules:
1. First line: [GRADE] — [Risk Level] ([arrow direction])
   - Risk Level per the academic scale: A+=Exceptional, A=Excellent, A-=Very Strong, B+=Strong, B=Solid, B-=Above Average, C+=Average, C=Below Average, C-=Watch, D+=Elevated Risk, D=High Risk, D-=Severe Risk, F=Distressed
   - Arrow: ↓ improving if score improved >2pts, ↑ worsening if score dropped >2pts, → stable otherwise
2. Next 1-2 lines: specific, causal risk drivers. Each driver ≤60 chars.
3. Each driver MUST name a concrete event, metric change, or sector theme:
   ✅ "Earnings miss on revenue weakness"
   ✅ "High rate sensitivity"
   ✅ "Valuation stretched vs earnings"
   ✅ "Weak revenue trend"
   ❌ "Mixed signals across sectors"
   ❌ "Market uncertainty"
   ❌ "Could impact performance"
4. If evidence is thin (<3 events), write: "Limited data — risk based on fundamentals" as the only driver.
5. Total output ≤140 chars preferred.

Banned words — DO NOT USE: may, could, would, suggests, indicates, sentiment, momentum, thesis, coverage, provisional, research, analyst, monitor, watch.
Write like a credit rating bulletin — direct, specific, concrete. Not a research note, not a process description.

How to write "dimension_rationale" — one short phrase per dimension:
- financial_health: what the fundamentals show about structural strength
- news_sentiment: what the news means for risk
- macro_exposure: how macro conditions affect risk
- sector_exposure: how the sector state affects risk
- volatility: what is driving volatility behavior

Forbidden language: dimension scores, "the model", "the score reflects", "based on the dimension", "data across N sources", internal evidence labels, implementation jargon. Avoid returning 50 for every dimension unless the evidence is genuinely neutral.

Respond in this exact JSON format (no markdown, no explanation):
{{"financial_health": 0-100, "news_sentiment": 0-100, "macro_exposure": 0-100, "sector_exposure": 0-100, "volatility": 0-100, "grade": "A+|A|A-|B+|B|B-|C+|C|C-|D+|D|D-|F", "reasoning": "concise risk rationale per rules above", "dimension_rationale": {{"financial_health": "...", "news_sentiment": "...", "macro_exposure": "...", "sector_exposure": "...", "volatility": "..."}}}}"""

DIMENSION_KEYS = V2_DIMENSION_KEYS

# ETF-specific LLM prompt — replaces financial_health/news_sentiment semantics
ETF_SYSTEM_PROMPT = """You are a risk rating system for ETFs and index funds. Score this ETF across 5 risk dimensions and write a concise risk rationale.

Scale: 0 = very risky / high drawdown risk. 100 = very safe / stable. Higher = lower risk.

ETF:
- Ticker: {ticker}
- Fund name: {fund_name}
- Category: {category}
- Recent news context: {summary}

Scoring criteria for ETFs:
1. financial_health (0-100): Quality of top holdings. High-grade, diversified holdings with strong fundamentals → high (70-100). Concentrated in speculative, leveraged, or struggling names → low (0-40). Use any available holdings data. If the fund's top holdings have strong balance sheets and earnings, score this dimension high.
2. news_sentiment (0-100): Category/fund-flow sentiment. Strong inflows, positive sector rotation into this fund type → high. Outflows, redemption pressure, adverse category rotation → low. 50 only when flows are genuinely neutral.
3. macro_exposure (0-100): How macro conditions affect this fund. Less sensitive to rate/cycle shifts → high. High duration, rate-sensitive, or cyclical exposure → low.
4. sector_exposure (0-100): Strength and breadth of the sector or asset class. Broad, diversified, strong-performing sector → high. Narrow, concentrated, weak, or volatile sector/asset class → low.
5. volatility (0-100): Low, stable, or falling realized volatility → high. High, rising, or drawdown-prone fund → low.

How to write "reasoning" — credit-rating format:
FORMAT: Header line + max 2 driver lines. No paragraphs.
Example:
B — Solid (→ stable)
Broad diversification limits single-name risk
Rate sensitivity moderate for this duration

Rules:
1. First line: [GRADE] — [Risk Level] ([arrow])
   - Risk Level per the academic scale: A+=Exceptional, A=Excellent, A-=Very Strong, B+=Strong, B=Solid, B-=Above Average, C+=Average, C=Below Average, C-=Watch, D+=Elevated Risk, D=High Risk, D-=Severe Risk, F=Distressed
   - Arrow: ↓ improving, ↑ worsening, → stable
2. Next 1-2 lines: specific, causal fund-level risk drivers. Each ≤60 chars.
3. No individual stock names. No "may", "could", "suggests", "sentiment", "thesis".
4. If evidence is thin, write: "Limited data — risk based on category profile"

Write like a credit rating bulletin. Direct, specific, concrete.

Respond in this exact JSON format (no markdown, no explanation):
{{"financial_health": 0-100, "news_sentiment": 0-100, "macro_exposure": 0-100, "sector_exposure": 0-100, "volatility": 0-100, "grade": "A+|A|A-|B+|B|B-|C+|C|C-|D+|D|D-|F", "reasoning": "concise risk rationale per rules above", "dimension_rationale": {{"financial_health": "Holdings quality and fund composition risk", "news_sentiment": "Fund flow and category rotation signal", "macro_exposure": "Rate and cycle sensitivity", "sector_exposure": "Sector/asset class breadth and strength", "volatility": "Realized volatility and drawdown profile"}}}}"""

# Display labels for ETF dimensions (overrides generic stock labels in iOS)
ETF_DIMENSION_LABELS = {
    "financial_health": "Holdings Quality",
    "news_sentiment": "Sector Strength",
    "macro_exposure": "Macro Exposure",
    "sector_exposure": "Concentration",
    "volatility": "Volatility",
}


def _is_etf(position_data: dict) -> bool:
    meta = position_data.get("ticker_metadata") or {}
    ticker = str(position_data.get("ticker") or meta.get("ticker") or "").upper()
    asset_class = str(meta.get("asset_class") or "").lower()
    membership = str(
        meta.get("index_membership") or position_data.get("index_membership") or ""
    ).upper()
    return asset_class == "etf" or "ETF" in membership or ticker in KNOWN_ETF_TICKERS


def _score_etf_holdings_risk(ticker: str) -> int | None:
    """Return a 0-100 holdings quality score for an ETF by averaging the composite
    scores of its top holdings from the latest etf_holdings data.
    Returns None if no holdings data is available."""
    try:
        supabase = get_supabase()
        # Get the most recent as_of date for this ETF
        date_rows = (
            supabase.table("etf_holdings")
            .select("as_of")
            .eq("etf_ticker", ticker.upper())
            .order("as_of", desc=True)
            .limit(1)
            .execute()
            .data
        )
        if not date_rows:
            return None
        latest_date = date_rows[0]["as_of"]

        # Get top holdings for that date
        holding_rows = (
            supabase.table("etf_holdings")
            .select("holding_ticker, weight_pct, rank")
            .eq("etf_ticker", ticker.upper())
            .eq("as_of", latest_date)
            .order("rank")
            .limit(25)
            .execute()
            .data
        )
        if not holding_rows:
            return None

        holding_tickers = [r["holding_ticker"] for r in holding_rows]

        # Get latest composite scores for those tickers
        score_rows = (
            supabase.table("ticker_risk_snapshots")
            .select("ticker, composite_score, safety_score")
            .in_("ticker", holding_tickers)
            .order("snapshot_date", desc=True)
            .execute()
            .data
        )
        # Build latest-score map per ticker
        score_map: dict[str, float] = {}
        for row in score_rows:
            t = str(row.get("ticker") or "").upper()
            if t not in score_map:
                cs = row.get("composite_score")
                ss = row.get("safety_score")
                val = cs if cs is not None else ss
                if val is not None:
                    score_map[t] = float(val)

        # Weighted average by holdings weight
        total_weight = 0.0
        weighted_sum = 0.0
        for holding in holding_rows:
            ht = str(holding["holding_ticker"]).upper()
            w = float(holding.get("weight_pct") or 1.0)
            score = score_map.get(ht)
            if score is not None:
                weighted_sum += score * w
                total_weight += w

        if total_weight == 0:
            return None
        return clamp_score(round(weighted_sum / total_weight), 0)
    except Exception:
        return None


def _etf_llm_prompt(position_data: dict) -> str:
    meta = position_data.get("ticker_metadata") or {}
    ticker = str(position_data.get("ticker") or "")
    company_name = str(
        meta.get("company_name") or position_data.get("company_name") or ticker
    )
    sector = str(meta.get("sector") or meta.get("index_membership") or "ETF")
    summary = str(position_data.get("summary") or "No recent news context available.")
    article_evidence = _article_evidence_brief(position_data)
    if article_evidence:
        summary = summary + "\n\nArticle evidence:\n" + article_evidence
    return ETF_SYSTEM_PROMPT.format(
        ticker=ticker,
        fund_name=company_name,
        category=sector,
        summary=summary[:600],
    )


def _neutral_dimension_count(scores: dict | None) -> int:
    if not isinstance(scores, dict):
        return len(DIMENSION_KEYS)
    return sum(clamp_score(scores.get(key), 0) == 50 for key in DIMENSION_KEYS)


def has_suspicious_neutral_scores(
    scores: dict | None, threshold: int = len(DIMENSION_KEYS)
) -> bool:
    return _neutral_dimension_count(scores) >= threshold


def _is_batch_response_suspicious(
    parsed_scores: dict[str, dict],
    tickers: list[str],
    threshold: int = len(DIMENSION_KEYS),
) -> bool:
    expected = [str(t).strip().upper() for t in tickers if str(t).strip()]
    if not expected:
        return False
    suspicious = 0
    for ticker in expected:
        score = parsed_scores.get(ticker, {})
        if has_suspicious_neutral_scores(score, threshold=threshold):
            suspicious += 1
    return suspicious > 0


def _data_state_for_position(position_data: dict) -> tuple[str, int, int, int, str]:
    event_analyses = list(position_data.get("event_analyses") or [])
    source_count = len(event_analyses)
    major_event_count = sum(
        1
        for event in event_analyses
        if str(event.get("significance") or "minor").strip().lower() == "major"
    )
    minor_event_count = max(source_count - major_event_count, 0)
    summary = str(position_data.get("summary") or "").strip().lower()

    if source_count == 0 or summary.startswith("insufficient evidence"):
        coverage_state = "provisional"
        coverage_note = "Score based on fundamentals — limited recent news available."
    elif source_count <= 2:
        coverage_state = "thin"
        word = "source" if source_count == 1 else "sources"
        coverage_note = f"Limited data: {source_count} recent {word} reviewed."
    else:
        coverage_state = "substantive"
        word = "source" if source_count == 1 else "sources"
        coverage_note = f"{source_count} recent {word} reviewed."

    return (
        coverage_state,
        source_count,
        major_event_count,
        minor_event_count,
        coverage_note,
    )


def _synthesized_reasoning(
    ticker: str,
    scores: dict,
    coverage_state: str,
    source_count: int,
    coverage_note: str,
    llm_used: bool,
    total_score: float | None = None,
) -> str:
    news_v = clamp_score(scores.get("news_sentiment"), 0)
    macro_v = clamp_score(scores.get("macro_exposure"), 0)
    vol_v = clamp_score(scores.get("volatility"), 0)
    sector_v = clamp_score(scores.get("sector_exposure"), 0)
    fin_v = clamp_score(scores.get("financial_health"), 0)

    drivers: list[str] = []

    if news_v <= 35:
        drivers.append("Negative company-specific news")
    elif news_v >= 65:
        drivers.append("Positive news support")

    if macro_v <= 35:
        drivers.append("Macro pressure on the sector")
    elif macro_v <= 45:
        drivers.append("Rate sensitivity adds risk")

    if sector_v <= 40:
        drivers.append("Sector concentration risk")

    if vol_v <= 40:
        drivers.append("Elevated volatility")

    if fin_v <= 45:
        drivers.append("Weak financial health")

    if not drivers:
        if news_v <= 45:
            drivers.append("Negative news pressure")
        elif news_v >= 55:
            drivers.append("Positive news support")
        elif macro_v <= 45:
            drivers.append("Macro sensitivity")
        elif vol_v <= 45:
            drivers.append("Moderate volatility")
        else:
            drivers.append("Structural profile dominant")

    if coverage_state in ("provisional", "thin"):
        drivers = drivers[:1] + ["Limited data — fundamentals dominate"]

    return "\n".join(drivers[:2])


def _article_evidence_brief(position_data: dict, limit: int = 4) -> str:
    evidence_rows = list(position_data.get("article_evidence") or [])
    if not evidence_rows:
        evidence_rows = []
        for event in list(position_data.get("event_analyses") or []):
            evidence_rows.append(
                {
                    "title": event.get("title"),
                    "source": event.get("source"),
                    "published_at": event.get("published_at"),
                    "evidence_quality": event.get("evidence_quality"),
                    "excerpt": event.get("article_excerpt") or event.get("summary") or "",
                }
            )

    lines: list[str] = []
    for row in evidence_rows[:limit]:
        title = str(row.get("title") or "").strip()
        source = str(row.get("source") or "").strip()
        published_at = str(row.get("published_at") or "").strip()[:19]
        evidence_quality = str(row.get("evidence_quality") or "").strip()
        excerpt = str(row.get("excerpt") or row.get("summary") or "").strip()
        if excerpt:
            excerpt = excerpt[:180]
        parts = [part for part in [title, source, published_at, evidence_quality] if part]
        if excerpt:
            parts.append(excerpt)
        if parts:
            lines.append(" | ".join(parts))

    return "\n".join(lines)


def _parse_batch_scores(raw_text: str, tickers: list[str]) -> dict[str, dict]:
    parsed = extract_json_object(raw_text, None)
    if isinstance(parsed, dict):
        for key in ("scores", "results"):
            candidate = parsed.get(key)
            if candidate is not None:
                parsed = candidate
                break

    expected = {str(t).strip().upper() for t in tickers if str(t).strip()}
    scores: dict[str, dict] = {}

    if isinstance(parsed, dict):
        for key, value in parsed.items():
            ticker = str(key).strip().upper()
            if expected and ticker not in expected:
                continue
            if isinstance(value, dict):
                scores[ticker] = value

        if scores:
            return scores

        ticker = parsed.get("ticker") or parsed.get("symbol")
        if ticker:
            ticker_key = str(ticker).strip().upper()
            if not expected or ticker_key in expected:
                return {ticker_key: parsed}

    if isinstance(parsed, list):
        for item in parsed:
            if not isinstance(item, dict):
                continue

            ticker = item.get("ticker") or item.get("symbol")
            if ticker:
                ticker_key = str(ticker).strip().upper()
                if not expected or ticker_key in expected:
                    scores[ticker_key] = item
                continue

            if len(item) == 1:
                key, value = next(iter(item.items()))
                ticker_key = str(key).strip().upper()
                if isinstance(value, dict) and (not expected or ticker_key in expected):
                    scores[ticker_key] = value

        if scores:
            return scores

    return {}


logger = logging.getLogger(__name__)


def _safe_float(value, default: float = 0.0) -> float:
    try:
        if value is None or value == "":
            return default
        return float(value)
    except Exception:
        return default


def _parse_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        normalized = str(value).replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except Exception:
        return None


def _event_age_days(event: dict) -> float:
    published_at = _parse_timestamp(event.get("published_at"))
    if published_at is None:
        return 7.0
    delta = datetime.now(timezone.utc) - published_at
    return max(0.0, delta.total_seconds() / 86400.0)


def _risk_direction_value(direction: str | None) -> int:
    normalized = str(direction or "neutral").strip().lower()
    if normalized == "worsening":
        return -1
    if normalized == "improving":
        return 1
    return 0


def _deterministic_dimension_scores(
    position_data: dict,
    portfolio_total_value: float,
) -> dict:
    event_analyses = list(position_data.get("event_analyses") or [])
    (
        coverage_state,
        source_count,
        major_event_count,
        minor_event_count,
        coverage_note,
    ) = _data_state_for_position(position_data)
    ticker_metadata = position_data.get("ticker_metadata") or {}
    is_etf_position = _is_etf(position_data)

    worsening_major = 0
    improving_major = 0
    for event in event_analyses:
        direction = _risk_direction_value(event.get("risk_direction"))
        significance = str(event.get("significance") or "minor").strip().lower()
        if significance == "major" and direction < 0:
            worsening_major += 1
        if significance == "major" and direction > 0:
            improving_major += 1

    # --- Dimension 1: Financial Health / Holdings Quality (0-100) ---
    if is_etf_position:
        ticker_str = str(position_data.get("ticker") or "").upper()
        precomputed = ticker_metadata.get("etf_holdings_risk")
        fin = int(precomputed) if precomputed is not None else (
            _score_etf_holdings_risk(ticker_str) or _score_financial_health(ticker_metadata)
        )
        fin_rationale = "Holdings quality score based on weighted avg risk of top constituents."
    else:
        fin = _score_financial_health(ticker_metadata)
        fin_rationale = _fin_rationale(ticker_metadata, fin)

    # --- Dimension 2: News Sentiment (0-100) ---
    news_delta = 0.0
    for event in event_analyses:
        direction = _risk_direction_value(event.get("risk_direction"))
        significance = str(event.get("significance") or "minor").strip().lower()
        confidence = min(max(_safe_float(event.get("confidence"), 0.5), 0.2), 1.0)
        age_days = _event_age_days(event)
        recency = max(0.35, 1.0 - min(age_days, 14.0) / 20.0)
        magnitude = 15 if significance == "major" else 7
        # Title-only articles carry much less signal — penalise lack of body depth
        evidence_quality = str(event.get("evidence_quality") or "").strip().lower()
        if evidence_quality == "title_only":
            depth_weight = 0.4
        elif evidence_quality == "headline_summary":
            depth_weight = 0.65
        else:
            depth_weight = 1.0
        news_delta += direction * magnitude * confidence * recency * depth_weight

    news_sentiment = clamp_score(round(50 + news_delta), 0)
    news_rationale = (
        f"News risk is driven by {worsening_major} major negative development(s) and improved by {improving_major} positive one(s)."
        if event_analyses
        else "No recent news with a clear directional signal — rating defaults to neutral pending new data."
    )

    # --- Dimension 3: Macro Exposure (0-100) ---
    macro_exposure = _score_macro_exposure(ticker_metadata)
    macro_rationale = _macro_rationale(ticker_metadata, macro_exposure)

    # --- Dimension 4: Sector Exposure (0-100) ---
    sector_exposure = _score_sector_exposure(ticker_metadata)
    sector_rationale = _sector_rationale(ticker_metadata, sector_exposure)

    # --- Dimension 5: Volatility (0-100) ---
    volatility = _score_volatility(ticker_metadata, worsening_major, improving_major)
    vol_rationale = _vol_rationale(ticker_metadata, volatility, worsening_major)

    normalized_scores = {
        "financial_health": fin,
        "news_sentiment": news_sentiment,
        "macro_exposure": macro_exposure,
        "sector_exposure": sector_exposure,
        "volatility": volatility,
    }
    weighted = calculate_weighted_score(normalized_scores)
    _meta = position_data.get("ticker_metadata") or {}
    total = round(
        smooth_score_change(
            new_score=weighted,
            previous_score=position_data.get("previous_total_score"),
            market_cap=_meta.get("market_cap"),
        ),
        1,
    )
    grade = score_to_grade(total)

    reasoning = _synthesized_reasoning(
        str(position_data.get("ticker") or "this ticker"),
        normalized_scores,
        coverage_state,
        source_count,
        coverage_note,
        llm_used=False,
        total_score=total,
    )
    formatted_reasoning = format_rationale(
        grade=grade,
        direction=grade_direction(total, position_data.get("previous_total_score")),
        raw_text=reasoning,
        scores=normalized_scores,
        source_count=source_count,
    )

    out = {
        **normalized_scores,
        "total_score": total,
        "grade": grade,
        "grade_direction": grade_direction(total, position_data.get("previous_total_score")),
        "score_delta": int(round(total - position_data.get("previous_total_score", total))),
        "reasoning": formatted_reasoning,
        "evidence_summary": position_data.get("summary", ""),
        "dimension_rationale": {
            "financial_health": fin_rationale,
            "news_sentiment": news_rationale,
            "macro_exposure": macro_rationale,
            "sector_exposure": sector_rationale,
            "volatility": vol_rationale,
        },
        "source_count": source_count,
        "major_event_count": major_event_count,
        "minor_event_count": minor_event_count,
        "coverage_state": coverage_state,
        "coverage_note": coverage_note,
        "is_provisional": coverage_state != "substantive",
        "evidence_strength": evidence_strength(source_count),
        "llm_scoring_used": False,
    }
    if is_etf_position:
        out["dimension_labels"] = ETF_DIMENSION_LABELS
    return out


# ════════════════════════════════════════════════════════════════════════════
# V2 Dimension Scorers
# ════════════════════════════════════════════════════════════════════════════

def _score_financial_health(metadata: dict) -> int:
    d_e = _safe_float(metadata.get("debt_to_equity"))
    fcf_margin = _safe_float(metadata.get("fcf_margin"))
    interest_cov = _safe_float(metadata.get("interest_coverage"))
    current_ratio = _safe_float(metadata.get("current_ratio"))
    rev_growth = _safe_float(metadata.get("revenue_growth_trend"))

    score = 50.0

    if d_e > 0:
        if d_e <= 0.3:
            score += 8
        elif d_e <= 0.7:
            score += 4
        elif d_e <= 1.5:
            score += 0
        elif d_e <= 3.0:
            score -= 6
        else:
            score -= 12

    # Ignore an FCF margin that exceeds revenue: it is not achievable by a real
    # operating business and only appears when op-cash-flow is used as an FCF proxy
    # for financials (see edgar_client.validate_fcf_margin). Source data is already
    # clamped, but this keeps a legacy/other-source outlier from maxing the bonus.
    if 0 < fcf_margin <= 1.0:
        if fcf_margin >= 0.20:
            score += 10
        elif fcf_margin >= 0.10:
            score += 6
        elif fcf_margin >= 0.05:
            score += 2
        else:
            score -= 4

    if interest_cov > 0:
        if interest_cov >= 20:
            score += 8
        elif interest_cov >= 5:
            score += 4
        elif interest_cov >= 2:
            score += 0
        else:
            score -= 6

    if current_ratio > 0:
        if current_ratio >= 2.0:
            score += 6
        elif current_ratio >= 1.0:
            score += 2
        elif current_ratio < 0.5:
            score -= 5

    if rev_growth is not None and rev_growth != 0:
        # revenue_growth_trend is stored as a PERCENT (e.g. 15.55 == 15.55%, max ~260),
        # but the thresholds below are fractions (0.30 == 30%). Without this conversion
        # ~89% of tickers tripped the top bonus and the input stopped discriminating.
        rev_growth_frac = rev_growth / 100.0
        if rev_growth_frac >= 0.30:
            score += 8
        elif rev_growth_frac >= 0.10:
            score += 4
        elif rev_growth_frac >= 0.0:
            score += 1
        else:
            score -= 5

    if metadata.get("profitability_profile") == "profitable":
        score += 4
    elif metadata.get("profitability_profile") == "unprofitable":
        score -= 5

    return clamp_score(round(score), 0)


def _fin_rationale(metadata: dict, score: int) -> str:
    parts = []
    d_e = _safe_float(metadata.get("debt_to_equity"))
    fcf_margin = _safe_float(metadata.get("fcf_margin"))
    if d_e > 0:
        parts.append(f"D/E {d_e:.2f}")
    if 0 < fcf_margin <= 1.0:
        parts.append(f"FCF margin {fcf_margin:.0%}")
    if parts:
        return f"Financials reflect {', '.join(parts)}."
    return "Fundamentals based on available data."


def _score_macro_exposure(metadata: dict) -> int:
    factor_breakdown = metadata.get("factor_breakdown") or {}
    if isinstance(factor_breakdown, str):
        import json

        try:
            factor_breakdown = json.loads(factor_breakdown)
        except Exception:
            factor_breakdown = {}
    reg = factor_breakdown.get("macro_regression") or {}
    _reg_r2 = _safe_float(reg.get("r_squared"), 0.0) if isinstance(reg, dict) else 0.0
    # A regression with R^2 < 0.10 has no real explanatory power. Across the whole
    # universe the per-ticker fit sat at ~0.02, so the regression path collapsed to a
    # near-constant ~90 that inflated every macro score (and every grade). Only trust
    # the regression when it actually fits; otherwise fall through to the beta-based
    # macro-sensitivity heuristic, which discriminates by how much the name moves with
    # the market.
    if isinstance(reg, dict) and not reg.get("limited_data") and _reg_r2 >= 0.10:
        sensitivity_score = reg.get("sensitivity_score")
        if sensitivity_score is None:
            coefficients = reg.get("coefficients") or {}
            sensitivity = math.sqrt(
                sum(float(value) ** 2 for value in coefficients.values())
            )
            sensitivity_score = 100.0 * (1.0 - min(1.0, sensitivity / 5.0))
        if sensitivity_score is not None:
            # Floor at 30: even a maximally market-sensitive name is not "zero" on macro.
            # A 0 here (high-beta semis: huge SPY coefficient -> sensitivity>=5 -> score 0)
            # double-counts beta with the volatility dimension and cratered fin-strong names.
            return clamp_score(round(max(sensitivity_score, 30.0)), 0)

    beta = abs(_safe_float(metadata.get("beta"), 0.0))
    macro_sens = str(metadata.get("macro_sensitivity") or "moderate").lower()

    if beta > 0:
        # Market beta is the macro-sensitivity proxy when a real multi-factor regression
        # is unavailable (free data tier has no credit-spread / real DXY / real 10Y). Map
        # it CONTINUOUSLY so the dimension discriminates smoothly: beta 0.5->72, 1.0->63,
        # 1.5->54, 2.0->45. Lower beta == less macro-sensitive == more resilient.
        # CAP the penalty at beta 2.0 (floor 45): a genuinely high-beta cyclical (semis run
        # beta 3-5) must not be floored to ~0 on a single proxy — beta cyclicality is already
        # reflected in the volatility dimension, so an unbounded penalty here double-counts it
        # and unfairly cratered financially-strong names (MU/AVGO/NVDA) to an F.
        score = 81.0 - (min(beta, 2.0) * 18.0)
    else:
        score = 65.0

    if macro_sens == "low":
        score += 5
    elif macro_sens == "very_high":
        score -= 10
    elif macro_sens == "high":
        score -= 5

    # Floor at 30 (same rationale as the regression path): macro must not crater to 0.
    return clamp_score(round(max(score, 30.0)), 0)


def _macro_rationale(metadata: dict, score: int) -> str:
    factor_breakdown = metadata.get("factor_breakdown") or {}
    if isinstance(factor_breakdown, str):
        import json

        try:
            factor_breakdown = json.loads(factor_breakdown)
        except Exception:
            factor_breakdown = {}
    reg = factor_breakdown.get("macro_regression") or {}
    if (
        isinstance(reg, dict)
        and reg.get("r_squared") is not None
        and not reg.get("limited_data")
        and _safe_float(reg.get("r_squared"), 0.0) >= 0.10
    ):
        coef = reg.get("coefficients", {})
        top_factor = max(coef.items(), key=lambda x: abs(x[1])) if coef else ("market", 0.0)
        return (
            f"Regression R\xb2={reg['r_squared']:.2f}, "
            f"top driver: {top_factor[0].upper()} ({top_factor[1]:.3f})."
        )

    beta = _safe_float(metadata.get("beta"))
    if beta:
        return f"Beta of {beta:.2f} drives macro sensitivity."
    return "Macro sensitivity based on sector profile."


def _score_sector_exposure(metadata: dict) -> int:
    # Prefer real computed inputs (sector_beta, momentum, breadth from Polygon bars)
    sector_inputs = metadata.get("sector_inputs") or {}

    # Asset-class fallback for diversified/bond/commodity funds (no GICS sector tape):
    # a precomputed, honest score (not a NULL). See _build_sector_exposure_inputs.
    # NOTE: read raw values and test None BEFORE coercing — `_safe_float` defaults to
    # 0.0 (never None), so coercing first would make every "missing" key look present.
    raw_fallback = sector_inputs.get("fallback_score")
    if raw_fallback is not None:
        return clamp_score(round(_safe_float(raw_fallback)), 0)

    raw_beta = sector_inputs.get("sector_beta")
    raw_momentum = sector_inputs.get("sector_momentum_30d")
    raw_breadth = sector_inputs.get("sector_breadth")
    raw_rel = sector_inputs.get("relative_strength_30d")

    if raw_beta is not None or raw_momentum is not None or raw_rel is not None:
        # Real data path. De-inflated baseline (was 65) + per-ticker terms so names in
        # the same sector no longer collapse to one shared value.
        score = 60.0
        # Per-ticker sector beta (now real & date-aligned, WS-A): higher beta = more
        # cyclical sector exposure = more risk. Steeper than the old *8.
        if raw_beta is not None:
            score -= (_safe_float(raw_beta) - 1.0) * 14.0
        # Per-ticker relative strength vs its sector: outperformance = resilience.
        if raw_rel is not None:
            score += max(-14.0, min(14.0, _safe_float(raw_rel) * 70.0))
        # Shared sector momentum: SMALL weight (identical across a sector).
        if raw_momentum is not None:
            score += max(-5.0, min(5.0, _safe_float(raw_momentum) * 30.0))
        # Shared breadth: small weight.
        if raw_breadth is not None:
            score += (_safe_float(raw_breadth) - 0.5) * 8.0
        return clamp_score(round(score), 0)

    # Fallback: heuristic based on sector class + market cap (de-inflated baseline).
    sector = str(metadata.get("sector") or "").strip().lower()
    market_cap = _safe_float(metadata.get("market_cap"))

    score = 60.0

    defensive = {"healthcare", "consumer staples", "utilities"}
    cyclical = {"financials", "energy", "real estate", "realestate", "materials", "industrials"}

    if sector in defensive:
        score += 6
    elif sector in cyclical:
        score -= 6

    if market_cap and market_cap >= 200e9:
        score += 4
    elif market_cap and market_cap < 2e9:
        score -= 6

    return clamp_score(round(score), 0)


def _sector_rationale(metadata: dict, score: int) -> str:
    sector = str(metadata.get("sector") or "").title()
    if sector:
        return f"Sector exposure shaped by {sector} profile."
    return "Sector exposure based on industry classification."


def _score_volatility(metadata: dict, worsening_major: int, improving_major: int) -> int:
    # Prefer real computed inputs (realized_vol, beta_to_spy, drawdown from Polygon bars)
    vol_inputs = metadata.get("volatility_inputs") or {}
    realized_vol_30d = _safe_float(vol_inputs.get("realized_vol_30d"))
    beta_to_spy = _safe_float(vol_inputs.get("beta_to_spy"))
    max_drawdown = _safe_float(vol_inputs.get("max_drawdown_252d"))

    if realized_vol_30d is not None or beta_to_spy is not None:
        # Real data path. De-inflated baseline (was 78 → avg score 81 hugged the ceiling);
        # realized vol and the now-real beta_to_spy (WS-A/WS-C) pull it down.
        # Calibration: SPY rv30~0.12,beta~1.0 → ~67; TSLA rv30~0.55,beta~1.7 → ~38
        score = 62.0
        if realized_vol_30d is not None:
            # 0.20 (20% ann vol) = neutral; gentler slope (was 60) so an ultra-volatile
            # but financially-sound name is not driven to ~0.
            score -= (realized_vol_30d - 0.20) * 50.0
        # NOTE: beta_to_spy intentionally NOT penalized here. Systematic-beta risk is already
        # captured by the macro dimension; penalizing it again in volatility double-counted it
        # (macro/vol correlated ~0.80) and floored high-beta semis to F. Volatility is now
        # realized-vol + drawdown driven (idiosyncratic), de-correlated from macro.
        if max_drawdown is not None:
            # max_drawdown is negative (e.g. -0.40 = 40% peak-to-trough)
            # Larger drawdown = lower score; each 10% drawdown costs 3 pts
            score += max_drawdown * 30.0
        score -= worsening_major * 5
        score += improving_major * 3
        return clamp_score(round(score), 0)

    # Fallback: proxy-based (unchanged legacy path)
    volatility_proxy = _safe_float(metadata.get("volatility_proxy"), 0.0)
    beta = abs(_safe_float(metadata.get("beta"), 0.0))

    score = 78.0 - (volatility_proxy * 40)
    if beta:
        score -= min(18, max(0.0, (beta - 1.0) * 10))
    score -= worsening_major * 5
    score += improving_major * 3
    return clamp_score(round(score), 0)


def _vol_rationale(metadata: dict, score: int, worsening_major: int) -> str:
    beta = _safe_float(metadata.get("beta"))
    if beta and beta > 1.2:
        return f"Beta of {beta:.2f} amplifies volatility exposure."
    if worsening_major:
        return "Recent negative events add upward pressure to volatility."
    return "Volatility is within normal range for this profile."


# ════════════════════════════════════════════════════════════════════════════
# LLM path
# ════════════════════════════════════════════════════════════════════════════

def _needs_llm_scoring(position_data: dict) -> bool:
    return not any(
        [
            position_data.get("event_analyses"),
            position_data.get("macro_impact"),
            position_data.get("ticker_metadata"),
        ]
    )


def _prefer_llm_scoring(position_data: dict) -> bool:
    if position_data.get("event_analyses"):
        return True

    summary = str(position_data.get("summary") or "").strip()
    long_report = str(position_data.get("long_report") or "").strip()
    return bool(summary or long_report)


def _join_labels(values: list[object] | None) -> str:
    return ", ".join(
        str(value).strip() for value in (values or []) if str(value or "").strip()
    )


def _llm_score_prompt(position_data: dict) -> str:
    article_evidence = _article_evidence_brief(position_data)
    evidence_block = (
        f"\n\nSelected article evidence:\n{article_evidence}" if article_evidence else ""
    )
    return SYSTEM_PROMPT.format(
        ticker=position_data.get("ticker", ""),
        shares=position_data.get("shares", 0),
        purchase_price=position_data.get("purchase_price", 0),
        position_value=round(_safe_float(position_data.get("position_value"), 0.0), 2),
        labels=_join_labels(position_data.get("inferred_labels")),
        summary=position_data.get("summary", ""),
        long_report=(position_data.get("long_report", "") or "") + evidence_block,
    )


async def score_position(
    position: dict,
    position_report: dict,
    inferred_labels: list[str] | None = None,
) -> dict:
    position_data = {
        **position,
        **position_report,
        "inferred_labels": inferred_labels
        or position_report.get("inferred_labels", []),
    }
    position_data["position_value"] = max(
        _safe_float(
            position_data.get("current_price") or position_data.get("purchase_price")
        )
        * _safe_float(position_data.get("shares")),
        0.0,
    )
    # Pre-fetch ETF holdings risk to inject into ticker_metadata before scoring
    is_etf_pos = _is_etf(position_data)
    if is_etf_pos:
        ticker_str = str(position_data.get("ticker") or "").upper()
        holdings_risk = await asyncio.to_thread(_score_etf_holdings_risk, ticker_str)
        if holdings_risk is not None:
            meta = dict(position_data.get("ticker_metadata") or {})
            meta["etf_holdings_risk"] = holdings_risk
            position_data = {**position_data, "ticker_metadata": meta}

    deterministic = _deterministic_dimension_scores(
        position_data,
        portfolio_total_value=max(
            _safe_float(position_data.get("purchase_price"))
            * _safe_float(position_data.get("shares")),
            1.0,
        ),
    )
    if not _prefer_llm_scoring(position_data) and not _needs_llm_scoring(position_data):
        return deterministic

    prompt = _etf_llm_prompt(position_data) if is_etf_pos else _llm_score_prompt(position_data)

    def _request_scores() -> tuple[str, dict]:
        result_text = chatcompletion_text(
            messages=[
                {
                    "role": "system",
                    "content": "You MUST respond with valid JSON only. No markdown. No explanation. No thinking. Start with { and end with }.",
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.0,
            top_p=1,
            frequency_penalty=0,
            presence_penalty=0,
            max_tokens=1500,
        )
        return result_text, extract_json_object(result_text, {})

    result_text, scores = await asyncio.to_thread(_request_scores)
    missing_dimensions = [key for key in DIMENSION_KEYS if scores.get(key) is None]
    if missing_dimensions:
        logger.warning(
            "score_position parse failure for %s; missing=%s; raw=%r",
            position.get("ticker", ""),
            missing_dimensions,
            (result_text or "")[:800],
        )
        retry_text, retry_scores = await asyncio.to_thread(_request_scores)
        retry_missing = [
            key for key in DIMENSION_KEYS if retry_scores.get(key) is None
        ]
        if len(retry_missing) < len(missing_dimensions):
            result_text, scores = retry_text, retry_scores
            missing_dimensions = retry_missing

    if missing_dimensions:
        logger.error(
            "score_position falling back to defaults for %s; missing=%s; raw=%r",
            position.get("ticker", ""),
            missing_dimensions,
            (result_text or "")[:800],
        )
        return deterministic

    normalized_scores = {
        key: clamp_score(scores.get(key), 0)
        for key in DIMENSION_KEYS
    }
    (
        coverage_state,
        source_count,
        major_event_count,
        minor_event_count,
        coverage_note,
    ) = _data_state_for_position(position_data)

    weighted = calculate_weighted_score(normalized_scores)
    _single_meta = position_data.get("ticker_metadata") or {}
    total = round(
        smooth_score_change(
            new_score=weighted,
            previous_score=position_report.get("previous_total_score"),
            market_cap=_single_meta.get("market_cap"),
        ),
        1,
    )
    grade = score_to_grade(total)
    dimension_rationale = scores.get("dimension_rationale") or {}
    reasoning = (scores.get("reasoning") or "").strip()
    if not reasoning:
        reasoning = _synthesized_reasoning(
            str(position_data.get("ticker") or "this ticker"),
            normalized_scores,
            coverage_state,
            source_count,
            coverage_note,
            llm_used=True,
            total_score=total,
        )
    formatted_reasoning = format_rationale(
        grade=grade,
        direction=grade_direction(total, position_report.get("previous_total_score")),
        raw_text=reasoning,
        scores=normalized_scores,
        source_count=source_count,
    )

    return {
        **normalized_scores,
        "total_score": total,
        "grade": grade,
        "grade_direction": grade_direction(total, position_report.get("previous_total_score")),
        "score_delta": int(round(total - position_report.get("previous_total_score", total))),
        "reasoning": formatted_reasoning,
        "evidence_summary": scores.get("evidence_summary") or position_data.get("summary", ""),
        "dimension_rationale": dimension_rationale,
        "source_count": source_count,
        "major_event_count": major_event_count,
        "minor_event_count": minor_event_count,
        "coverage_state": coverage_state,
        "coverage_note": coverage_note,
        "is_provisional": coverage_state != "substantive",
        "evidence_strength": evidence_strength(source_count),
        "llm_scoring_used": True,
        **({"dimension_labels": ETF_DIMENSION_LABELS} if is_etf_pos else {}),
    }


def _dimension_confidence_weights(
    metadata: dict, normalized: dict, article_count: int
) -> dict[str, float]:
    """Per-dimension confidence in [0,1]: a thin proxy counts less than a real signal.

    - financial: completeness of the fundamental inputs.
    - news: number of usable articles (10+ == full confidence).
    - macro: real regression R^2 vs the beta-proxy fallback (free tier).
    - sector / volatility: real computed beta / realized vol vs heuristic.
    Floors keep every present dimension meaningful (never below 0.5) so the weighting
    tilts the mean toward better-supported inputs without letting any one dominate.
    """
    weights: dict[str, float] = {}

    fund_keys = (
        "debt_to_equity", "fcf_margin", "interest_coverage",
        "current_ratio", "revenue_growth_trend",
    )
    present = sum(1 for k in fund_keys if metadata.get(k) is not None)
    weights["financial_health"] = 0.5 + 0.5 * (present / len(fund_keys))

    weights["news_sentiment"] = (
        max(0.0, min(1.0, 0.3 + 0.07 * article_count))
        if normalized.get("news_sentiment") is not None else 0.0
    )

    factor_breakdown = metadata.get("factor_breakdown") or {}
    if isinstance(factor_breakdown, str):
        import json

        try:
            factor_breakdown = json.loads(factor_breakdown)
        except Exception:
            factor_breakdown = {}
    reg = factor_breakdown.get("macro_regression") or {} if isinstance(factor_breakdown, dict) else {}
    r2 = _safe_float(reg.get("r_squared"), 0.0) if isinstance(reg, dict) else 0.0
    if isinstance(reg, dict) and not reg.get("limited_data") and r2 >= 0.10:
        weights["macro_exposure"] = min(1.0, 0.6 + r2)
    else:
        weights["macro_exposure"] = 0.5  # beta proxy: real but lower-confidence

    weights["sector_exposure"] = 0.8 if metadata.get("sector_beta") is not None else 0.5
    weights["volatility"] = 0.85 if metadata.get("realized_vol_30d") is not None else 0.6
    return weights


def score_position_structural(
    position: dict,
    ticker_metadata: dict | None = None,
    regime_state: str = "neutral",
    recent_events: list[dict] | None = None,
    previous_safety_score: float | None = None,
) -> dict:
    if ticker_metadata is None:
        ticker_metadata = {}
    if recent_events is None:
        recent_events = []

    worsening_major = 0
    improving_major = 0
    for event in recent_events:
        direction = _risk_direction_value(event.get("risk_direction"))
        significance = str(event.get("significance") or "minor").strip().lower()
        if significance == "major" and direction < 0:
            worsening_major += 1
        if significance == "major" and direction > 0:
            improving_major += 1

    fin = _score_financial_health(ticker_metadata)
    macro = _score_macro_exposure(ticker_metadata)
    sector = _score_sector_exposure(ticker_metadata)
    vol = _score_volatility(ticker_metadata, worsening_major, improving_major)

    weighted_news = 0.0
    total_weight = 0.0
    article_count = len(recent_events)
    scorable_count = 0
    for e in recent_events:
        recency_w = _safe_float(e.get("recency_weight"), 1.0)
        source_w = _safe_float(e.get("source_weight"), 1.0)
        # WS-D: ONLY real sentiment scores count. Do not fall back to event confidence
        # (a different concept) and do not manufacture a 50 for unscorable articles —
        # both reintroduce the neutral-50 pileup this fix removes. Read the RAW value and
        # test None BEFORE coercing: _safe_float(None) returns 0.0, which would otherwise
        # count every unscored article as a sentiment of 0 and collapse the dimension.
        raw_sent = e.get("sentiment_score")
        if raw_sent is not None:
            sent = _safe_float(raw_sent)
            w = recency_w * source_w
            weighted_news += sent * w
            total_weight += w
            scorable_count += 1
    if total_weight > 0 and scorable_count >= 3:
        news = clamp_score(round(weighted_news / total_weight), 0)
    else:
        # Not enough genuinely-scorable articles → honest limited-data NULL, never 50.
        news = None

    # Prefer the wide, recency-weighted news score computed upstream (28-day, up to
    # ~60 relevant articles) over this narrow recent_events window: the 10 newest
    # events are often freshly ingested and not yet enriched, which otherwise drove
    # the news dimension to NULL for names that DO have plenty of scored coverage.
    # Gated on not-limited so a genuinely thin ticker still resolves to an honest
    # NULL rather than a manufactured score. (2026-06-30)
    _news_inputs = ticker_metadata.get("news_inputs") or {}
    if isinstance(_news_inputs, dict) and not _news_inputs.get("limited_data"):
        _wide_news = _news_inputs.get("weighted_score")
        if _wide_news is not None:
            news = clamp_score(round(float(_wide_news)), 0)

    normalized = {
        "financial_health": fin,
        "news_sentiment": news,
        "macro_exposure": macro,
        "sector_exposure": sector,
        "volatility": vol,
    }
    # Quality-weighted mean: weight each dimension by signal confidence so a thin proxy
    # counts less than a real signal. Gated off via env for easy A/B / rollback.
    if os.getenv("DISABLE_QUALITY_WEIGHTING", "").lower() in ("1", "true", "yes"):
        weighted = calculate_weighted_score(normalized)
    else:
        weighted = calculate_weighted_score(
            normalized,
            weights=_dimension_confidence_weights(ticker_metadata, normalized, article_count),
        )
    # WS-E: on the one-time re-spread run, bypass the daily-move cap so the freshly
    # stretched composite is written in full instead of being throttled back toward the
    # old compressed score (the cap would otherwise limit each name to ~+/-cap per day,
    # collapsing the new spread). Normal runs keep the cap for day-over-day stability.
    if os.getenv("COMPOSITE_RESPREAD_BYPASS_SMOOTHING", "").lower() in ("1", "true", "yes"):
        total = round(weighted, 1)
    else:
        total = round(
            smooth_score_change(
                new_score=weighted,
                previous_score=previous_safety_score,
            ),
            1,
        )
    grade = score_to_grade(total)

    source_count = len(recent_events)
    major_event_count = sum(
        1 for e in recent_events
        if str(e.get("significance") or "minor").strip().lower() == "major"
    )
    minor_event_count = max(source_count - major_event_count, 0)

    if source_count == 0:
        coverage_state = "provisional"
        coverage_note = "No recent event data was available."
    elif source_count <= 2:
        coverage_state = "thin"
        coverage_note = f"Limited data: {source_count} recent event(s)."
    else:
        coverage_state = "substantive"
        coverage_note = f"{source_count} recent event(s) supported this score."

    structural_reasoning = format_rationale(
        grade=grade,
        direction=grade_direction(total, previous_safety_score),
        raw_text="Structural profile dominant",
        scores=normalized,
        source_count=source_count,
    )

    existing_factor_breakdown = ticker_metadata.get("factor_breakdown") or {}
    if isinstance(existing_factor_breakdown, str):
        import json

        try:
            existing_factor_breakdown = json.loads(existing_factor_breakdown)
        except Exception:
            existing_factor_breakdown = {}

    return {
        "safety_score": total,
        "total_score": total,
        "composite_score": total,
        "structural_base_score": total,
        "macro_adjustment": 0.0,
        "event_adjustment": 0.0,
        # WS-G: the risk-score `confidence` was a hard-coded 0.75 with no meaning. A
        # facts product has no place for a fabricated confidence figure, so it is gone.
        # (Per-article and portfolio confidence are different concepts and remain.)
        "grade": grade,
        "grade_direction": grade_direction(total, previous_safety_score),
        "score_delta": int(round(total - previous_safety_score)) if previous_safety_score is not None else None,
        "reasoning": structural_reasoning,
        "dimension_rationale": {
            "financial_health": _fin_rationale(ticker_metadata, fin),
            "news_sentiment": "Event-driven sentiment from available articles.",
            "macro_exposure": _macro_rationale(ticker_metadata, macro),
            "sector_exposure": _sector_rationale(ticker_metadata, sector),
            "volatility": _vol_rationale(ticker_metadata, vol, worsening_major),
        },
        "factor_breakdown": {
            **existing_factor_breakdown,
            "ai_dimensions": normalized,
        },
        **normalized,
        "source_count": source_count,
        "major_event_count": major_event_count,
        "minor_event_count": minor_event_count,
        "coverage_state": coverage_state,
        "coverage_note": coverage_note,
        "is_provisional": coverage_state != "substantive",
        "evidence_strength": evidence_strength(source_count),
    }


async def score_positions_batch(
    positions_data: list[dict],
) -> list[dict]:
    if not positions_data:
        return []

    portfolio_total_value = (
        sum(
            max(
                _safe_float(
                    p.get("current_price")
                    or (p.get("ticker_metadata") or {}).get("price")
                    or p.get("purchase_price")
                )
                * _safe_float(p.get("shares")),
                0.0,
            )
            for p in positions_data
        )
        or 1.0
    )

    results = [
        _deterministic_dimension_scores(position, portfolio_total_value)
        for position in positions_data
    ]

    sparse_positions = [
        (index, position)
        for index, position in enumerate(positions_data)
        if _prefer_llm_scoring(position) or _needs_llm_scoring(position)
    ]
    if not sparse_positions:
        return results

    import re

    llm_chunk_size = (
        3
        if any(_prefer_llm_scoring(position) for _, position in sparse_positions)
        else 8
    )

    for chunk_start in range(0, len(sparse_positions), llm_chunk_size):
        chunk = sparse_positions[chunk_start : chunk_start + llm_chunk_size]
        tickers = [position.get("ticker", "") for _, position in chunk]
        evidence_texts = []
        for i, (_, position) in enumerate(chunk):
            evidence = _article_evidence_brief(position, limit=3)
            if evidence:
                evidence_texts.append(f"Position {i + 1} article evidence:\n{evidence}")
        positions_text = "\n".join(
            f"""Position {i + 1}:
- Ticker: {position.get("ticker", "")}
- Shares: {position.get("shares", 0)} @ ${position.get("purchase_price", 0)}
- Approximate current price: ${position.get("current_price") or position.get("purchase_price", 0)}
- Estimated position value: ${round(_safe_float(position.get("current_price") or position.get("purchase_price")) * _safe_float(position.get("shares")), 2)}
- Portfolio weight: {round(((_safe_float(position.get("current_price") or position.get("purchase_price")) * _safe_float(position.get("shares"))) / portfolio_total_value) * 100, 2)}%
- Inferred labels: {_join_labels(position.get("inferred_labels")) or position.get("archetype", "core")}
- Position report summary: {position.get("summary", "no summary")[:200]}
- Long report excerpt: {position.get("long_report", "")[:300]}"""
            for i, (_, position) in enumerate(chunk)
        )
        evidence_block = "\n\n".join(evidence_texts)
        score_example = ", ".join(
            f'"{ticker}": {{"financial_health": 50, "news_sentiment": 50, "macro_exposure": 50, "sector_exposure": 50, "volatility": 50, "grade": "C-", "reasoning": "...", "dimension_rationale": {{"financial_health": "...", "news_sentiment": "...", "macro_exposure": "...", "sector_exposure": "...", "volatility": "..."}}, "evidence_summary": "..."}}'
            for ticker in tickers
        )
        prompt = f"""Score each position across 5 dimensions (0-100) and assign a grade.

Scale: 0 = penny-stock-like / very risky, 100 = treasury-like / very safe. Higher = lower risk.

{positions_text}

{evidence_block if evidence_block else ""}

Return EXACTLY this JSON format (no markdown, no explanation, no thinking):
{{"scores": {{{score_example}}}}}

        Scoring criteria:
        - financial_health: strong balance sheet, cash flow, coverage=high (70-100), weak fundamentals=low (0-40)
        - news_sentiment: positive/supportive news=high (70-100), negative/dangerous news=low (0-40), neutral=50 only when truly balanced
        - macro_exposure: less macro-sensitive=high (70-100), more macro-sensitive=low (0-40)
        - sector_exposure: strong sector with broad participation=high (70-100), weak/concentrated sector=low (0-40)
        - volatility: low/stable/falling volatility=high (70-100), high/rising volatility=low (0-40)
        - Grade bands: A+ (90-100), A (85-89), A- (80-84), B+ (75-79), B (70-74), B- (65-69), C+ (60-64), C (55-59), C- (50-54), D+ (45-49), D (40-44), D- (35-39), F (0-34)

        How to write "reasoning" — strict credit-rating format:
        FORMAT: [GRADE] — [Risk Level] ([arrow]) + max 2 driver lines. Each driver ≤60 chars.
        Arrows: ↓ improving if score improved, ↑ worsening if score dropped, → stable
        Example:
        C+ — Average (↑ worsening)
        Earnings miss on revenue weakness
        Sector rotation into defensives

        Rules:
        1. Each driver MUST name a concrete event, metric change, or sector theme.
        2. If evidence is thin (<3 events), write: "Limited data — risk based on fundamentals"
        3. No paragraphs. No hedging. No "may", "could", "would", "suggests", "indicates"

        Important:
        - Do not return 50 across all five dimensions unless the evidence is genuinely absent.
        - If the evidence is directional, move the relevant dimensions away from 50.

        Forbidden: dimension scores in rationale, "the model", "the score reflects", internal evidence labels, "thesis", "positive momentum", "macro headwinds", "provisional", "sentiment", "confirms", "coverage", "monitor", "research", "analyst", "watch", "portfolio weighting".

Respond with ONLY the JSON object. Start with {{ and end with }}."""

        def _request_chunk_scores() -> tuple[str, dict[str, dict]]:
            result_text = chatcompletion_text(
                messages=[
                    {
                        "role": "system",
                        "content": "You MUST respond with valid JSON only. No markdown. No explanation. No thinking. Start your response with { and end with }.",
                    },
                    {"role": "user", "content": prompt},
                ],
                temperature=0.0,
                top_p=1,
                frequency_penalty=0,
                presence_penalty=0,
                max_tokens=800,
            )
            return result_text, _parse_batch_scores(result_text, tickers)

        result_text, all_scores = await asyncio.to_thread(_request_chunk_scores)
        if _is_batch_response_suspicious(all_scores, tickers):
            logger.warning(
                "score_positions_batch sparse fallback retry; raw=%r",
                (result_text or "")[:800],
            )
            retry_text, retry_scores = await asyncio.to_thread(_request_chunk_scores)
            if not _is_batch_response_suspicious(retry_scores, tickers):
                result_text, all_scores = retry_text, retry_scores

        if not all_scores:
            for ticker in tickers:
                ticker_upper = ticker.upper()
                ticker_scores = {}
                for dim in DIMENSION_KEYS:
                    pattern = rf"{ticker_upper}.*?{dim}.*?(\d+)"
                    match = re.search(pattern, result_text, re.IGNORECASE | re.DOTALL)
                    if match:
                        ticker_scores[dim] = int(match.group(1))
                if ticker_scores:
                    all_scores[ticker_upper] = ticker_scores

        for result_index, position in chunk:
            ticker = str(position.get("ticker") or "").strip().upper()
            raw_scores = all_scores.get(ticker, {})
            if not raw_scores:
                continue
            (
                coverage_state,
                source_count,
                major_event_count,
                minor_event_count,
                coverage_note,
            ) = _data_state_for_position(position)
            if _prefer_llm_scoring(position) and has_suspicious_neutral_scores(
                raw_scores
            ):
                logger.warning(
                    "score_positions_batch keeping deterministic fallback for %s due to neutral AI output",
                    ticker,
                )
                continue
            normalized = {
                key: clamp_score(raw_scores.get(key), 0)
                for key in DIMENSION_KEYS
            }
            reasoning = (raw_scores.get("reasoning") or "").strip()
            if not reasoning:
                reasoning = _synthesized_reasoning(
                    ticker,
                    normalized,
                    coverage_state,
                    source_count,
                    coverage_note,
                    llm_used=True,
                )
            weighted = calculate_weighted_score(normalized)
            _pos_meta = position.get("ticker_metadata") or {}
            total = round(
                smooth_score_change(
                    new_score=weighted,
                    previous_score=position.get("previous_total_score"),
                    market_cap=_pos_meta.get("market_cap"),
                ),
                1,
            )
            grade = score_to_grade(total)
            formatted_reasoning = format_rationale(
                grade=grade,
                direction=grade_direction(total, position.get("previous_total_score")),
                raw_text=reasoning,
                scores=normalized,
                source_count=source_count,
            )
            results[result_index] = {
                **normalized,
                "total_score": total,
                "grade": grade,
                "grade_direction": grade_direction(total, position.get("previous_total_score")),
                "score_delta": int(round(total - position.get("previous_total_score", total))),
                "reasoning": formatted_reasoning,
                "evidence_summary": raw_scores.get("evidence_summary") or position.get("summary", ""),
                "dimension_rationale": raw_scores.get("dimension_rationale") or {},
                "source_count": source_count,
                "major_event_count": major_event_count,
                "minor_event_count": minor_event_count,
                "coverage_state": coverage_state,
                "coverage_note": coverage_note,
                "is_provisional": coverage_state != "substantive",
                "evidence_strength": evidence_strength(source_count),
                "llm_scoring_used": True,
                "factor_breakdown": {
                    "ai_dimensions": normalized,
                },
            }

    return results
