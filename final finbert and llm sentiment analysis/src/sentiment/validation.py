"""Strict validation of LLM output. Nothing unvalidated reaches the cache."""
from __future__ import annotations

import json
import math
import re

LABELS = {"negative", "neutral", "positive"}
_EPS = 1e-6


class ResponseFormatError(ValueError):
    """The response as a whole is unusable (not JSON / wrong top-level shape)."""


def _strip_fences(raw: str) -> str:
    s = raw.strip()
    m = re.match(r"^```(?:json)?\s*(.*?)\s*```$", s, flags=re.DOTALL | re.IGNORECASE)
    return m.group(1) if m else s


def _num(value, name: str, lo: float, hi: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a number, got {type(value).__name__}")
    v = float(value)
    if not math.isfinite(v):
        raise ValueError(f"{name} is not finite")
    if v < lo - _EPS or v > hi + _EPS:
        raise ValueError(f"{name}={v} outside [{lo}, {hi}]")
    return min(hi, max(lo, v))


def validate_assessment(a: dict) -> dict:
    """Validate one assessment dict; return cleaned numbers/label or raise ValueError."""
    if not isinstance(a, dict):
        raise ValueError("assessment is not an object")
    sentiment = _num(a.get("sentiment_score"), "sentiment_score", -1.0, 1.0)
    relevance = _num(a.get("relevance_score"), "relevance_score", 0.0, 1.0)
    label = a.get("sentiment_label")
    if not isinstance(label, str) or label.strip().lower() not in LABELS:
        raise ValueError(f"sentiment_label must be one of {sorted(LABELS)}, got {label!r}")
    label = label.strip().lower()
    if (label == "positive" and sentiment < -0.05) or (label == "negative" and sentiment > 0.05):
        raise ValueError(f"label {label!r} contradicts sentiment_score={sentiment}")
    return {"sentiment": sentiment, "relevance": relevance, "label": label}


def validate_response(raw: str, expected: dict[str, list[str]]):
    """Parse and validate a batch response.

    ``expected`` maps article_id -> tickers that were requested.
    Returns ``(ok, errors)`` where both are keyed by (article_id, ticker).
    Pairs the model skipped, duplicated or mangled land in ``errors`` so the
    caller can retry just those. Raises ResponseFormatError if nothing at all
    can be read.
    """
    if raw is None or not str(raw).strip():
        raise ResponseFormatError("empty response")
    try:
        data = json.loads(_strip_fences(str(raw)))
    except json.JSONDecodeError as e:
        raise ResponseFormatError(f"invalid JSON: {e}") from e

    results = data.get("results") if isinstance(data, dict) else data
    if not isinstance(results, list):
        raise ResponseFormatError('top level must be {"results": [...]}')

    ok: dict[tuple[str, str], dict] = {}
    errors: dict[tuple[str, str], str] = {}
    seen: set[tuple[str, str]] = set()

    for entry in results:
        if not isinstance(entry, dict):
            continue
        aid = str(entry.get("article_id", "")).strip()
        if aid not in expected:
            continue  # hallucinated / unknown article id: ignore
        assessments = entry.get("assessments")
        if not isinstance(assessments, list):
            continue
        wanted = {t.upper(): t for t in expected[aid]}
        for a in assessments:
            if not isinstance(a, dict):
                continue
            ticker = str(a.get("ticker", "")).strip().upper()
            if ticker not in wanted:
                continue  # unrequested ticker: ignore
            key = (aid, wanted[ticker])
            if key in seen:
                ok.pop(key, None)
                errors[key] = "duplicate assessment for ticker"
                continue
            seen.add(key)
            try:
                ok[key] = validate_assessment(a)
            except ValueError as e:
                errors[key] = str(e)

    for aid, tickers in expected.items():
        for t in tickers:
            if (aid, t) not in ok and (aid, t) not in errors:
                errors[(aid, t)] = "missing from response"
    if not ok and not any("missing" not in m for m in errors.values()):
        raise ResponseFormatError("response contained none of the requested articles")
    return ok, errors
