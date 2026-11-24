"""Trading-day assignment with a hard prediction cutoff (no look-ahead).

Rule: an article published at time ``t`` is usable for the *first* trading
day D such that ``t <= D @ cutoff_time`` (America/New_York).

  * published Tue 10:00 ET        -> Tue
  * published Tue 17:30 ET        -> Wed
  * published Fri 20:00 / weekend -> Mon
  * date-only / midnight stamps   -> treated as 23:59:59 ET on that date,
                                     i.e. the next trading day (we cannot
                                     know the article was out in time)

Articles whose assigned trading day is more than ``max_lag_days`` calendar
days after publication (e.g. news from before the first price row) are
dropped rather than attached to a distant day.
"""
from __future__ import annotations

from datetime import time

import numpy as np
import pandas as pd


def trading_days_from_prices(path) -> np.ndarray:
    dates = pd.read_csv(path, usecols=["Date"])["Date"]
    return np.sort(pd.to_datetime(dates).dt.normalize().unique()).astype("datetime64[D]")


def assign_trade_dates(published_utc: pd.Series, time_known: pd.Series,
                       trading_days: np.ndarray, cutoff: time = time(16, 0),
                       tz: str = "America/New_York", max_lag_days: int = 5) -> pd.Series:
    """Return a Series of trade dates (datetime64[ns], NaT if unassignable)."""
    published_utc = pd.to_datetime(published_utc, utc=True)
    et = published_utc.dt.tz_convert(tz)

    known = time_known.astype(bool).values
    # Timed stamps use the New York calendar date. Date-only stamps carry no
    # timezone, so the stamped date itself is used (not shifted by UTC->ET).
    et_date = et.dt.tz_localize(None).dt.normalize().values
    stamped_date = published_utc.dt.tz_localize(None).dt.normalize().values
    local_date = pd.Series(np.where(known, et_date, stamped_date), index=published_utc.index)
    secs = et.dt.hour * 3600 + et.dt.minute * 60 + et.dt.second
    cutoff_secs = cutoff.hour * 3600 + cutoff.minute * 60 + cutoff.second
    after_cutoff = (secs > cutoff_secs) | (~known)

    days = trading_days.astype("datetime64[D]")
    d = local_date.values.astype("datetime64[D]")
    left = np.searchsorted(days, d, side="left")
    right = np.searchsorted(days, d, side="right")

    is_td = np.zeros(len(d), dtype=bool)
    in_range = left < len(days)
    is_td[in_range] = days[left[in_range]] == d[in_range]

    use_same = is_td & ~after_cutoff.values
    idx = np.where(use_same, left, right)
    valid = idx < len(days)
    trade = np.full(len(d), np.datetime64("NaT"), dtype="datetime64[D]")
    trade[valid] = days[idx[valid]]

    lag = (trade - d).astype("timedelta64[D]").astype("float64")
    too_far = np.isnan(lag) | (lag > max_lag_days)
    trade[too_far] = np.datetime64("NaT")
    return pd.Series(pd.to_datetime(trade), index=published_utc.index)
