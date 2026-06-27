# Clavix Morning Digest — LLM/Data Quality Audit & Remediation Plan
Date: 2026-06-27 | ICP: holder of GOOG / AMD / JNJ / SMCI / XOM

> VERIFICATION NOTE (added after the multi-agent audit, by spot-checking the live code):
> - VERIFIED TRUE: USE_TICKERTICK default=true (news_enrichment.py:15) with no .env override;
>   macro_articles forced [] in prod (scheduler.py:1424, :2188); "Macro analysis unavailable."
>   placeholder behind a dead `if macro_articles:` gate (scheduler.py:2581-2586);
>   macro_classifier.py:182 "say there is no clear overnight macro change" give-up line;
>   sector fallback "{N} holding(s) tied to this sector. {headline}" (portfolio_compiler.py:257);
>   event_analyses + earnings_calendar populated daily but unused by the compiler; SOXX missing
>   from sector_snapshot.SECTOR_ETFS.
> - VERIFIED FALSE (do NOT act on): the "#CRASH fallback_what_matters NameError" row below is a
>   false positive. `fallback_what_matters` IS defined at portfolio_compiler.py:606 before its
>   uses at :677/:706/:884/:906. There is no NameError. The row is struck through in the table.

All diagnoses are accurate against the live code. Here is the synthesized plan.

---

# Clavix Morning Digest: LLM/Data Quality Remediation Plan

**Author:** Lead engineer synthesis | **Date:** 2026-06-27 | **Target:** ICP holding GOOG / AMD / JNJ / SMCI / XOM

---

## 1. Executive Summary: Three Systemic Root Causes

Every weak output in the morning digest traces back to the **same three structural failures**, repeated across five sections. This is not five unrelated bugs; it is one architecture problem wearing five masks.

### Root cause A — The 2026-06-26 compliance migration severed the data feeds but never replaced them
The Tickertick/licensing migration set `USE_TICKERTICK=true` (default, `news_enrichment.py:15`) and **hard-coded the macro and sector inputs to empty (`[]`/`{}`) in every production branch** (`scheduler.py:1424`, `:2188`, `:2191`; `routes/digest.py:330`). The classifiers themselves are built and correct, but they are starved of input. Meanwhile **three compliant data sources already populated daily go completely unused**:
- `macro_regime_snapshots` (FRED-backed: VIX, UST10Y, DXY, WTI, SPY, HY spread + day-changes) — public domain, written by `macro_snapshot.py`.
- `sector_regime_snapshots` (per-ETF day-change %) — written daily, read by the heatmap but not the prose.
- `event_analyses` (`what_happened` / `what_it_means` / `risk_direction`) — the exact raw material for real alerts, thrown away.
- `earnings_calendar` (dated catalysts) — read by `today.py` chips, never wired to the digest compiler.

### Root cause B — Fallback strings masquerade as analysis
When the starved LLM returns nothing, the code emits **hard-coded Python f-strings that pretend to be insight**: `"Macro analysis unavailable."` (`scheduler.py:2581`), `"No clear overnight macro change for this holding…"` (`portfolio_compiler.py:320`), `"{N} holding(s) tied to this sector. {company headline}"` (`portfolio_compiler.py:257`), `"No immediate portfolio-level risk driver found today…"` (`portfolio_compiler.py:526`). Several of these **recycle the wrong data**: forward-looking risk drivers (`watch_items[0]`, `top_risks[0]`) get laundered into the watchlist-alerts and what-to-watch slots, so "things that *could* happen" appear as if they happened.

### Root cause C — The prompts lack the inputs they need, and several actively instruct the model to give up
The shared compiler prompt (`portfolio_compiler.py:9-90`) and the macro classifier prompt (`macro_classifier.py:146-183`) are told to "be specific: earnings, data releases" but are **never given an earnings date, a sector move, or a per-event narrative**. Worse, `macro_classifier.py:182` *explicitly instructs* the model: "If macro read-through is weak for a holding, mark it neutral and say there is no clear overnight macro change" — the model is commanded to produce the exact dead-end output the ICP hates. The position-impact generator (`classify_overnight_macro`) is also physically blind to `sector_context`, which is computed but never passed to it.

