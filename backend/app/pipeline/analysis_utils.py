import hashlib
import ast
import json
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


_PUBLIC_ANALYSIS_REPLACEMENTS: list[tuple[str, str]] = [
    (
        r"\bfull_body read rather than a fully grounded article analysis\b",
        "limited article data",
    ),
    (r"\bfully grounded article analysis\b", "limited article data"),
    (r"\bfully supported analysis\b", "limited article data"),
    (
        r"\bfull article coverage rather than a fully supported analysis\b",
        "limited article data",
    ),
    (r"\bfull_body\b", "full article"),
    (r"\btitle_only\b", "headline-only"),
    (r"\bheadline_summary\b", "headline summary"),
    (r"\bevidence quality\b", "data depth"),
    (r"\blow-evidence\b", "low-confidence data"),
    (r"\bcurrent evidence is still incomplete\b", "limited data remains"),
    (r"\bevidence is still incomplete\b", "limited data remains"),
    (r"\barticle evidence\b", "article data"),
    (
        r"Risk factors for [A-Z0-9.\-]+ are relatively balanced.*?dominates\.",
        "Risk factors are balanced.",
    ),
    (
        r"Synthesized one bullish event analysis[^.]*\.",
        "Event-based analysis assembled.",
    ),
    (r"\bSynthesized\b", "assembled"),
    (r"\bfallback\b", "supplemental"),
    (r"\bmethodology\b", "approach"),
    (r"\bprocessed\b", "reviewed"),
    (r"\bcoverage is thin\b", "data is limited"),
    (r"\blow-confidence coverage\b", "limited data"),
    (
        r"\bthe model did not provide a usable written rationale, so this summary was synthesized from the final dimension scores\b",
        "this summary was assembled from the final dimension scores",
    ),
    (r"\bfallback synthesis\b", "summary assembled"),
    (r"\bthesis\b", "risk assessment"),
    (r"\bpositive momentum\b", "improving trend"),
    (r"\bmacro headwinds\b", "macro pressure"),
    (r"\bprovisional\b", "limited data"),
    (r"\bcurrent read\b", "current rating"),
    (r"\bsentiment\b", "news signal"),
    (r"\bconfirms\b", "lowers risk"),
    (r"\bcoverage\b", "data"),
    (r"\bresearch note\b", "rating bulletin"),
    (r"\bresearch\b", "rating"),
    (r"\banalyst\b", "rating"),
    (r"\bmonitor\b", "track"),
    (r"\bmonitoring\b", "tracking"),
    (r"\bdigest\b", "rating"),
    (r"\bwatch\b", "track"),
    (r"\bwatching\b", "tracking"),
    (r"\bmomentum\b", "trend"),
    (r"\bthe read\b", "the rating"),
    (r"\bthis read\b", "this rating"),
    (r"\breview\b", "rating update"),
]

_BANNED_PHRASES_PATTERNS: list[tuple[str, str]] = [
    (r"\bpositive momentum\b", "improving trend"),
    (r"\bmomentum\b", "trend"),
    (r"\bmacro headwinds\b", "macro pressure"),
    (r"\bthesis\b", "risk assessment"),
    (r"\bprovisional\b", "limited data"),
    (r"\bcurrent read\b", "current rating"),
    (r"\bsentiment\b", "news signal"),
    (r"\bconfirms the\b", "lowers risk for the"),
    (r"\bconfirms\b", "lowers risk"),
    (r"\bcoverage\b", "data"),
    (r"\bmonitor\b", "track"),
    (r"\bmonitoring\b", "tracking"),
    (r"\bwatch\b", "track"),
    (r"\bwatching\b", "tracking"),
    (r"\bwatch for\b", "track for"),
    (r"\bthe read\b", "the rating"),
    (r"\bthis read\b", "this rating"),
    (r"\bcould shift\b", "may change"),
    (r"\bmay shift\b", "may change"),
    (r"\bwould change\b", "may change"),
    (r"\breview\b", "rating update"),
    (r"\bresearch note\b", "rating bulletin"),
    (r"\bresearch\b", "rating"),
    (r"\banalyst\b", "rating"),
    (r"\bdigest\b", "rating"),
    (r"\bdigest\b", "rating"),
    (r"\bmomentum\b", "trend"),
    (r"\bmay\b", "might"),
    (r"\bcould\b", "can"),
    (r"\bwould\b", "will"),
    (r"\bsuggests\b", "shows"),
    (r"\bindicates\b", "reflects"),
    (r"\bmarket uncertainty\b", "volatility"),
    (r"\bmixed signals\b", "competing forces"),
    (r"\bongoing volatility\b", "persistent volatility"),
    (r"\bvarious factors\b", "multiple drivers"),
    (r"\boverall trends?\b", "driving trend"),
    (r"\bbroad market\b", "market"),
    (r"\bgeneral uncertainty\b", "uncertainty"),
    (r"\bcould impact performance\b", "affects performance"),
    (r"\brisk factors.*balanced\b", "no dominant risk driver"),
    (r"\bno single force dominates\b", "no dominant risk driver"),
    (r"\bno material change\b", "stable"),
    (r"\bnothing urgent\b", "low urgency"),
]

