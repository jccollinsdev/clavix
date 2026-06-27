from __future__ import annotations
import re
from typing import Optional
from ..services.minimax import chatcompletion_text
from .analysis_utils import extract_json_object


def _strip_html(text: str) -> str:
    if not text:
        return ""
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _normalize_ticker(value: str | None) -> str:
    return str(value or "").strip().upper()


def _is_valid_sector_name(value: str | None) -> bool:
    normalized = str(value or "").strip().lower()
    return bool(normalized and normalized not in {"unknown", "none", "null", "n/a"})


MACRO_THEMES = [
    "rate_policy",
    "inflation",
    "growth_recession",
    "geopolitics",
    "sector_specific",
    "credit_market",
    "currency",
    "commodities",
]

THEME_LABELS = {
    "rate_policy": "rate policy",
    "inflation": "inflation",
    "growth_recession": "growth and recession",
    "geopolitics": "geopolitics",
    "sector_specific": "sector-specific moves",
    "credit_market": "credit markets",
    "currency": "currency",
    "commodities": "commodities",
}

THEME_KEYWORDS = {
    "rate_policy": [
        "fed",
        "interest rate",
        "yield",
        "bond",
        "rate",
        "central bank",
        "monetary",
        "fomc",
        "basis points",
    ],
    "inflation": [
        "inflation",
        "cpi",
        "pce",
        "price",
        "cost",
        "pricing",
        "hot",
        "moderate",
        "tame",
    ],
    "growth_recession": [
        "gdp",
        "growth",
        "recession",
        "contraction",
        "expansion",
        "slowdown",
        "economy",
        "jobs",
        "unemployment",
    ],
    "geopolitics": [
        "china",
        "trade war",
        "tariff",
        "opec",
        "russia",
        "ukraine",
        "middle east",
        "sanctions",
        "export",
    ],
    "sector_specific": [
        "bank",
        "energy",
        "tech",
        "healthcare",
        "retail",
        "housing",
        "auto",
    ],
    "credit_market": [
        "credit",
        "spread",
        "high yield",
        "junk",
        "default",
        "leveraged",
        "debt",
    ],
    "currency": ["dollar", "yuan", "euro", "currency", "fx", "foreign exchange"],
    "commodities": [
        "oil",
        "gas",
        "crude",
        "gold",
        "silver",
        "copper",
        "commodity",
        "wheat",
    ],
}


def _detect_macro_themes(articles: list[dict]) -> list[dict]:
    detected = []
    for article in articles:
        text = f"{article.get('title', '')} {article.get('summary', '')}".lower()
        matched_themes = []
        for theme, keywords in THEME_KEYWORDS.items():
            if any(kw in text for kw in keywords):
                matched_themes.append(theme)

        if matched_themes:
            detected.append(
                {
                    "title": article.get("title", ""),
                    "summary": article.get("summary", "")[:300],
                    "source": article.get("source"),
                    "published_at": article.get("published_at"),
                    "themes": matched_themes,
                }
            )
    return detected