**The fix pattern is identical for all five sections:** (1) wire the already-populated compliant data into the generator, (2) rewrite the prompt to demand a direction (up/down) and forbid the give-up line, (3) replace the deterministic fallback so it is still directional and never recycles a risk driver or company headline.

**Do NOT** "fix" this by setting `USE_TICKERTICK=false` — that re-enables the non-compliant CNBC/Google feeds the team deliberately removed. Source from FRED/`sector_regime_snapshots`/`event_analyses`/`earnings_calendar` instead.

---

## 2. Master Fix Table

Priority key: **P0** = ship first (max ICP impact / unblocks others / latent crash), **P1** = high, **P2** = polish/defense-in-depth. Effort: S = <0.5d, M = 0.5–1.5d.

| # | Area | What | File:line | Gap type | Pri | Eff |
|---|------|------|-----------|----------|-----|-----|
| ~~CRASH~~ | ~~What to Watch~~ | ~~fallback_what_matters NameError~~ — **FALSE POSITIVE, discarded.** `fallback_what_matters` is defined at `portfolio_compiler.py:606`; no crash. | — | — | ~~P0~~ | — |
| 1 | Macro overnight | Stop the harsh `"Macro analysis unavailable."` placeholder; always call the classifier (use its clean empty-list branch) | `scheduler.py:2586` (+ initializer `:2577-2585`); same gate `routes/digest.py:311-319` | prompt/code | **P0** | S |
| 2 | Macro overnight | Wire real macro readout from FRED `macro_regime_snapshots`: new `classify_overnight_macro_from_factors(snapshot, positions)` + `FACTOR_SYSTEM_PROMPT` | `macro_classifier.py` (new fn+prompt); call from `scheduler.py:2585-2591`, `routes/digest.py:311-319` | data | **P0** | M |
| 3 | Macro overnight | Factor→ticker deterministic mapping so every holding gets a directional line (WTI→XOM, UST10Y→tech, VIX/risk-off→JNJ, DXY→GOOG/XOM, HY spread→SMCI) | `macro_classifier.py` (feed into `_normalize_position_impacts`) | data | P1 | M |
| 4 | Macro overnight | Staleness guard: require `as_of_date` within ~3 days and `data_status='real_factors'`, else clean empty-state brief | `macro_classifier.py` (new builder) | data | P1 | S |
| 5 | Your sectors | Build compliant per-sector context from `sector_regime_snapshots` (ETF direction) + `shared_ticker_events` (the why); call where `sector_context` is zeroed | `scheduler.py:1415-1427, :2179-2191`; `routes/digest.py:321-357`; helper near `portfolio.py:52` | data | **P0** | M |
| 6 | Your sectors | Rewrite `SECTOR_SUMMARY_PROMPT` + user block to per-owned-sector, directional, dot-connecting briefs | `macro_classifier.py:186-205, :361-425` | prompt | **P0** | S |
| 7 | Your sectors | Replace `_fallback_sector_overview` so fallback is per-sector + directional, never a raw company headline; drop `"{N} holding(s) tied…"` | `portfolio_compiler.py:214-261` (brief at `:251-257`) | prompt/fallback | P1 | M |
| 8 | Your sectors | Render ALL owned sectors' briefs in iOS, not just `.first` (move per-sector list out of `else if`) | `MorningReportView.swift:119-183` (esp. `:122`, `:144-175`) | UI | P1 | S |
| 9 | Your sectors | Pass owned-sector ETF direction into the main compiler LLM prompt (`_sector_overview_text`) | `portfolio_compiler.py:425-440`, `:799` | prompt | P2 | S |
| 10 | Sector heatmap | Add `("Semiconductors","SOXX")` to writer's `SECTOR_ETFS` (fixes grey SOXX, ~47% of book) | `sector_snapshot.py:29-43` | data | **P0** | S |
| 11 | Sector heatmap | Replace bare `"—"` tile fallback with a sector-derived label (route through `SectorRow` or `s.sector`) | `MorningReportView.swift:135, :140-150` | data/UI | **P0** | S |
| 12 | Sector heatmap | Surface backend `display_name` (sector name) + render it instead of raw ETF ticker | `portfolio.py:126-139` + `ScoreHistory.swift:106-120` + both renderers | data/UI | P1 | M |
| 13 | Sector heatmap | De-dupe the two drifted `SECTOR_ETF_MAP` copies into one shared constant | `today.py:38-53` + `portfolio.py:19-40` → new `sector_constants.py` | data | P1 | M |
| 14 | Sector heatmap | Make nil-changePct color visually distinct from "flat" (hatch / "no data" caption) | `SectorHeatmapView.swift:172-183` | UI | P2 | S |
| 15 | Position changes | Wire `sector_context` + per-stock signals (sector move, company headlines, score/grade delta) into `classify_overnight_macro` | `macro_classifier.py:428-474`; `scheduler.py:2577-2593, ~3502-3507` | data | **P0** | M |
| 16 | Position changes | Rewrite macro/position-impact `SYSTEM_PROMPT`; **delete line 182** ("say there is no clear overnight macro change") | `macro_classifier.py:146-183` | prompt | **P0** | S |
| 17 | Position changes | Gate the no-change fallback to fire only on zero macro+sector+company signal; synthesize sector-anchored line otherwise; unify the two copies | `portfolio_compiler.py:316-329` + `macro_classifier.py:249-255` | prompt/fallback | P1 | M |
| 18 | Position changes | Stop stapling raw `watchItems.first` noun-phrase onto `impactSummary`; render as "What to watch:" line or drop | `MorningReportView.swift:225-250` | UI | P1 | S |
| 19 | Position changes | Make compiler's richer `position_impacts` win over empty macro impacts in merge | `portfolio_compiler.py:264-330` (precedence `:271-292`) | code | P2 | S |
| 20 | Watchlist alerts | New `build_event_watchlist_alerts(supabase, tickers, days=5, limit=6)` sourcing `event_analyses` (`what_happened`+`risk_direction`+`what_it_means`) | `personalisation.py` (near `:205`) | data | **P0** | M |
| 21 | Watchlist alerts | Wire event-driven alerts into PRODUCTION scheduler path (currently passes no `watchlist_alerts`) | `scheduler.py:3502-3516` | data | **P0** | S |
| 22 | Watchlist alerts | Replace title-only on-demand builder with the new event-driven one | `routes/digest.py:48-82, :359-383` | data | **P0** | S |
| 23 | Watchlist alerts | Delete the `watch_items`/`top_risks` fallback that turns risk drivers into alerts; prefer passed-in alerts over LLM-invented | `portfolio_compiler.py:633-646, :867-869` | fallback | **P0** | S |
| 24 | Watchlist alerts | Feed per-event evidence into compiler prompt + rewrite Watchlist Alerts instruction (event + direction, no hypotheticals) | `portfolio_compiler.py:46-48, :65, :74, :817-818` | prompt | P1 | S |
| 25 | Watchlist alerts | Add direction tag to the stored alert message (defense-in-depth) | `scheduler.py:2977-3004` (line `:2983`) | data | P2 | S |
| 26 | What to Watch | Wire `earnings_calendar` rows into `compile_portfolio_digest` via new `services/earnings_calendar.fetch_upcoming(supabase, tickers)` (reuse `today.py:236-249` query) | `portfolio_compiler.py:722-733`; `scheduler.py:3501-3540, 1709-1740`; `compiler.py`; `today.py:236-249` | data | **P0** | M |
| 27 | What to Watch | Rewrite `_fallback_what_matters_today` to cite the earnings date and **drop the filler tail** (`:527`) | `portfolio_compiler.py:507-532` | prompt/fallback | **P0** | M |
| 28 | What to Watch | Inject EARNINGS CALENDAR block into LLM prompt + tighten specificity instructions (`SYSTEM_PROMPT:72-73`, user `:815-816`) | `portfolio_compiler.py:9-90, :795-832` | prompt | P1 | M |
| 29 | What to Watch | Optional: suppress the digest catalyst line when an `EARN` chip already shows the same ticker date | `today.py:251-284`; `DigestView.swift:452-495` | UI | P2 | S |