_RISK_LEVELS: dict[str, str] = {
    "A": "Low Risk",
    "B": "Moderate Risk",
    "C": "Elevated Risk",
    "D": "High Risk",
    "F": "Severe Risk",
}

_DRIVER_MAX_LENGTH = 60
_RATIONALE_MAX_LENGTH = 140
_RATIONALE_HARD_MAX = 200

_GENERIC_DRIVERS: dict[str, list[str]] = {
    "news": [
        "Negative news pressure",
        "Positive news support",
        "Mixed news signals",
    ],
    "macro": [
        "Macro pressure on the sector",
        "Favorable macro backdrop",
        "Rate sensitivity adds risk",
    ],
    "sizing": [
        "Concentration amplifies downside",
        "Position size is manageable",
    ],
    "volatility": [
        "Elevated volatility",
        "Stable price action",
    ],
    "fundamentals": [
        "Valuation stretched vs earnings",
        "Weak revenue trend",
        "Strong earnings support",
    ],
}

_P1_BANNED_WORDS: list[str] = [
    "may", "could", "would", "suggests", "indicates",
    "sentiment", "momentum", "thesis", "coverage", "provisional",
    "mixed signals", "market uncertainty", "various factors",
    "overall trend", "broad market", "general uncertainty",
    "research", "analyst", "monitor", "watch",
]

_RATIONALE_MAX_LENGTH = 280


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def clamp_score(value: Any, default: int = 50) -> int:
    try:
        numeric = int(round(float(value)))
    except (TypeError, ValueError):
        numeric = default
    return max(0, min(100, numeric))


def safe_json_loads(raw_text: str, default: Any) -> Any:
    try:
        return json.loads(raw_text)
    except (TypeError, json.JSONDecodeError):
        return default


def _try_parse_json_like(raw_text: str) -> Any:
    parsed = safe_json_loads(raw_text, None)
    if parsed is not None:
        return parsed

    cleaned = re.sub(r",(\s*[}\]])", r"\1", raw_text)
    parsed = safe_json_loads(cleaned, None)
    if parsed is not None:
        return parsed

    try:
        return ast.literal_eval(cleaned)
    except (ValueError, SyntaxError):
        return None


def _strip_model_wrappers(raw_text: str) -> str:
    if not isinstance(raw_text, str):
        return ""

    cleaned = re.sub(r"<think>.*?</think>", "", raw_text, flags=re.DOTALL)
    cleaned = re.sub(r"```json\s*", "```", cleaned, flags=re.IGNORECASE)
    cleaned = cleaned.strip()

    fence_match = re.search(r"```\s*(.*?)\s*```", cleaned, flags=re.DOTALL)
    if fence_match:
        cleaned = fence_match.group(1).strip()

    return cleaned


def _balanced_json_spans(raw_text: str) -> list[str]:
    spans: list[str] = []
    length = len(raw_text)

    for start, opening in ((i, ch) for i, ch in enumerate(raw_text) if ch in "[{"):
        stack = [opening]
        in_string = False
        escaped = False

        for idx in range(start + 1, length):
            ch = raw_text[idx]

            if in_string:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    in_string = False
                continue

            if ch == '"':
                in_string = True
                continue

            if ch in "[{":
                stack.append(ch)
                continue

            if ch in "]}":
                if not stack:
                    break
                top = stack[-1]
                if (top == "{" and ch != "}") or (top == "[" and ch != "]"):
                    break
                stack.pop()
                if not stack:
                    spans.append(raw_text[start : idx + 1].strip())
                    break

        if spans:
            break

    return spans


def extract_json_value(raw_text: str, default: Any) -> Any:
    cleaned = _strip_model_wrappers(raw_text)
    parsed = _try_parse_json_like(cleaned)
    if parsed is not None:
        return parsed

    if not cleaned:
        return default

    for candidate in _balanced_json_spans(cleaned):
        parsed = _try_parse_json_like(candidate)
        if parsed is not None:
            return parsed

    return default