SYSTEM_PROMPT = """You write the per-holding "what is moving my stock today" lines for a retail investor's morning portfolio briefing. The investor owns these stocks and wants you to connect the dots: macro -> sector -> their specific stock, and say which way the pressure points.

Return strict JSON with this shape:
{
  "overnight_macro": {
    "headlines": ["2-4 key overnight headlines"],
    "themes": ["up to 3 of: rate_policy, inflation, growth_recession, geopolitics, sector_specific, credit_market, currency, commodities"],
    "brief": "2-3 plain sentences: what happened overnight and what it means for markets"
  },
  "position_impacts": [
    {"ticker": "AMD", "macro_relevance": "supports|contradicts|neutral", "impact_summary": "Exactly 2 sentences, see rules below."}
  ],
  "what_matters_today": [
    {"catalyst": "scheduled event today (earnings, data, Fed speaker)", "impacted_positions": ["AMD"], "urgency": "high|medium|low"}
  ]
}

For EACH holding you are given its sector, today's sector move (when known), its recent company headlines (when known), and the relevant macro themes. Use them.

How to write impact_summary (exactly 2 sentences, plain English, no jargon, no hedging):
1) Sentence 1 names the DOMINANT force acting on THIS stock today and its DIRECTION for someone who owns it: upward pressure, downward pressure, or mixed/flat. Be specific to the ticker, never generic.
2) Sentence 2 connects the chain. If macro is the driver, link macro -> the stock. If macro is quiet but the sector or company news is moving, SAY THAT EXPLICITLY and pivot, e.g. "Macro is quiet, but semis are selling off overnight, which adds downward pressure on AMD." or "The broad tape is calm; the mover here is XOM's own news flow as oil firms up, a modest tailwind."

Hard rules:
- ALWAYS pick the strongest available signal in this order: company-specific news > sector move > macro theme. Only call a holding neutral if NONE of macro, sector, or company news is doing anything to it.
- NEVER output a generic "no clear macro change, focus on company-specific developments" line. If macro is weak, you have sector and company data; use it.
- State a direction in every line (upward / downward / mixed / flat pressure). The owner needs to know which way it cuts for them.
- macro_relevance is judged from the owner's seat (they are long the stock): supports = today's backdrop helps the stock, contradicts = it hurts, neutral = no net read-through from any of macro/sector/company.
- Tie sector moves to sector peers the investor owns when relevant (e.g. AMD and SMCI both ride semis).
- No bloat, no market-commentary filler, no theme keywords echoed verbatim. Two tight sentences per holding.
- Include every holding provided exactly once.
- For themes, use exactly: rate_policy, inflation, growth_recession, geopolitics, sector_specific, credit_market, currency, commodities.
- In the overnight_macro brief, write natural language only. Do not echo theme keys.
- Be specific and factual. Do not speculate beyond the inputs.
"""


SECTOR_SUMMARY_PROMPT = """You summarize overnight sector news for a morning portfolio digest.

Return strict JSON with this shape:
{
  "sector_overview": [
    {
      "sector": "technology",
      "brief": "1-2 sentence summary of what actually happened across the sector overnight",
      "headlines": []
    }
  ]
}

Rules:
- Only include the sectors provided by the user prompt
- Exclude empty, unknown, null, or none sectors
- The brief must synthesize the articles, not repeat or list titles
- Keep the tone calm, concise, and risk-focused
- headlines should be an empty array unless the prompt explicitly asks for them
"""


def _fallback_sector_brief(sector: str, articles: list[dict]) -> dict:
    article_count = len(articles)
    if not article_count:
        brief = f"No material overnight update was identified for {sector}."
    else:
        brief = f"Overnight {sector} data was active across {article_count} item(s), with the main developments concentrated in the sector rather than isolated to a single company headline."
    return {"sector": sector, "brief": brief, "headlines": []}


def _theme_label(theme: str) -> str:
    return THEME_LABELS.get(theme, theme.replace("_", " "))


def _normalize_position_impacts(
    raw_impacts: list[dict],
    positions: list[dict],
    fallback_map: dict[str, dict] | None = None,
) -> list[dict]:
    fallback_map = fallback_map or {}
    impact_map: dict[str, dict] = {}
    for item in raw_impacts or []:
        if not isinstance(item, dict):
            continue
        ticker = _normalize_ticker(item.get("ticker"))
        if not ticker:
            continue
        impact_map[ticker] = {
            "ticker": ticker,
            "macro_relevance": str(item.get("macro_relevance") or "neutral")
            .strip()
            .lower()
            or "neutral",
            "impact_summary": str(item.get("impact_summary") or "").strip(),
        }

    normalized = []
    for position in positions:
        ticker = _normalize_ticker(position.get("ticker"))
        if not ticker:
            continue
        impact = impact_map.get(ticker)
        if impact and impact.get("impact_summary"):
            normalized.append(impact)
            continue
        # Deterministic factor/sector floor (when supplied) keeps every holding
        # directional instead of falling back to a generic "no change" line.
        fb = fallback_map.get(ticker)
        if fb and str(fb.get("impact_summary") or "").strip():
            normalized.append(
                {
                    "ticker": ticker,
                    "macro_relevance": str(fb.get("macro_relevance") or "neutral")
                    .strip()
                    .lower()
                    or "neutral",
                    "impact_summary": str(fb.get("impact_summary")).strip(),
                }
            )
            continue
        normalized.append(
            {
                "ticker": ticker,
                "macro_relevance": "neutral",
                "impact_summary": f"No standout macro, sector, or company catalyst for {ticker} this morning; its own news flow is the thing to watch.",
            }
        )
    return normalized


