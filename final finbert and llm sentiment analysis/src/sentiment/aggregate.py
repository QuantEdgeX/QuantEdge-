"""Daily ticker-level aggregation.

For each (ticker, trade_date):

    sentiment_score = sum(relevance_i * sentiment_i) / sum(relevance_i)

over canonical (de-duplicated) articles with ``relevance >= min_relevance``.
Every (trading day, ticker) cell is present in the output. Days without
usable news are explicit: score 0.0, article_count 0, has_news 0 (the same
neutral fill your existing pipeline uses, but now visible and auditable).
``n_unscored`` counts candidate articles that could not be scored (failed or
still pending) so partially-scored days can be spotted and excluded.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

OUTPUT_COLUMNS = ["date", "ticker", "sentiment_score", "article_count", "has_news",
                  "relevance_weight_sum", "n_candidates", "n_unscored"]


def aggregate_daily(scores: pd.DataFrame, candidates: pd.DataFrame, trading_days,
                    tickers: list[str], min_relevance: float = 0.30,
                    relevance_override: pd.DataFrame | None = None) -> pd.DataFrame:
    """``scores``: Store.scored_pairs_df; ``candidates``: Store.candidates_df.

    ``relevance_override`` (article_id, ticker, relevance) replaces the scorer's own
    relevance, e.g. to weight FinBERT by the LLM's relevance for an ablation.
    """
    ok = scores[scores["status"] == "ok"].copy()
    if relevance_override is not None:
        ov = relevance_override.rename(columns={"relevance": "relevance_ov"})
        ok = ok.merge(ov[["article_id", "ticker", "relevance_ov"]], on=["article_id", "ticker"],
                      how="inner")
        ok["relevance"] = ok["relevance_ov"]
    used = ok[ok["relevance"] >= min_relevance].copy()
    used["w_s"] = used["relevance"] * used["sentiment"]

    daily = used.groupby(["trade_date", "ticker"]).agg(
        num=("w_s", "sum"), relevance_weight_sum=("relevance", "sum"),
        article_count=("article_id", "nunique")).reset_index()
    daily["sentiment_score"] = (daily["num"] / daily["relevance_weight_sum"]).clip(-1.0, 1.0)

    cand = candidates.groupby(["trade_date", "ticker"]).agg(
        n_candidates=("article_id", "nunique")).reset_index()
    scored_ok = ok.groupby(["trade_date", "ticker"]).agg(n_scored=("article_id", "nunique")).reset_index()

    days = pd.to_datetime(pd.Series(np.asarray(trading_days).astype("datetime64[D]")))
    grid = pd.MultiIndex.from_product([days, sorted(tickers)], names=["date", "ticker"]).to_frame(index=False)
    grid["trade_date"] = grid["date"].dt.strftime("%Y-%m-%d")

    out = (grid.merge(daily.drop(columns="num"), on=["trade_date", "ticker"], how="left")
               .merge(cand, on=["trade_date", "ticker"], how="left")
               .merge(scored_ok, on=["trade_date", "ticker"], how="left"))
    out["sentiment_score"] = out["sentiment_score"].fillna(0.0)
    out["article_count"] = out["article_count"].fillna(0).astype(int)
    out["relevance_weight_sum"] = out["relevance_weight_sum"].fillna(0.0)
    out["n_candidates"] = out["n_candidates"].fillna(0).astype(int)
    out["n_unscored"] = (out["n_candidates"] - out["n_scored"].fillna(0).astype(int)).clip(lower=0)
    out["has_news"] = (out["article_count"] > 0).astype(int)
    out["date"] = out["date"].dt.strftime("%Y-%m-%d")
    return out[OUTPUT_COLUMNS].sort_values(["ticker", "date"]).reset_index(drop=True)


def coverage_report(daily: pd.DataFrame) -> pd.DataFrame:
    g = daily.groupby("ticker").agg(
        days=("date", "count"), days_with_news=("has_news", "sum"),
        articles=("article_count", "sum"), unscored=("n_unscored", "sum"))
    g["pct_days_with_news"] = (100 * g["days_with_news"] / g["days"]).round(1)
    return g.sort_values("pct_days_with_news")