def extract_json_object(raw_text: str, default: Any) -> Any:
    parsed = extract_json_value(raw_text, None)
    if isinstance(parsed, dict):
        return parsed
    if isinstance(parsed, list) and len(parsed) > 0:
        for item in parsed:
            if isinstance(item, dict):
                return item
    return default


def extract_json_list(raw_text: str, default: Any) -> Any:
    parsed = extract_json_value(raw_text, None)
    if isinstance(parsed, list):
        return parsed
    if isinstance(parsed, dict):
        for key in ("results", "scores", "items", "data", "payload", "output"):
            candidate = parsed.get(key)
            if isinstance(candidate, list):
                return candidate
        for value in parsed.values():
            if isinstance(value, list):
                return value
    return default


def make_event_hash(*parts: Any) -> str:
    payload = "||".join(str(part or "").strip().lower() for part in parts)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def sanitize_public_analysis_text(value: Any) -> Any:
    if isinstance(value, str):
        cleaned = value
        for pattern, replacement in _PUBLIC_ANALYSIS_REPLACEMENTS:
            cleaned = re.sub(pattern, replacement, cleaned, flags=re.IGNORECASE)
        if "\n" in cleaned:
            lines = [re.sub(r"[ \t]+", " ", line).strip() for line in cleaned.splitlines()]
            cleaned = "\n".join(line for line in lines if line)
        else:
            cleaned = re.sub(r"\s+", " ", cleaned).strip()
        return cleaned
    if isinstance(value, list):
        return [sanitize_public_analysis_text(item) for item in value]
    if isinstance(value, dict):
        return {key: sanitize_public_analysis_text(item) for key, item in value.items()}
    return value


def score_to_grade(score: float) -> str:
    if score >= 80:
        return "A"
    if score >= 65:
        return "B"
    if score >= 50:
        return "C"
    if score >= 35:
        return "D"
    return "F"


def grade_to_risk_level(grade: str) -> str:
    return _RISK_LEVELS.get(grade.upper(), "Elevated Risk")


def grade_direction(current_score: Optional[float], previous_score: Optional[float]) -> str:
    if current_score is None or previous_score is None:
        return "flat"
    delta = current_score - previous_score
    if delta > 2:
        return "up"
    if delta < -2:
        return "down"
    return "flat"


def evidence_strength(source_count: int) -> str:
    if source_count == 0:
        return "thin"
    if source_count <= 2:
        return "thin"
    if source_count <= 5:
        return "moderate"
    return "strong"


def _extract_drivers(text: str, max_drivers: int = 2) -> list[str]:
    lines = [line.strip() for line in text.split("\n") if line.strip()]
    drivers: list[str] = []
    if lines:
        skip_header = lines[0] if lines else ""
        is_header = bool(re.match(r'^[A-F]\s*—', skip_header))
        start = 1 if is_header else 0
        for line in lines[start:]:
            cleaned = line.lstrip("•-*• ").rstrip()
            if cleaned and len(cleaned) > 3:
                drivers.append(cleaned)
    if not drivers:
        sentences = re.split(r'[.;!]\s*', text)
        for s in sentences:
            s = s.strip()
            if s and len(s) > 5 and not s.lower().startswith(("grade", "rating", "score", "a ", "b ", "c ", "d ", "f ")):
                drivers.append(s)
    result = []
    for d in drivers[:max_drivers]:
        d = re.sub(r"\s+", " ", d).strip()
        d = _sanitize_driver_text(d)
        if d and not _is_garbled_driver(d):
            if len(d) > _DRIVER_MAX_LENGTH:
                d = d[:_DRIVER_MAX_LENGTH - 1].rstrip() + "…"
            result.append(d)
    return result


def _is_garbled_driver(text: str) -> bool:
    if not text or len(text) < 10:
        return True
    text_lower = text.lower().strip()
    garbled_patterns = [
        r"^\w+\s+risk assessment\s+(shows|reflects)\s+",
        r"^\w+\s+(shows|reflects|is)\s+(data|limited|might)",
        r"limited data.*limited data",
        r"^\w+\s+\w+\s+might be",
    ]
    generic_fillers = [
        "balanced risk",
        "no dominant risk",
        "no single force",
        "risk factors are balanced",
        "no material change",
        "nothing urgent",
        "nothing specific",
        "no specific",
        "data might be limited",
        "balanced forces",
    ]
    for pat in garbled_patterns:
        if re.search(pat, text_lower):
            return True
    for filler in generic_fillers:
        if filler in text_lower:
            return True
    return False