---

## 3. Proposed Prompt Rewrites (full text)

### 3.1 NEW: `FACTOR_SYSTEM_PROMPT` — macro readout driven by FRED factors (fix #2)
Add to `macro_classifier.py`. Used by `classify_overnight_macro_from_factors(snapshot, positions)`.

```
You are writing the "Macro overnight" line of a morning brief for a retail investor who holds a specific set of stocks. You are given last night's closing levels and day-over-day changes for the macro factors that actually move their book: the S&P 500, the 10-year Treasury yield, the VIX, WTI crude oil, the US dollar index, and high-yield credit spreads. You are also given their holdings.

Your job: say what moved overnight, in plain English, and connect each move to the stocks they own with a clear up or down direction. No hedging boilerplate, no "investors should monitor", no restating the numbers without a takeaway.

Return strict JSON:
{
  "overnight_macro": {
    "headlines": ["2-3 short factual lines, each one factor move, e.g. '10-year yield up 8 bps to 4.42%'"],
    "themes": ["up to 3 from: rate_policy, inflation, growth_recession, geopolitics, sector_specific, credit_market, currency, commodities"],
    "brief": "2-3 sentences. Lead with the single biggest overnight move and what it signals. Then say plainly which way it pushes the kinds of stocks in this portfolio. Use real direction words: lifts, pressures, supports, weighs on."
  },
  "position_impacts": [
    {"ticker": "XOM", "macro_relevance": "supports|contradicts|neutral", "impact_summary": "one sentence tying a specific factor move to this stock with an up/down direction"}
  ],
  "what_matters_today": [
    {"catalyst": "a scheduled event today if implied (CPI, Fed, OPEC, jobs)", "impacted_positions": ["XOM"], "urgency": "high|medium|low"}
  ]
}

How to reason about direction (apply, do not recite):
- WTI crude UP -> supports energy (XOM); crude DOWN -> pressures XOM.
- 10-year yield UP -> pressures long-duration / high-multiple tech (GOOG, AMD, SMCI); yield DOWN -> supports them. Higher yields are a mild support for defensive cash-flow names only via rotation, not fundamentals.
- VIX spiking / risk-off -> pressures high-beta tech (AMD, SMCI), supports defensives (JNJ).
- Stronger dollar (DXY up) -> mild headwind for large multinationals with overseas revenue (GOOG, XOM).
- Wider high-yield credit spreads -> risk-off signal, pressures the most speculative names (SMCI) first.

Rules:
- Include EVERY holding in position_impacts exactly once.
- If a factor barely moved (small day change), mark affected holdings neutral and say there is no clear overnight read-through. Do not invent drama.
- If nothing meaningful moved overnight, return empty headlines and brief: "No major overnight macro moves to flag; rates, oil, and volatility were roughly flat."
- Be specific and factual. Quote the actual levels/changes you were given. Never echo the theme keys (rate_policy etc.) in the prose.
- No generic advice, no "consult a professional", no "time will tell".
```

