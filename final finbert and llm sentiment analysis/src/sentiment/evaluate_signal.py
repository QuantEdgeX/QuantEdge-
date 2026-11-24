"""Model-free signal diagnostics: does sentiment at the close of day D rank-correlate
with the 5-day forward return, and does the LLM arm differ from the FinBERT arm?

This is NOT a substitute for re-running your full model evaluation; it is a cheap,
leak-free first look. Forward return uses the same definition as your feature code:
``Close.shift(-h) / Close - 1`` per ticker.

* IC = daily cross-sectional Spearman correlation across tickers, averaged over dates.
* Forward returns overlap (h=5), so naive t-stats overstate significance. Confidence
  intervals therefore come from a moving-block bootstrap over dates (block = horizon).
* "news days" restricts to (date, ticker) cells with has_news == 1.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def forward_returns(prices_path, horizon: int = 5) -> pd.DataFrame:
    px = pd.read_csv(prices_path, usecols=["Date", "Ticker", "Close"])
    px["Date"] = pd.to_datetime(px["Date"])
    px = px.sort_values(["Ticker", "Date"])
    px["fwd_return"] = px.groupby("Ticker")["Close"].shift(-horizon) / px["Close"] - 1
    return px.rename(columns={"Date": "date", "Ticker": "ticker"})[["date", "ticker", "fwd_return"]]


def _daily_ic(df: pd.DataFrame, min_names: int) -> pd.Series:
    def ic(g: pd.DataFrame) -> float:
        if len(g) < min_names or g["sentiment_score"].nunique() < 2:
            return np.nan
        return g["sentiment_score"].rank().corr(g["fwd_return"].rank())
    return df.groupby("date")[["sentiment_score", "fwd_return"]].apply(ic).dropna()


def block_bootstrap_ci(x: np.ndarray, block: int, n_boot: int = 2000, seed: int = 0,
                       alpha: float = 0.05) -> tuple[float, float]:
    n = len(x)
    if n < 2 * block:
        return (np.nan, np.nan)
    rng = np.random.default_rng(seed)
    n_blocks = int(np.ceil(n / block))
    starts_max = n - block
    means = np.empty(n_boot)
    for b in range(n_boot):
        starts = rng.integers(0, starts_max + 1, n_blocks)
        sample = np.concatenate([x[s:s + block] for s in starts])[:n]
        means[b] = sample.mean()
    return tuple(np.quantile(means, [alpha / 2, 1 - alpha / 2]))


def evaluate_arms(arms: dict[str, pd.DataFrame], fwd: pd.DataFrame, start: str | None = None,
                  end: str | None = None, horizon: int = 5, min_names: int = 8,
                  n_boot: int = 2000) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Returns (per-arm summary, paired differences vs the first arm)."""
    summaries, ic_series = [], {}
    for name, daily in arms.items():
        d = daily.copy()
        d["date"] = pd.to_datetime(d["date"])
        df = d.merge(fwd, on=["date", "ticker"], how="inner").dropna(subset=["fwd_return"])
        if start:
            df = df[df["date"] >= pd.Timestamp(start)]
        if end:
            df = df[df["date"] <= pd.Timestamp(end)]
        for scope, sub in (("all cells", df), ("news days", df[df["has_news"] == 1])):
            ic = _daily_ic(sub, min_names)
            ic_series[(name, scope)] = ic
            lo, hi = block_bootstrap_ci(ic.values, horizon, n_boot)
            summaries.append({
                "arm": name, "scope": scope, "cells": len(sub),
                "pct_cells_with_news": round(100 * df["has_news"].mean(), 1),
                "dates_used": len(ic),
                "mean_IC": ic.mean() if len(ic) else np.nan,
                "ci95_low": lo, "ci95_high": hi,
                "pooled_spearman": (sub["sentiment_score"].rank().corr(sub["fwd_return"].rank())
                                    if len(sub) > 2 else np.nan)})
    summary = pd.DataFrame(summaries)

    diffs, names = [], list(arms)
    for other in names[1:]:
        for scope in ("all cells", "news days"):
            a, b = ic_series[(names[0], scope)], ic_series[(other, scope)]
            common = a.index.intersection(b.index)
            diff = (b.loc[common] - a.loc[common]).values
            lo, hi = block_bootstrap_ci(diff, horizon, n_boot)
            diffs.append({"comparison": f"{other} - {names[0]}", "scope": scope,
                          "dates": len(common),
                          "mean_IC_diff": diff.mean() if len(diff) else np.nan,
                          "ci95_low": lo, "ci95_high": hi,
                          "ci_excludes_zero": bool(not np.isnan(lo) and (lo > 0 or hi < 0))})
    return summary, pd.DataFrame(diffs)