def _fallback_macro_brief(
    overnight_articles: list[dict], positions: list[dict]
) -> dict:
    themes_found = set()
    for article in overnight_articles:
        for theme in article.get("themes", []):
            themes_found.add(theme)

    headlines = [
        a.get("title", "")[:100] for a in overnight_articles[:4] if a.get("title")
    ]

    fallback_brief = "Overnight macro developments were limited. Markets appear calm with no significant policy shifts or economic surprises."
    if themes_found:
        fallback_brief = (
            f"Overnight headlines pointed to {', '.join(_theme_label(theme) for theme in sorted(themes_found))}. "
            f"No major surprise changed the overall tone."
        )

    return {
        "overnight_macro": {
            "headlines": headlines or [],
            "themes": list(themes_found) if themes_found else [],
            "brief": fallback_brief,
        },
        "position_impacts": _normalize_position_impacts([], positions),
        "what_matters_today": [],
    }


def _normalize_macro_output(
    parsed: dict, fallback: dict, positions: list[dict]
) -> dict:
    raw_macro = parsed.get("overnight_macro") if isinstance(parsed, dict) else {}
    if not isinstance(raw_macro, dict):
        raw_macro = {}

    fallback_macro = fallback["overnight_macro"]
    raw_headlines = raw_macro.get("headlines")
    headlines = [
        str(item).strip()
        for item in (raw_headlines or fallback_macro.get("headlines") or [])
        if str(item).strip()
    ][:4]

    raw_themes = [
        str(theme).strip().lower()
        for theme in (raw_macro.get("themes") or [])
        if str(theme).strip().lower() in MACRO_THEMES
    ]
    fallback_detected = _detect_macro_themes(
        [{"title": headline, "summary": ""} for headline in headlines]
    )
    detected_themes: list[str] = []
    for item in fallback_detected:
        for theme in item.get("themes", []):
            if theme not in detected_themes:
                detected_themes.append(theme)
    themes = raw_themes or detected_themes or list(fallback_macro.get("themes") or [])

    brief = (
        str(raw_macro.get("brief") or "").strip()
        or fallback_macro.get("brief")
        or "No significant macro developments overnight."
    )
    if headlines and (
        "_" in brief
        or "limited" in brief.lower()
        or brief.lower().startswith("overnight macro developments centered on")
    ):
        headline_text = "; ".join(
            str(headline).strip()
            for headline in headlines[:3]
            if str(headline or "").strip()
        )
        theme_text = ", ".join(_theme_label(theme) for theme in themes[:3])
        if theme_text:
            brief = f"Overnight headlines centered on {headline_text}. The main themes were {theme_text}."
        else:
            brief = f"Overnight headlines centered on {headline_text}."

    parsed_impacts = parsed.get("position_impacts") if isinstance(parsed, dict) else []
    if not isinstance(parsed_impacts, list):
        parsed_impacts = []

    what_matters_today = (
        parsed.get("what_matters_today") if isinstance(parsed, dict) else []
    )
    if not isinstance(what_matters_today, list):
        what_matters_today = []

    fallback_impact_map = {
        _normalize_ticker(i.get("ticker")): i
        for i in (fallback.get("position_impacts") or [])
        if isinstance(i, dict) and _normalize_ticker(i.get("ticker"))
    }
    return {
        "overnight_macro": {
            "headlines": headlines,
            "themes": themes[:3],
            "brief": brief,
        },
        "position_impacts": _normalize_position_impacts(
            parsed_impacts, positions, fallback_impact_map
        ),
        "what_matters_today": what_matters_today,
    }