User prompt the builder assembles (column names confirmed against `macro_snapshot.py:113-129`: `regime_state, vix_level, vix_day_change, ust10y_level, ust10y_day_change, dxy_level, dxy_day_change, wti_level, wti_day_change, spy_close, spy_day_change_pct, credit_spread_level, rates_signal, credit_signal`):

```
Holdings:
- GOOG: large-cap tech
- AMD: high-beta semiconductor
- JNJ: defensive healthcare
- SMCI: speculative AI-hardware small/mid cap
- XOM: integrated energy

Overnight macro factors (level, day change):
- S&P 500: 5,431 (-0.6%)
- 10Y Treasury yield: 4.42% (+0.08)
- VIX: 17.8 (+1.9)
- WTI crude: $81.40/bbl (+2.3%)
- US dollar index (DXY): 105.6 (+0.4)
- High-yield credit spread: 3.21% (+0.06)
- Regime: neutral
```

### 3.2 REPLACE: `SECTOR_SUMMARY_PROMPT` (fix #6) — `macro_classifier.py:186-205`

```
You write the "Your sectors" section of a retail investor's morning portfolio digest. The reader owns specific stocks and wants to know, for each sector they actually hold, which way it is pushing their stocks today and the one concrete reason.

You are given, per sector the user owns:
- sector name
- sector_etf_change_pct: the sector ETF's latest day change in percent (positive = sector up, negative = sector down, null = no read)
- holdings: a list of the user's tickers in that sector, each with a short news note (what happened) and a sentiment (-1 negative to +1 positive)

Return strict JSON:
{
  "sector_overview": [
    {"sector": "technology", "brief": "...", "headlines": []}
  ]
}

Write each brief as 1-2 plain sentences that do three things in order:
1. State direction for the user's names in that sector: up, down, or flat, anchored to sector_etf_change_pct when present (e.g. "Energy is up about 0.8% today" or "Tech is soft, down ~1.1%").
2. Name the user's ticker(s) in that sector and connect the move to them ("which lifts XOM" / "a headwind for GOOG and AMD").
3. Give the single most concrete reason from the holdings' news notes (a specific catalyst, not a vague theme).

Hard rules:
- Only output sectors present in the input. Never invent a sector.
- Never write portfolio meta-commentary like "N holdings tied to this sector" or "exposure to this group". The reader knows what they own; tell them what is happening.
- Never paste a raw press headline or analyst-rating title as the brief. Synthesize across the holdings.
- Always commit to a direction (up / down / flat) for the user's names. Do not hedge with "mixed" unless the ETF read is genuinely flat and the news notes conflict, in which case say so in one clause.
- If a sector has no real news and no ETF read, say plainly: "{Sector} is quiet today, no driver for {tickers}."
- No finance filler ("risk-adjusted", "broadly constructive", "remains well-positioned"). Calm, direct, concrete.
- headlines must be an empty array.
```

