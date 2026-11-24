"""Near-duplicate removal (syndicated copies, re-posts, re-tagged articles).

Within a rolling window, an article is a duplicate when its normalised title
matches exactly, or when title-token Jaccard similarity against a recent
article carrying a shared provider tag reaches ``jaccard``. The *earliest*
copy is canonical, so a later re-post can never pull a story earlier in time.
"""
from __future__ import annotations

import re
from collections import defaultdict, deque

import pandas as pd

_STOP = {"the", "a", "an", "of", "to", "in", "on", "for", "and", "at", "as", "by", "with"}


def normalize_title(title: object) -> str:
    if title is None or (isinstance(title, float) and pd.isna(title)):
        return ""
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]+", " ", str(title).lower())).strip()


def title_tokens(norm_title: str) -> frozenset:
    return frozenset(t for t in norm_title.split() if t not in _STOP)


def jaccard(a: frozenset, b: frozenset) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def find_duplicates(df: pd.DataFrame, window_hours: int = 48,
                    jaccard_threshold: float = 0.85) -> dict[str, str]:
    """``df`` needs: article_id, published_at (UTC), title, tags (iterable).

    Returns {duplicate_article_id: canonical_article_id}.
    """
    window = pd.Timedelta(hours=window_hours)
    ordered = df.sort_values(["published_at", "article_id"], kind="mergesort")

    by_title: dict[str, tuple[pd.Timestamp, str]] = {}
    by_tag: dict[str, deque] = defaultdict(deque)
    dup: dict[str, str] = {}

    for aid, ts, title, tags in zip(ordered["article_id"], ordered["published_at"],
                                    ordered["title"], ordered["tags"]):
        norm = normalize_title(title)
        tokens = title_tokens(norm)

        hit = by_title.get(norm) if norm else None
        if hit is not None and ts - hit[0] <= window:
            dup[aid] = hit[1]
            continue

        found = None
        if len(tokens) >= 4:
            for tag in tags:
                dq = by_tag[tag]
                while dq and ts - dq[0][0] > window:
                    dq.popleft()
                for _, cid, ctoks in dq:
                    if jaccard(tokens, ctoks) >= jaccard_threshold:
                        found = cid
                        break
                if found:
                    break
        if found:
            dup[aid] = found
            continue

        if norm:
            by_title[norm] = (ts, aid)
        if len(tokens) >= 4:
            for tag in tags:
                by_tag[tag].append((ts, aid, tokens))
    return dup