async def summarize_sector_overview(
    sector_articles_by_name: dict[str, list[dict]],
) -> dict:
    valid_sectors = {
        str(sector).strip().lower(): articles
        for sector, articles in (sector_articles_by_name or {}).items()
        if _is_valid_sector_name(sector) and articles
    }
    if not valid_sectors:
        return {"sector_overview": []}

    sector_blocks = []
    for sector, articles in sorted(valid_sectors.items()):
        lines = [f"Sector: {sector}"]
        for article in articles[:6]:
            title = str(article.get("title") or "").strip()
            summary = _strip_html(str(article.get("summary") or "").strip())
            if title:
                lines.append(f"- {title}: {summary[:180]}")
        sector_blocks.append("\n".join(lines))

    try:
        result = chatcompletion_text(
            messages=[
                {"role": "system", "content": SECTOR_SUMMARY_PROMPT},
                {"role": "user", "content": "\n\n".join(sector_blocks)},
            ],
            temperature=0.1,
            max_tokens=900,
        )
        parsed = extract_json_object(result, {})
    except Exception:
        parsed = {}
    raw_overview = parsed.get("sector_overview") or []
    if isinstance(raw_overview, list):
        normalized = []
        seen = set()
        for item in raw_overview:
            if not isinstance(item, dict):
                continue
            sector = str(item.get("sector") or "").strip().lower()
            if (
                sector in seen
                or sector not in valid_sectors
                or not _is_valid_sector_name(sector)
            ):
                continue
            seen.add(sector)
            normalized.append(
                {
                    "sector": sector,
                    "brief": str(item.get("brief") or "").strip()
                    or _fallback_sector_brief(sector, valid_sectors[sector])["brief"],
                    "headlines": [],
                }
            )
        if normalized:
            return {"sector_overview": normalized}

    return {
        "sector_overview": [
            _fallback_sector_brief(sector, articles)
            for sector, articles in sorted(valid_sectors.items())
        ]
    }


def _position_context_lines(
    positions: list[dict], sector_by_ticker: dict[str, dict] | None
) -> str:
    sector_by_ticker = sector_by_ticker or {}
    lines = []
    for p in positions:
        ticker = _normalize_ticker(p.get("ticker"))
        if not ticker:
            continue
        sec = sector_by_ticker.get(ticker) or {}
        sector_name = sec.get("sector") or p.get("sector") or "unknown"
        chg = _num(sec.get("etf_change_pct"))
        move = (
            f", sector {sector_name} {chg:+.1f}% today"
            if chg is not None
            else f", sector {sector_name}"
        )
        heads = [h for h in (sec.get("headlines") or []) if str(h or "").strip()]
        head_txt = f" | recent: {heads[0]}" if heads else ""
        lines.append(f"- {ticker}{move}{head_txt}")
    return "\n".join(lines)


async def classify_overnight_macro(
    overnight_articles: list[dict],
    positions: list[dict],
    sector_by_ticker: dict[str, dict] | None = None,
) -> dict:
    if not overnight_articles:
        return {
            "overnight_macro": {
                "headlines": [],
                "themes": [],
                "brief": "No overnight macro developments to report.",
            },
            "position_impacts": _normalize_position_impacts([], positions),
            "what_matters_today": [],
        }

    position_context = _position_context_lines(positions, sector_by_ticker)

    articles_text = "\n".join(
        f"- [{a.get('source', 'news')}] {a.get('title', '')}: {_strip_html(a.get('summary', ''))[:200]}"
        for a in overnight_articles[:10]
    )

    prompt = f"""Positions:
{position_context}

Overnight macro articles:
{articles_text}
"""

    try:
        result = chatcompletion_text(
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            temperature=0.1,
            max_tokens=1000,
        )
        parsed = extract_json_object(result, {})
    except Exception:
        parsed = {}
    fallback = _fallback_macro_brief(overnight_articles, positions)

    return _normalize_macro_output(parsed, fallback, positions)


# ---------------------------------------------------------------------------
# FRED factor-driven macro readout (+ top macro headlines for context)
# ---------------------------------------------------------------------------