### 3.3 REPLACE: macro/position-impact `SYSTEM_PROMPT` (fix #16) — `macro_classifier.py:146-183`, **deleting line 182**

```
You are writing the per-holding 'what is moving my stock today' lines for a retail investor's morning portfolio briefing. The investor owns these stocks and wants you to connect the dots: macro -> sector -> their specific stock, and tell them which way the pressure points.

Return strict JSON:
{
  "overnight_macro": {
    "headlines": ["2-4 key overnight headlines"],
    "themes": ["up to 3 of: rate_policy, inflation, growth_recession, geopolitics, sector_specific, credit_market, currency, commodities"],
    "brief": "2-3 plain sentences: what happened overnight and what it means for markets"
  },
  "position_impacts": [
    {"ticker": "AMD", "macro_relevance": "supports | contradicts | neutral", "impact_summary": "Exactly 2 sentences, see rules below."}
  ],
  "what_matters_today": [
    {"catalyst": "scheduled event today (earnings, data, Fed speaker)", "impacted_positions": ["AMD"], "urgency": "high | medium | low"}
  ]
}

For EACH holding you are given: its sector, today's sector move/brief, its top company headlines, its price/score change and any grade change, and the relevant macro themes. Use them.

How to write impact_summary (exactly 2 sentences, plain English, no jargon, no hedging):
1) Sentence 1 names the DOMINANT force acting on THIS stock today and its DIRECTION for the investor who owns it: upward pressure, downward pressure, or mixed/flat. Be specific to the ticker, never generic.
2) Sentence 2 connects the chain. If macro is the driver, link macro -> the stock. If macro is quiet but the sector or the company news is moving, SAY THAT EXPLICITLY and pivot, e.g. "Macro is quiet, but semis are selling off overnight, which adds downward pressure on AMD." or "The broad market is calm; the mover here is XOM's own news flow as oil firms up, a modest tailwind."

Hard rules:
- ALWAYS pick the strongest available signal in this order: company-specific news > sector move > macro theme. Only call something neutral if NONE of macro, sector, or company news is doing anything to this name.
- NEVER output a generic 'no clear macro change, focus on company-specific developments' line. If macro is weak, you have sector and company data; use it.
- State direction in every line (upward / downward / mixed / flat pressure). The investor needs to know which way it cuts for them.
- macro_relevance is judged from the investor's seat (they are long the stock): supports = today's backdrop helps the stock, contradicts = it hurts, neutral = no net read-through from ANY of macro/sector/company.
- Tie sector moves to sector peers the investor owns when relevant (e.g. AMD and SMCI both ride semis).
- No bloat, no market-commentary filler, no theme keywords echoed verbatim. Two tight sentences per holding.
- Include every holding provided exactly once.
```

### 3.4 REPLACE: Watchlist Alerts schema + section rules (fix #24) — `portfolio_compiler.py:46-48, :65, :74, :817-818`