def _sanitize_driver_text(text: str) -> str:
    cleaned = text
    for pattern, replacement in _BANNED_PHRASES_PATTERNS:
        cleaned = re.sub(pattern, replacement, cleaned, flags=re.IGNORECASE)
    for word in _P1_BANNED_WORDS:
        pattern = rf"\b{word}\b"
        cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    cleaned = re.sub(r"\s+\.","",  cleaned).strip()
    cleaned = re.sub(r"\.\s*\.", ".", cleaned).strip()
    cleaned = re.sub(r"^[,;]\s*", "", cleaned).strip()
    cleaned = re.sub(r"\s*[,;]\s*$", "", cleaned).strip()
    if len(cleaned) < 10 or cleaned.lower().strip(",. ") in ("", "limited data"):
        return ""
    cleaned = cleaned[0].upper() + cleaned[1:] if cleaned else cleaned
    return cleaned


def _pick_generic_drivers(grade: str, scores: Optional[Dict] = None) -> List[str]:
    if grade in ("D", "F"):
        drivers = _GENERIC_DRIVERS["news"][:1] + _GENERIC_DRIVERS["sizing"][:1]
    elif grade == "C":
        drivers = _GENERIC_DRIVERS["macro"][:1] + _GENERIC_DRIVERS["volatility"][:1]
    else:
        drivers = _GENERIC_DRIVERS["fundamentals"][:1]
    if scores:
        news = int(scores.get("news_sentiment", 50))
        volatility = int(scores.get("volatility_trend", 50))
        macro = int(scores.get("macro_exposure", 50))
        if news < 35:
            drivers[0] = _GENERIC_DRIVERS["news"][0]
        elif news > 65:
            drivers[0] = _GENERIC_DRIVERS["news"][1]
        if volatility < 35:
            drivers[-1] = _GENERIC_DRIVERS["volatility"][0]
        elif macro < 35:
            drivers[-1] = _GENERIC_DRIVERS["macro"][0]
    return drivers[:2]


def _direction_arrow(direction: Optional[str] = None) -> str:
    d = str(direction or "flat").strip().lower()
    if d == "up":
        return "↓ improving"
    if d == "down":
        return "↑ worsening"
    return "→ stable"


def format_rationale(
    grade: str,
    direction: Optional[str] = None,
    raw_text: Optional[str] = None,
    scores: Optional[Dict] = None,
    source_count: int = 0,
) -> str:
    risk_level = _RISK_LEVELS.get(grade, "Elevated Risk")
    arrow = _direction_arrow(direction)
    header = f"{grade} — {risk_level} ({arrow})"

    drivers: list[str] = []
    if raw_text and raw_text.strip():
        drivers = _extract_drivers(raw_text, max_drivers=2)

    if not drivers and source_count == 0:
        return f"{header}\nLimited data — risk based on fundamentals"

    if not drivers:
        if scores:
            drivers = _pick_generic_drivers(grade, scores)
        else:
            drivers = _pick_generic_drivers(grade)

    if not drivers or all(len(d.strip()) < 5 for d in drivers):
        ev = evidence_strength(source_count)
        if ev == "thin":
            return f"{header}\nLimited data — risk based on fundamentals"
        return f"{header}\nLimited data — risk based on fundamentals"

    parts = [header]
    for d in drivers:
        driver = d.rstrip(".; ")
        if len(driver) > _DRIVER_MAX_LENGTH:
            driver = driver[:_DRIVER_MAX_LENGTH - 1].rstrip() + "…"
        parts.append(driver)

    result = "\n".join(parts)

    if len(result) > _RATIONALE_HARD_MAX:
        parts = [header]
        for d in drivers[:1]:
            driver = d.rstrip(".; ")
            if len(driver) > _DRIVER_MAX_LENGTH:
                driver = driver[:_DRIVER_MAX_LENGTH - 1].rstrip() + "…"
            parts.append(driver)
        result = "\n".join(parts)

    return result


def sanitize_rationale(text: str) -> str:
    if not text or not text.strip():
        return ""
    cleaned = text.strip()
    for pattern, replacement in _BANNED_PHRASES_PATTERNS:
        cleaned = re.sub(pattern, replacement, cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if len(cleaned) > _RATIONALE_HARD_MAX:
        sentinel = ". "
        last_period = cleaned[:_RATIONALE_HARD_MAX].rfind(sentinel)
        if last_period > 40:
            cleaned = cleaned[: last_period + 1].strip()
        else:
            last_comma = cleaned[:_RATIONALE_HARD_MAX].rfind(", ")
            if last_comma > 40:
                cleaned = cleaned[:last_comma].strip() + "."
            else:
                cleaned = cleaned[:_RATIONALE_HARD_MAX].rstrip() + "."
    if len(cleaned) < 10:
        return ""
    return cleaned