FACTOR_SYSTEM_PROMPT = """You are writing the "Macro overnight" section of a morning brief for a retail investor who holds a specific set of stocks. You are given (a) last night's closing levels and day-over-day changes for the macro factors that move their book (S&P 500, 10-year Treasury yield, VIX, WTI crude, US dollar index, high-yield credit spread) and (b) a few top macro news headlines for higher-level context. You are also given their holdings and the sector each sits in.

Your job: say what is going on at a high level (lead with the biggest move or headline), then connect it to the stocks they own with a clear up or down direction. Plain English. No hedging boilerplate, no "investors should monitor", no restating numbers without a takeaway.

Return strict JSON:
{
  "overnight_macro": {
    "headlines": ["2-4 short factual lines: top macro headlines and/or one-factor moves like '10-year yield up 8 bps to 4.42%'"],
    "themes": ["up to 3 of: rate_policy, inflation, growth_recession, geopolitics, sector_specific, credit_market, currency, commodities"],
    "brief": "2-3 sentences. Lead with the single biggest overnight development (a headline or the largest factor move) and what it signals. Then say plainly which way it pushes the kinds of stocks in this portfolio. Use real direction words: lifts, pressures, supports, weighs on."
  },
  "position_impacts": [
    {"ticker": "XOM", "macro_relevance": "supports|contradicts|neutral", "impact_summary": "one sentence tying a specific factor or sector move to this stock with an up/down direction"}
  ],
  "what_matters_today": [
    {"catalyst": "a scheduled event today if implied by the headlines (CPI, Fed, OPEC, jobs)", "impacted_positions": ["XOM"], "urgency": "high|medium|low"}
  ]
}

How to reason about direction (apply, do not recite):
- WTI crude UP -> supports energy (e.g. XOM); crude DOWN -> pressures it.
- 10-year yield UP -> pressures long-duration / high-multiple tech (e.g. GOOG, AMD, SMCI); yield DOWN -> supports them.
- VIX spiking / risk-off -> pressures high-beta tech, supports defensives (e.g. JNJ).
- Stronger dollar (DXY up) -> mild headwind for large multinationals with overseas revenue.
- Wider high-yield credit spreads -> risk-off, pressures the most speculative names first.

Rules:
- Include EVERY holding in position_impacts exactly once, keyed to the factor or sector that most affects it.
- If a factor barely moved, mark affected holdings neutral and say there is no clear overnight read-through. Do not invent drama.
- If nothing meaningful moved and there are no notable headlines, return empty headlines and brief: "No major overnight macro moves to flag; rates, oil, and volatility were roughly flat."
- Quote the actual levels/changes you were given. Never echo the theme keys in the prose.
- No generic advice, no "consult a professional".
"""


def _num(value: object) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _fmt_signed(value: object, *, pct: bool = False, digits: int = 2) -> str:
    v = _num(value)
    if v is None:
        return "n/a"
    suffix = "%" if pct else ""
    return f"{v:+.{digits}f}{suffix}"


def _headline_text(item: object) -> str:
    if isinstance(item, dict):
        return str(item.get("title") or item.get("headline") or "").strip()
    return str(item or "").strip()


def _factor_table(snapshot: dict) -> str:
    s = snapshot or {}
    lines: list[str] = []
    if _num(s.get("spy_close")) is not None:
        lines.append(
            f"- S&P 500: {s.get('spy_close')} ({_fmt_signed(s.get('spy_day_change_pct'), pct=True)})"
        )
    if _num(s.get("ust10y_level")) is not None:
        lines.append(
            f"- 10Y Treasury yield: {s.get('ust10y_level')}% ({_fmt_signed(s.get('ust10y_day_change'))})"
        )
    if _num(s.get("vix_level")) is not None:
        lines.append(f"- VIX: {s.get('vix_level')} ({_fmt_signed(s.get('vix_day_change'))})")
    if _num(s.get("wti_level")) is not None:
        lines.append(
            f"- WTI crude: ${s.get('wti_level')}/bbl ({_fmt_signed(s.get('wti_day_change'))})"
        )
    if _num(s.get("dxy_level")) is not None:
        lines.append(
            f"- US dollar index (DXY): {s.get('dxy_level')} ({_fmt_signed(s.get('dxy_day_change'))})"
        )
    if _num(s.get("credit_spread_level")) is not None:
        lines.append(
            f"- High-yield credit spread: {s.get('credit_spread_level')}% (signal: {s.get('credit_signal') or 'n/a'})"
        )
    regime = str(s.get("regime_state") or "").strip()
    if regime:
        lines.append(f"- Regime: {regime}")
    return "\n".join(lines) or "- (macro factor levels unavailable)"


