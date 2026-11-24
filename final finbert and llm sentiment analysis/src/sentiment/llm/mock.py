"""Deterministic offline LLM used by tests and ``LLM_PROVIDER=mock`` dry runs.

It is a keyword heuristic, NOT a sentiment model. Failure injection lets the
tests exercise retries, rate limits, invalid JSON and partial responses.
"""
from __future__ import annotations

import json

from ..prompts import ARTICLES_MARKER
from .base import PermanentLLMError, RateLimitError, TransientLLMError

POS = ("beat", "surge", "record", "upgrade", "growth", "profit", "wins", "soar", "raises")
NEG = ("miss", "plunge", "downgrade", "lawsuit", "probe", "recall", "cut", "fall", "slump")


class MockLLM:
    model_id = "mock-keyword-v1"

    def __init__(self, rate_limit_first: int = 0, transient_first: int = 0,
                 garbage_first: int = 0, drop_ticker: str | None = None,
                 fatal: bool = False, bad_range_first: int = 0):
        self.calls = 0
        self.rate_limit_first, self.transient_first = rate_limit_first, transient_first
        self.garbage_first, self.drop_ticker = garbage_first, drop_ticker
        self.fatal, self.bad_range_first = fatal, bad_range_first
        self.prompts: list[str] = []

    def generate_json(self, system: str, user: str, max_output_tokens: int) -> str:
        self.calls += 1
        self.prompts.append(user)
        if self.fatal:
            raise PermanentLLMError("bad key", fatal=True)
        if self.calls <= self.rate_limit_first:
            raise RateLimitError("429", retry_after=0.0)
        if self.calls <= self.transient_first:
            raise TransientLLMError("503")
        if self.calls <= self.garbage_first:
            return "Sure! Here is the analysis: positive"
        items = json.loads(user.split(ARTICLES_MARKER, 1)[1].split("\n\nYour previous answer")[0])
        results = []
        for it in items:
            text = f"{it['title']} {it['text']}".lower()
            score = 0.0
            score += 0.6 * any(w in text for w in POS)
            score -= 0.6 * any(w in text for w in NEG)
            assess = []
            for c in it["companies"]:
                if c["ticker"] == self.drop_ticker:
                    continue
                name = c["name"].split()[0].lower().strip(",.")
                rel = 1.0 if name in it["title"].lower() else (0.6 if name in text else 0.1)
                s = score if rel >= 0.3 else 0.0
                if self.calls <= self.bad_range_first:
                    s = 3.0
                assess.append({"ticker": c["ticker"], "sentiment_score": s,
                               "relevance_score": rel,
                               "sentiment_label": "positive" if s > 0.1 else
                               "negative" if s < -0.1 else "neutral"})
            results.append({"article_id": it["article_id"], "assessments": assess})
        return json.dumps({"results": results})
