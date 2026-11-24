import hashlib
from dataclasses import replace
from pathlib import Path

import numpy as np
import pandas as pd

from src.sentiment.config import Settings
from src.sentiment.news.base import ARTICLE_COLUMNS


def make_prices(path: Path, tickers, start="2023-01-02", end="2023-04-28", seed=0):
    rng = np.random.default_rng(seed)
    days = pd.bdate_range(start, end)
    frames = []
    for t in tickers:
        close = 100 * np.exp(np.cumsum(rng.normal(0, 0.01, len(days))))
        frames.append(pd.DataFrame({"Date": days, "Close": close, "High": close * 1.01,
                                    "Low": close * 0.99, "Open": close,
                                    "Volume": rng.integers(1e6, 2e6, len(days)), "Ticker": t}))
    pd.concat(frames).to_csv(path, index=False)


def make_news_csv(path: Path, rows):
    """rows: (title, body, published_utc_iso, tag[, time_known])"""
    recs = []
    for r in rows:
        title, body, pub, tag = r[:4]
        known = r[4] if len(r) > 4 else 1
        aid = hashlib.sha1(f"{title}|{pub}".encode()).hexdigest()[:16]
        recs.append({"article_id": aid, "published_at": pub, "time_known": known, "title": title,
                     "body": body, "url": f"http://x/{aid}", "publisher": "p", "author": "a",
                     "symbol_tag": tag})
    pd.DataFrame(recs, columns=ARTICLE_COLUMNS).to_csv(path, index=False)


def test_settings(tmp: Path, **kw) -> Settings:
    base = Settings(data_dir=tmp / "sent", stock_data_path=tmp / "stock_data.csv",
                    requests_per_minute=0, retry_base_seconds=0.0, retry_max_seconds=0.0,
                    batch_size=3, max_retries=3)
    return replace(base, **kw)