def _themes_from_snapshot(snapshot: dict) -> list[str]:
    s = snapshot or {}
    themes: list[str] = []
    if _num(s.get("ust10y_day_change")) not in (None, 0.0):
        themes.append("rate_policy")
    if _num(s.get("wti_day_change")) not in (None, 0.0):
        themes.append("commodities")
    if _num(s.get("dxy_day_change")) not in (None, 0.0):
        themes.append("currency")
    if str(s.get("credit_signal") or "").lower() in {"widening", "tightening"}:
        themes.append("credit_market")
    if _num(s.get("vix_day_change")) not in (None, 0.0):
        themes.append("growth_recession")
    return themes[:3]


def _impact_for_factor(
    ticker: str, sector: str, etf_chg: float | None, snapshot: dict
) -> tuple[str, str]:
    s = snapshot or {}
    sec = (sector or "").lower()
    is_energy = "energy" in sec or "oil" in sec
    is_tech = any(k in sec for k in ("tech", "semiconduct", "semis", "communication", "media"))
    is_defensive = any(k in sec for k in ("health", "pharma", "staple", "utilit"))

    # 1) A real sector ETF move is the most concrete signal.
    if etf_chg is not None and abs(etf_chg) >= 0.5:
        if etf_chg > 0:
            return (
                f"{(sector or 'The sector').title()} is up {abs(etf_chg):.1f}% today, a tailwind for {ticker}.",
                "supports",
            )
        return (
            f"{(sector or 'The sector').title()} is down {abs(etf_chg):.1f}% today, a headwind for {ticker}.",
            "contradicts",
        )

    # 2) Sector-specific macro factor.
    wti = _num(s.get("wti_day_change"))
    ust = _num(s.get("ust10y_day_change"))
    vix = _num(s.get("vix_day_change"))
    if is_energy and wti is not None and abs(wti) >= 0.01:
        if wti > 0:
            return (f"Crude firmed overnight, a modest tailwind for {ticker}.", "supports")
        return (f"Crude slipped overnight, mild downward pressure on {ticker}.", "contradicts")
    if is_tech and ust is not None and abs(ust) >= 0.03:
        if ust > 0:
            return (
                f"The 10-year yield rose overnight, a headwind for higher-multiple names like {ticker}.",
                "contradicts",
            )
        return (
            f"The 10-year yield eased overnight, a tailwind for rate-sensitive names like {ticker}.",
            "supports",
        )
    if is_defensive and vix is not None and vix >= 1.0:
        return (
            f"With volatility up overnight, defensive names like {ticker} are relatively favored.",
            "supports",
        )

    # 3) Nothing notable for this name.
    return (
        f"No standout overnight macro or sector read-through for {ticker}; its own news flow is the thing to watch.",
        "neutral",
    )


def _deterministic_factor_impacts(
    snapshot: dict, positions: list[dict], sector_by_ticker: dict[str, dict]
) -> dict[str, dict]:
    impacts: dict[str, dict] = {}
    for p in positions:
        ticker = _normalize_ticker(p.get("ticker"))
        if not ticker:
            continue
        sec = sector_by_ticker.get(ticker) or {}
        sector_name = sec.get("sector") or p.get("sector") or ""
        etf_chg = _num(sec.get("etf_change_pct"))
        summary, relevance = _impact_for_factor(ticker, sector_name, etf_chg, snapshot)
        impacts[ticker] = {
            "ticker": ticker,
            "macro_relevance": relevance,
            "impact_summary": summary,
        }
    return impacts


