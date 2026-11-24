"""Ingest a normalised news CSV into the SQLite cache.

Pass 1 reads only light columns, merges rows of the same article (the same
story often appears once per provider tag), removes near-duplicates and
assigns each canonical article a trading day under the prediction cutoff.
Pass 2 streams the full text, runs entity matching and stores everything.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path

import numpy as np
import pandas as pd

from .config import Settings
from .dedup import find_duplicates
from .entities import EntityMatcher
from .market_time import assign_trade_dates
from .store import Store

logger = logging.getLogger(__name__)


def ingest_news(prepared_csv: str | Path, store: Store, settings: Settings,
                trading_days: np.ndarray, matcher: EntityMatcher | None = None,
                chunksize: int = 50_000) -> dict:
    matcher = matcher or EntityMatcher()
    light = pd.read_csv(prepared_csv, dtype=str, keep_default_na=False,
                        usecols=["article_id", "published_at", "time_known", "title", "symbol_tag"])
    if light.empty:
        logger.warning("Prepared news file is empty; nothing to ingest.")
        return {"rows": 0}
    light["published_at"] = pd.to_datetime(light["published_at"], utc=True)
    light["time_known"] = light["time_known"].astype(int)

    # ---- merge tag rows of the same article ---------------------------
    grouped = light.groupby("article_id", sort=False).agg(
        published_at=("published_at", "min"),
        time_known=("time_known", "min"),
        title=("title", "first"),
        tags=("symbol_tag", lambda s: tuple(sorted({t for t in s if t}))),
    ).reset_index()
    logger.info("Ingest: %d rows -> %d distinct articles", len(light), len(grouped))

    # ---- near-duplicate removal (earliest copy is canonical) ----------
    dup_map = find_duplicates(grouped, settings.dedup_window_hours, settings.dedup_jaccard)
    tags_by_id = dict(zip(grouped["article_id"], grouped["tags"]))
    merged_tags = {k: set(v) for k, v in tags_by_id.items()}
    for dup, canon in dup_map.items():
        merged_tags[canon] |= set(tags_by_id[dup])
    logger.info("Dedup: %d duplicates of %d articles", len(dup_map), len(grouped))

    # ---- trading-day assignment (leakage control) ---------------------
    grouped["trade_date"] = assign_trade_dates(
        grouped["published_at"], grouped["time_known"].astype(bool), trading_days,
        cutoff=settings.cutoff_time, tz=settings.market_tz)
    trade_by_id = dict(zip(grouped["article_id"], grouped["trade_date"]))
    pub_by_id = dict(zip(grouped["article_id"], grouped["published_at"]))
    known_by_id = dict(zip(grouped["article_id"], grouped["time_known"]))
    n_unassigned = int(grouped["trade_date"].isna().sum())

    # ---- pass 2: stream bodies, match entities, store -----------------
    seen: set[str] = set()
    stats = {"articles_distinct": len(grouped), "duplicates": len(dup_map),
             "unassigned_trade_date": n_unassigned, "stored": 0, "candidate_pairs": 0,
             "tag_only_dropped": 0, "no_candidates": 0}

    reader = pd.read_csv(prepared_csv, dtype=str, keep_default_na=False, chunksize=chunksize)
    for chunk in reader:
        chunk = chunk[~chunk["article_id"].isin(seen)].drop_duplicates("article_id")
        art_rows, cand_rows = [], []
        for r in chunk.itertuples(index=False):
            aid = r.article_id
            seen.add(aid)
            is_dup = aid in dup_map
            trade = trade_by_id.get(aid)
            trade_s = None if pd.isna(trade) else pd.Timestamp(trade).strftime("%Y-%m-%d")
            art_rows.append({
                "article_id": aid,
                "published_at": pub_by_id[aid].strftime("%Y-%m-%dT%H:%M:%SZ"),
                "time_known": int(known_by_id[aid]),
                "title": r.title, "body": r.body, "url": r.url,
                "publisher": r.publisher, "author": r.author,
                "tags": json.dumps(sorted(merged_tags[aid])),
                "dup_of": dup_map.get(aid),
                "trade_date": trade_s,
            })
            if is_dup or trade_s is None:
                continue
            ev = matcher.evidence(r.title, r.body, merged_tags[aid], pub_by_id[aid])
            cands = matcher.candidates(ev, settings.require_text_evidence,
                                       settings.max_candidates_per_article)
            tagged = {t for t, e in ev.items() if e.tag}
            stats["tag_only_dropped"] += len(tagged - {t for t, _ in cands})
            if not cands:
                stats["no_candidates"] += 1
            for ticker, e in cands:
                cand_rows.append((aid, ticker, e.to_dict()))
        store.insert_articles(art_rows)
        store.insert_candidates(cand_rows)
        stats["stored"] += len(art_rows)
        stats["candidate_pairs"] += len(cand_rows)
        logger.info("Ingest progress: %s", stats)

    logger.info("Ingest done: %s", stats)
    return stats