Schema block (`:46-48`):
```
  "watchlist_alerts": [
    "TICKER — <what actually happened, dated> -> Upward|Downward|Neutral pressure: <why it matters to this holder in one clause>"
  ]
```

Replace the two structure rules at `:65` and `:74`:
```
- Then a section titled: **Watchlist Alerts** — only include a ticker here if a REAL, RECENT event occurred (earnings, guidance, an upgrade/downgrade, a filing, a regulatory action, a contract, an outage). Each line must name the event that HAPPENED, not a risk to watch for.
- **Watchlist Alerts** rules: (1) State the concrete event in plain past tense ("beat Q3 estimates", "issued a subpoena", "filed its 10-K"), with the date if known. (2) Give an explicit direction: "Upward pressure", "Downward pressure", or "Neutral/mixed read". (3) Add one short clause on why it matters to someone holding the stock. (4) NEVER write a hypothetical ("if X happens", "potential", "risk of", "could face", "may see") — those belong in monitoring notes, not alerts. (5) If a ticker has no recent event, either omit it or write "TICKER — No new events. No change." (6) Use ONLY the events supplied in the "Watchlist Alerts:" evidence block below; do not invent events from general market knowledge.
```

Replace user-prompt instruction (`:817-818`):
```
- "watchlist_alerts": copy the supplied event lines (in the "Watchlist Alerts:" evidence block) into sections.watchlist_alerts, lightly cleaned. Each must read as "TICKER — <event that happened> -> Upward|Downward|Neutral pressure: <why>". Do NOT add tickers that have no supplied event. Do NOT turn a risk driver, a 'what would change the rating', or a 'thing to watch' into an alert — if it did not already happen, it is not an alert.
```

Add to `position_report_builder.py` `SYSTEM_PROMPT` writing rules (so its `watch_items` can never be mistaken for events):
```
4. Close with what would change the rating. These watch_items are forward-looking risk drivers for THIS rating only and must never be presented as events that occurred.
```

### 3.5 REPLACE: What Matters Today specificity rules (fix #28) — `portfolio_compiler.py:72-73, :815-816`

`SYSTEM_PROMPT:72-73`:
```
- **What Matters Today** must be a concrete, dated, directional catalyst the investor can act on. When an upcoming earnings date is provided in the EARNINGS CALENDAR input, cite it exactly: "SMCI reports earnings Jul 30 after the close." State which way it could push the stock (up if it beats, down if it misses) only when there is a real reason; otherwise just name the event and date.
- If, and ONLY if, no dated catalyst exists for any holding, emit one short low-urgency item that names the single holding worth watching and what to watch for, in one sentence. Do NOT append generic tails like "keep the rest of the book on watch for earnings, filings, or macro shocks." Never pad. If nothing is happening, the shortest honest sentence wins.
```

Add to the user prompt, inserted right before `{what_matters_info}` (~`:802`):
```
EARNINGS CALENDAR (next 14 days, held tickers only — cite these dates verbatim when relevant; if empty, no earnings are scheduled):
{earnings_calendar_info}
```
where `{earnings_calendar_info}` is one line per row, e.g. `- SMCI: Jul 30 (after close), est EPS 0.62`, or the literal `- none scheduled in the next 14 days` when there are no rows.

User-prompt instruction (`:815-816`):
```
- Use "what_matters_today" for forward-looking, dated catalysts. When the EARNINGS CALENDAR lists a holding, cite the exact date (e.g. "AMD reports earnings Aug 5 after close"). Do not write "earnings" without a date when a date is available.
- If no holding has a dated catalyst, return exactly ONE low-urgency item naming the single most relevant holding and what to watch — one sentence, no trailing "monitor the rest of the book" boilerplate, no filler.
```

---

## 4. Recommended Execution Order (max ICP impact first)

Sequenced so each step ships something the ICP sees, and shared dependencies land before their dependents.