def _factor_brief(snapshot: dict, headlines: list[str]) -> str:
    s = snapshot or {}
    bits: list[str] = []
    spy = _num(s.get("spy_day_change_pct"))
    if spy is not None:
        if abs(spy) < 0.05:
            bits.append("the S&P was roughly flat")
        else:
            bits.append(f"the S&P {'rose' if spy > 0 else 'fell'} {abs(spy):.1f}%")
    ust = _num(s.get("ust10y_day_change"))
    if ust is not None and abs(ust) >= 0.02:
        bits.append(f"the 10-year yield {'rose' if ust > 0 else 'eased'} to {s.get('ust10y_level')}%")
    wti = _num(s.get("wti_day_change"))
    if wti is not None and abs(wti) >= 0.01:
        bits.append(f"crude {'firmed' if wti > 0 else 'slipped'}")
    factor_sentence = (
        "Overnight, " + ", ".join(bits) + "." if bits else "Markets were broadly quiet overnight."
    )
    lead = str(headlines[0]).strip() if headlines else ""
    if lead and lead[-1] not in ".?!":
        lead += "."
    return f"{lead} {factor_sentence}".strip() if lead else factor_sentence


def _fallback_factor_macro(
    snapshot: dict,
    headlines: list[str],
    positions: list[dict],
    sector_by_ticker: dict[str, dict],
) -> dict:
    heads = [h for h in (headlines or []) if str(h or "").strip()][:4]
    return {
        "overnight_macro": {
            "headlines": heads,
            "themes": _themes_from_snapshot(snapshot),
            "brief": _factor_brief(snapshot, heads),
        },
        "position_impacts": list(
            _deterministic_factor_impacts(snapshot, positions, sector_by_ticker).values()
        ),
        "what_matters_today": [],
    }


