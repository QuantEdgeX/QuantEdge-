"""SQLite cache so that nothing is ever analysed twice.

Tables
------
articles    one row per canonical or duplicate article (dup_of marks copies)
candidates  (article, ticker) pairs that passed entity matching
scores      (article, ticker, model_id, prompt_version) -> sentiment/relevance

Scores are keyed on model *and* prompt version, so changing either triggers
fresh scoring while old results stay available for comparison.
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

import pandas as pd

SCHEMA = """
CREATE TABLE IF NOT EXISTS articles (
    article_id   TEXT PRIMARY KEY,
    published_at TEXT NOT NULL,
    time_known   INTEGER NOT NULL,
    title        TEXT,
    body         TEXT,
    url          TEXT,
    publisher    TEXT,
    author       TEXT,
    tags         TEXT,
    dup_of       TEXT,
    trade_date   TEXT
);
CREATE INDEX IF NOT EXISTS ix_articles_trade ON articles(trade_date);
CREATE TABLE IF NOT EXISTS candidates (
    article_id TEXT NOT NULL,
    ticker     TEXT NOT NULL,
    evidence   TEXT,
    PRIMARY KEY (article_id, ticker)
);
CREATE TABLE IF NOT EXISTS scores (
    article_id     TEXT NOT NULL,
    ticker         TEXT NOT NULL,
    model_id       TEXT NOT NULL,
    prompt_version TEXT NOT NULL,
    sentiment      REAL,
    relevance      REAL,
    label          TEXT,
    status         TEXT NOT NULL,
    error          TEXT,
    created_at     TEXT NOT NULL,
    PRIMARY KEY (article_id, ticker, model_id, prompt_version)
);
"""


class Store:
    def __init__(self, path: Path | str):
        self.path = Path(path)
        if str(path) != ":memory:":
            self.path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(path))
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(SCHEMA)
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()

    @contextmanager
    def transaction(self):
        try:
            yield self.conn
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise

    # ---- articles / candidates ---------------------------------------
    def insert_articles(self, rows: Iterable[dict]) -> None:
        with self.transaction() as c:
            c.executemany(
                """INSERT OR REPLACE INTO articles
                   (article_id, published_at, time_known, title, body, url, publisher,
                    author, tags, dup_of, trade_date)
                   VALUES (:article_id,:published_at,:time_known,:title,:body,:url,
                           :publisher,:author,:tags,:dup_of,:trade_date)""", list(rows))

    def insert_candidates(self, rows: Iterable[tuple[str, str, dict]]) -> None:
        with self.transaction() as c:
            c.executemany(
                "INSERT OR REPLACE INTO candidates (article_id, ticker, evidence) VALUES (?,?,?)",
                [(a, t, json.dumps(e)) for a, t, e in rows])

    def get_articles(self, ids: list[str]) -> dict[str, sqlite3.Row]:
        out: dict[str, sqlite3.Row] = {}
        for i in range(0, len(ids), 500):
            chunk = ids[i:i + 500]
            q = ",".join("?" * len(chunk))
            for r in self.conn.execute(f"SELECT * FROM articles WHERE article_id IN ({q})", chunk):
                out[r["article_id"]] = r
        return out

    def article_count(self) -> int:
        return self.conn.execute("SELECT COUNT(*) FROM articles").fetchone()[0]

    # ---- scoring queue -------------------------------------------------
    def pending_pairs(self, model_id: str, prompt_version: str,
                      retry_failed: bool = False, limit: int | None = None
                      ) -> list[tuple[str, str]]:
        """Candidate (article, ticker) pairs with no successful score yet.

        Duplicates and articles that could not be assigned a trading day are
        never queued, so no money is spent on them.
        """
        sql = f"""
            SELECT c.article_id, c.ticker
            FROM candidates c
            JOIN articles a ON a.article_id = c.article_id
            LEFT JOIN scores s ON s.article_id = c.article_id AND s.ticker = c.ticker
                 AND s.model_id = ? AND s.prompt_version = ?
            WHERE a.dup_of IS NULL AND a.trade_date IS NOT NULL
              AND (s.status IS NULL {"OR s.status = 'failed'" if retry_failed else ""})
            ORDER BY a.published_at, c.article_id, c.ticker"""
        if limit:
            sql += f" LIMIT {int(limit)}"
        return [(r[0], r[1]) for r in self.conn.execute(sql, (model_id, prompt_version))]

    def save_scores(self, rows: Iterable[dict]) -> None:
        now = datetime.now(timezone.utc).isoformat(timespec="seconds")
        with self.transaction() as c:
            c.executemany(
                """INSERT OR REPLACE INTO scores
                   (article_id, ticker, model_id, prompt_version, sentiment, relevance,
                    label, status, error, created_at)
                   VALUES (:article_id,:ticker,:model_id,:prompt_version,:sentiment,
                           :relevance,:label,:status,:error,:created_at)""",
                [{**{"sentiment": None, "relevance": None, "label": None, "error": None},
                  **r, "created_at": now} for r in rows])

    # ---- exports ---------------------------------------------------------
    def scored_pairs_df(self, model_id: str, prompt_version: str) -> pd.DataFrame:
        """Article-level results joined to canonical articles (for aggregation)."""
        sql = """
            SELECT s.article_id, s.ticker, s.sentiment, s.relevance, s.label, s.status,
                   a.published_at, a.trade_date, a.title, a.url, a.publisher
            FROM scores s JOIN articles a ON a.article_id = s.article_id
            WHERE s.model_id = ? AND s.prompt_version = ? AND a.dup_of IS NULL"""
        return pd.read_sql_query(sql, self.conn, params=(model_id, prompt_version))

    def candidates_df(self) -> pd.DataFrame:
        sql = """
            SELECT c.article_id, c.ticker, a.trade_date, a.published_at
            FROM candidates c JOIN articles a ON a.article_id = c.article_id
            WHERE a.dup_of IS NULL AND a.trade_date IS NOT NULL"""
        return pd.read_sql_query(sql, self.conn)

    def stats(self) -> dict:
        q = lambda s: self.conn.execute(s).fetchone()[0]
        return {
            "articles_total": q("SELECT COUNT(*) FROM articles"),
            "articles_canonical": q("SELECT COUNT(*) FROM articles WHERE dup_of IS NULL"),
            "articles_duplicates": q("SELECT COUNT(*) FROM articles WHERE dup_of IS NOT NULL"),
            "articles_with_trade_date": q(
                "SELECT COUNT(*) FROM articles WHERE dup_of IS NULL AND trade_date IS NOT NULL"),
            "candidate_pairs": q("SELECT COUNT(*) FROM candidates"),
        }