### Phase 0 — Stop the bleeding (half a day, S effort, no new data)
These remove the most obviously-broken-looking outputs immediately and fix a latent crash.
1. **Fix #CRASH** (`portfolio_compiler.py:884,906`) — the `fallback_what_matters` NameError sits on the *exact* no-urgent-driver path the ICP hits. This can hard-fail digest compilation. **Do this first, it is a live crash.**
2. **Fix #1** — remove `"Macro analysis unavailable."`, always call the classifier (one-line guard change at `scheduler.py:2586` + initializer). Even before real data lands, the empty-list branch returns a calm `"No overnight macro developments to report."`
3. **Fix #10** — add `("Semiconductors","SOXX")` to `SECTOR_ETFS`. One line; the next snapshot refresh colors the ICP's single largest tile (~47% of book, AMD+SMCI). Highest visual impact per character changed.
4. **Fix #11** — kill the bare `"—"` tile in `MorningReportView.swift`.

### Phase 1 — Wire the compliant data (the core fix, 2–3 days)
This is where the digest stops being boilerplate. Build the four data feeds (Section 5) and the generators that consume them.
5. **Fixes #2, #4** — FRED factor-driven macro readout + staleness guard. Macro overnight goes from blank to a real rates/oil/VIX read.
6. **Fixes #5, #6, #7** — sector context from `sector_regime_snapshots` + `shared_ticker_events`, new sector prompt, directional fallback. "Your sectors" starts naming direction.
7. **Fixes #20, #21, #22, #23** — event-driven watchlist alerts from `event_analyses`, wired into BOTH paths, fallback deleted. Alerts become real dated events with up/down.
8. **Fixes #26, #27** — earnings calendar wired into the compiler + dated fallback. "What to Watch" cites real dates.

### Phase 2 — Connect the dots per stock (1–2 days)
9. **Fixes #15, #16** — pass `sector_context` + per-stock signals into `classify_overnight_macro`, rewrite its prompt, **delete the give-up line (`macro_classifier.py:182`)**. This is the single highest-leverage prompt change: it is what makes "Position changes" stop being five identical form-letters. Depends on #5 (sector context must exist first).
10. **Fix #3** — deterministic factor→ticker mapping as a floor so every holding always gets a directional line.
11. **Fixes #17, #19** — fallback gating + merge precedence so the richer output wins.

### Phase 3 — iOS rendering + polish (1 day)
12. **Fixes #8, #18** — render all sector briefs (not just `.first`), stop stapling watch-item fragments onto sentences.
13. **Fixes #12, #13** — `display_name` (sector names not ETF codes), de-dupe the two `SECTOR_ETF_MAP` copies into `sector_constants.py`.
14. **Fixes #9, #14, #24, #25, #28, #29** — remaining P1/P2 prompt tightening, heatmap nil-color, defense-in-depth.

**Rationale:** Phase 0 makes the app stop looking broken in under a day. Phase 1 is the substance: it converts four dead sections to live data. Phase 2's position-impact fix is gated on Phase 1's sector context existing, so it must come after. iOS work is last because backend correctness is the prerequisite for it to show anything.

---

## 5. Data / Feed Wiring Required

No new external feed or license is needed. All four sources are **already populated daily** by existing jobs. The work is plumbing them from where they are written to where the digest is built.

### 5.1 Macro factors — `macro_regime_snapshots` (FRED, public domain)
- **Source of truth:** written daily by `macro_snapshot.py:84 refresh_macro_snapshot()`. Columns confirmed at `macro_snapshot.py:113-129`.
- **Plug-in points:** new `classify_overnight_macro_from_factors(snapshot, positions)` in `macro_classifier.py`. Read the latest row (reuse the `_latest_date` pattern from `composite_recompute.py:229`), guard on `as_of_date` within ~3 days and `data_status='real_factors'` (note: a `price_only` fallback row exists, `macro_snapshot.py:176-201` — treat that as thin, prefer empty-state over presenting it as a full macro read). Call from `scheduler.py:2585-2591` when `macro_articles` is empty, and from `routes/digest.py:311-319`.
- **Do NOT** revert `USE_TICKERTICK` to re-enable CNBC RSS (`fetch_cnbc_macro_rss`, still wired at `scheduler.py:2198` / `routes/digest.py:316` but only reachable on the dead legacy branch). It is non-compliant; leave it gated off.

