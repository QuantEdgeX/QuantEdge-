"""Entity matching: which companies is an article actually about?

Evidence comes from (a) the provider's own symbol tag, (b) company names,
products and executives found in the text, and (c) exchange-qualified
tickers such as "(NASDAQ: AAPL)" or cashtags like "$AAPL".

A bare ticker string ("V", "C", "MA", "GE", "KO" ...) is *never* evidence.
The provider tag alone is not enough either unless
``require_text_evidence=False``: scraped tags are noisy, and a tag with no
mention of the company anywhere in the text is not worth an LLM call.
The LLM makes the final relevance judgement for every surviving candidate.
"""
from __future__ import annotations

import html
import re
from dataclasses import asdict, dataclass
from typing import Iterable

import pandas as pd

from .universe import COMPANIES, Company

_QUOTES = str.maketrans({"\u2019": "'", "\u2018": "'", "\u201c": '"', "\u201d": '"',
                         "\u00a0": " "})

_EXCHANGE_CTX = re.compile(
    r"\b(?:NASDAQ|NYSE|NYSEARCA|NYSE American|Nasdaq|NasdaqGS|NasdaqGM)\s*:\s*([A-Z][A-Z.\-]{0,4})\b")
_CASHTAG = re.compile(r"(?<![\w$])\$([A-Z]{1,5})\b")


def normalize_text(text: object) -> str:
    if text is None or (isinstance(text, float) and pd.isna(text)):
        return ""
    s = html.unescape(str(text)).translate(_QUOTES)
    return re.sub(r"\s+", " ", s).strip()


def _alt(aliases: Iterable[str]) -> str:
    items = sorted(set(aliases), key=len, reverse=True)
    return "|".join(re.escape(a) for a in items)


def _compile(aliases: Iterable[str], ignore_case: bool):
    aliases = list(aliases)
    if not aliases:
        return None
    flags = re.IGNORECASE if ignore_case else 0
    return re.compile(rf"(?<!\w)(?:{_alt(aliases)})(?!\w)", flags)


@dataclass
class Evidence:
    tag: bool = False
    strong_title: int = 0
    strong_body: int = 0
    weak_title: int = 0
    weak_body: int = 0
    ctx: int = 0

    @property
    def has_text_evidence(self) -> bool:
        if self.strong_title or self.strong_body or self.ctx:
            return True
        # A weak (ambiguous-word) mention only counts when the provider
        # tag corroborates it.
        return bool(self.tag and (self.weak_title or self.weak_body))

    def rank(self) -> float:
        return (3.0 * (self.strong_title > 0) + 2.0 * self.tag + 2.0 * (self.ctx > 0)
                + min(self.strong_body, 3) + 0.5 * min(self.weak_title + self.weak_body, 2))

    def to_dict(self) -> dict:
        return asdict(self)


class _CompiledCompany:
    """Pre-compiled regexes for one company; ``since`` aliases kept apart."""

    def __init__(self, company: Company):
        self.company = company
        since = {k: pd.Timestamp(v, tz="UTC") for k, v in company.since.items()}
        self.tiers = []  # (tier_name, plain_regex, [(regex, since_ts)])
        for tier, aliases, ci in (("strong", company.strong, True),
                                  ("strong", company.strong_cs, False),
                                  ("weak", company.weak_cs, False)):
            plain = [a for a in aliases if a not in since]
            dated = [(_compile([a], ci), since[a]) for a in aliases if a in since]
            self.tiers.append((tier, _compile(plain, ci), dated))
        self.exclude = (re.compile("|".join(re.escape(e) for e in company.exclude),
                                   re.IGNORECASE) if company.exclude else None)

    def count(self, text: str, published_at: pd.Timestamp | None) -> tuple[int, int]:
        """Return (strong_matches, weak_matches) in ``text``."""
        if not text:
            return 0, 0
        if self.exclude is not None:
            text = self.exclude.sub(" ", text)
        counts = {"strong": 0, "weak": 0}
        for tier, plain, dated in self.tiers:
            if plain is not None:
                counts[tier] += len(plain.findall(text))
            for rx, since_ts in dated:
                if published_at is None or published_at >= since_ts:
                    counts[tier] += len(rx.findall(text))
        return counts["strong"], counts["weak"]


class EntityMatcher:
    def __init__(self, companies: Iterable[Company] = COMPANIES):
        self._compiled = {c.ticker: _CompiledCompany(c) for c in companies}
        self.tickers = set(self._compiled)

    # ------------------------------------------------------------------
    def evidence(self, title: object, body: object, tags: Iterable[str] = (),
                 published_at: pd.Timestamp | None = None) -> dict[str, Evidence]:
        title_n, body_n = normalize_text(title), normalize_text(body)
        tags = {str(t).strip().upper() for t in tags if t}
        out: dict[str, Evidence] = {}

        ctx_counts: dict[str, int] = {}
        for text in (title_n, body_n):
            for rx in (_EXCHANGE_CTX, _CASHTAG):
                for sym in rx.findall(text):
                    sym = sym.upper().rstrip(".")
                    if sym in self.tickers:
                        ctx_counts[sym] = ctx_counts.get(sym, 0) + 1

        for ticker, comp in self._compiled.items():
            st, wt = comp.count(title_n, published_at)
            sb, wb = comp.count(body_n, published_at)
            ev = Evidence(tag=ticker in tags, strong_title=st, strong_body=sb,
                          weak_title=wt, weak_body=wb, ctx=ctx_counts.get(ticker, 0))
            if ev.tag or ev.strong_title or ev.strong_body or ev.weak_title \
                    or ev.weak_body or ev.ctx:
                out[ticker] = ev
        return out

    def candidates(self, evidence: dict[str, Evidence], require_text_evidence: bool = True,
                   max_candidates: int = 6) -> list[tuple[str, Evidence]]:
        kept = [(t, e) for t, e in evidence.items()
                if e.has_text_evidence or (e.tag and not require_text_evidence)]
        kept.sort(key=lambda te: (-te[1].rank(), te[0]))
        return kept[:max_candidates]