async def classify_overnight_macro_from_factors(
    snapshot: dict,
    headlines: list,
    positions: list[dict],
    sector_by_ticker: dict[str, dict] | None = None,
) -> dict:
    """Macro readout driven by FRED factor levels plus top macro headlines."""
    sector_by_ticker = sector_by_ticker or {}
    headline_texts = [t for t in (_headline_text(h) for h in (headlines or [])) if t][:6]

    holding_lines = []
    for p in positions:
        ticker = _normalize_ticker(p.get("ticker"))
        if not ticker:
            continue
        sec = sector_by_ticker.get(ticker) or {}
        sector_name = sec.get("sector") or p.get("sector") or "unknown"
        chg = _num(sec.get("etf_change_pct"))
        move = f", sector {sector_name} {chg:+.1f}% today" if chg is not None else f", sector {sector_name}"
        holding_lines.append(f"- {ticker}{move}")

    user_prompt = f"""Holdings:
{chr(10).join(holding_lines) or '- (no holdings)'}

Overnight macro factors (level, day change):
{_factor_table(snapshot)}

Top macro headlines:
{chr(10).join(f'- {h}' for h in headline_texts) or '- (no notable macro headlines overnight)'}
"""

    try:
        result = chatcompletion_text(
            messages=[
                {"role": "system", "content": FACTOR_SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.1,
            max_tokens=1000,
        )
        parsed = extract_json_object(result, {})
    except Exception:
        parsed = {}

    fallback = _fallback_factor_macro(snapshot, headline_texts, positions, sector_by_ticker)
    return _normalize_macro_output(parsed, fallback, positions)


# ---------------------------------------------------------------------------
# Owned-sector directional briefs (sector ETF move + holdings' news)
# ---------------------------------------------------------------------------

OWNED_SECTOR_PROMPT = """You write the "Your sectors" section of a retail investor's morning portfolio digest. The reader owns specific stocks and wants to know, for each sector they actually hold, which way it is pushing their stocks today and the one concrete reason.

You are given, per sector the user owns:
- sector name
- sector_etf_change_pct: the sector ETF's latest day change in percent (positive = sector up, negative = sector down, "no read" = unavailable)
- holdings: the user's tickers in that sector
- a few recent news notes for those holdings

Return strict JSON:
{
  "sector_overview": [
    {"sector": "technology", "brief": "...", "headlines": []}
  ]
}

Write each brief as 1-2 plain sentences that do three things in order:
1. State direction for the user's names in that sector: up, down, or flat, anchored to sector_etf_change_pct when present (e.g. "Energy is up about 0.8% today" or "Tech is soft, down ~1.1%").
2. Name the user's ticker(s) in that sector and connect the move to them ("which lifts XOM" / "a headwind for GOOG and AMD").
3. Give the single most concrete reason from the news notes (a specific catalyst, not a vague theme).

Hard rules:
- Only output sectors present in the input. Never invent a sector.
- Never write portfolio meta-commentary like "N holdings tied to this sector" or "exposure to this group". Tell them what is happening.
- Never paste a raw press headline or analyst-rating title as the brief. Synthesize.
- Always commit to a direction (up / down / flat) for the user's names. Avoid "mixed" unless the ETF read is genuinely flat and the notes conflict.
- If a sector has no real news and no ETF read, say plainly: "{Sector} is quiet today, no clear driver for {tickers}."
- No finance filler ("risk-adjusted", "broadly constructive", "remains well-positioned"). Calm, direct, concrete.
- headlines must be an empty array.
"""


def _fallback_owned_sector_brief(entry: dict) -> str:
    sector = str(entry.get("sector") or "this sector")
    chg = _num(entry.get("etf_change_pct"))
    tickers = [t for t in (entry.get("tickers") or []) if str(t or "").strip()]
    who = ", ".join(tickers) if tickers else "your holdings"
    if chg is None:
        return f"{sector.title()} is quiet today with no clear ETF read; watch {who} for company-specific news."
    if chg > 0.1:
        return f"{sector.title()} is up {abs(chg):.1f}% today, a tailwind for {who}."
    if chg < -0.1:
        return f"{sector.title()} is down {abs(chg):.1f}% today, a headwind for {who}."
    return f"{sector.title()} is roughly flat today; no real push on {who} from the sector."


async def summarize_owned_sectors(sector_inputs: list[dict]) -> dict:
    """Directional per-owned-sector briefs.

    sector_inputs: [{sector, etf_change_pct, tickers, articles:[{title,summary}]}]
    """
    valid = [
        s
        for s in (sector_inputs or [])
        if _is_valid_sector_name(s.get("sector"))
        and (s.get("articles") or s.get("etf_change_pct") is not None or s.get("tickers"))
    ]
    if not valid:
        return {"sector_overview": []}

    blocks = []
    for s in valid:
        sector = str(s.get("sector"))
        chg = _num(s.get("etf_change_pct"))
        chg_txt = f"{chg:+.2f}%" if chg is not None else "no read"
        tickers = ", ".join(t for t in (s.get("tickers") or []) if str(t or "").strip())
        lines = [
            f"Sector: {sector}",
            f"sector_etf_change_pct: {chg_txt}",
            f"holdings: {tickers or 'none'}",
        ]
        for a in (s.get("articles") or [])[:5]:
            title = str(a.get("title") or "").strip()
            summary = _strip_html(str(a.get("summary") or ""))[:160]
            if title:
                lines.append(f"- {title}: {summary}")
        blocks.append("\n".join(lines))

    try:
        result = chatcompletion_text(
            messages=[
                {"role": "system", "content": OWNED_SECTOR_PROMPT},
                {"role": "user", "content": "\n\n".join(blocks)},
            ],
            temperature=0.1,
            max_tokens=900,
        )
        parsed = extract_json_object(result, {})
    except Exception:
        parsed = {}

    by_name = {str(s.get("sector")).strip().lower(): s for s in valid}
    out: list[dict] = []
    seen: set[str] = set()
    raw = parsed.get("sector_overview") if isinstance(parsed, dict) else []
    if isinstance(raw, list):
        for item in raw:
            if not isinstance(item, dict):
                continue
            sector = str(item.get("sector") or "").strip().lower()
            if sector in seen or sector not in by_name:
                continue
            brief = str(item.get("brief") or "").strip()
            if not brief:
                continue
            seen.add(sector)
            out.append({"sector": sector, "brief": brief, "headlines": []})

    # Guarantee every owned sector gets a directional line.
    for sector, entry in by_name.items():
        if sector in seen:
            continue
        out.append(
            {"sector": sector, "brief": _fallback_owned_sector_brief(entry), "headlines": []}
        )

    order = {str(s.get("sector")).strip().lower(): i for i, s in enumerate(valid)}
    out.sort(key=lambda x: order.get(x["sector"], 99))
    return {"sector_overview": out}


def filter_macro_articles(articles: list[dict]) -> list[dict]:
    return [
        a
        for a in articles
        if a.get("relevance", {}).get("event_type") in ["macro", "sector", "theme"]
    ]