### 5.2 Sector direction — `sector_regime_snapshots` (per-ETF day-change)
- **Source of truth:** written daily by `sector_snapshot.py:93 refresh_sector_snapshots()` iterating `SECTOR_ETFS` (`:29-43`). **Currently missing SOXX** → fix #10 adds it. The same map's reader (`portfolio.py:122-124 SECTOR_ETF_MAP`) already expects `SOXX`, which is the exact drift that greys the chip.
- **Plug-in points:** new `build_sector_context_from_holdings(positions, supabase)` near `portfolio.py:52` (reuse `_sector_snapshot_map`). Reads `etf_day_change_pct` per owned sector + `tldr`/`what_it_means`/`sentiment_score` from `shared_ticker_events`. Call where `sector_context` is zeroed: `scheduler.py:1415-1427`, `:2179-2191`, `routes/digest.py:321-357` (replace the `not USE_TICKERTICK` gate at `:330`). Feed into `summarize_sector_overview` input and pass through to `compile_portfolio_digest`.
- **Consolidate** the two drifted `SECTOR_ETF_MAP` copies (`today.py:38-53` lacks SOXX + media→XLC; `portfolio.py:19-40` is the live richer one) into one `backend/app/pipeline/sector_constants.py`, imported by `portfolio.py`, `today.py`, AND `sector_snapshot.py` so the writer's ETF universe and reader's map can never diverge again (fix #13).

### 5.3 Events — `event_analyses` (`what_happened` / `what_it_means` / `risk_direction`)
- **Source of truth:** rows produced and normalized at `scheduler.py:2969-2973` and `analysis_utils.py:861-898`. `risk_direction ∈ {improving, worsening, neutral}`.
- **Plug-in points:** new `build_event_watchlist_alerts(supabase, tickers, *, days=5, limit=6)` in `personalisation.py` near `:205` (beside `recent_event_ids_for_tickers`). Map `risk_direction` → "Upward pressure" / "Downward pressure" / "Mixed/neutral read". This becomes the single source for BOTH digest paths: `scheduler.py:3502-3516` (production, currently passes NO `watchlist_alerts`) and `routes/digest.py:359-383` (replaces `_build_watchlist_alerts` at `:48-82`). Held tickers for the scheduled digest; union the watchlist via `get_default_watchlist_detail` where a distinct watchlist exists (as `routes/digest.py:361` already does).

### 5.4 Earnings dates — `earnings_calendar` (Finnhub, dated catalysts)
- **Source of truth:** populated daily by `jobs/earnings_calendar.py`; already queried by `today.py:236-249` to build `EARN` chips. Columns: `ticker, report_date, time_of_day, est_eps, est_revenue`.
- **Plug-in points:** factor the `today.py:236-249` query into `backend/app/services/earnings_calendar.py:fetch_upcoming(supabase, tickers)` (one source of truth). Add `earnings_calendar: list[dict] | None = None` param to `compile_portfolio_digest` (`portfolio_compiler.py:722-733`); pass from all three call sites (`scheduler.py:3501-3540`, `scheduler.py:1709-1740`, `compiler.py`). Use it in `_fallback_what_matters_today` (`:507-532`) and inject the `{earnings_calendar_info}` block into the LLM user prompt (~`:802`).

---

## Key cross-cutting notes for the implementing engineer

- **The single most important deletion in the whole plan is `macro_classifier.py:182`** ("say there is no clear overnight macro change"). Until that line is gone, the position-impacts card will keep producing the form-letter even if you wire every data source perfectly.
- **`sector_context` must be built before the position-impact fix (#15) can work** — #15 depends on #5. Sequence them in that order.
- **There are two `_fallback` functions with near-identical no-change strings** (`portfolio_compiler.py:320` and `macro_classifier.py:253`). Unify them so a future engineer can't fix one and miss the other.
- **All call sites must be updated together** when adding params (`earnings_calendar`, `sector_context` into `classify_overnight_macro`). The production scheduler path (`scheduler.py:3502`) is the one the ICP actually opens every morning, and it is currently the *worse* of the two paths — prioritize it over the on-demand `routes/digest.py` path when they diverge.
- **Reminder per project memory:** backend deploys are VPS via SSH + Docker Compose (`sansar@134.122.114.241`), not Render auto-deploy. Snapshot tables backfill on the next daily refresh after #10 lands; SOXX won't color until that job runs.