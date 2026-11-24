"""Adapter for the Hugging Face dataset ``Brianferrell787/financial-news-multisource``.

Replaces the former FNSPID adapter. The corpus is stored as Parquet shards, one
folder per subset (``data/<subset>/*.parquet``), with the minimal schema::

    date          ISO-8601 UTC string (midnight UTC when only the day is known)
    text          title + "\\n\\n" + body
    extra_fields  JSON string: url / publisher / stocks / time_precision / date_trading ...

Access: the dataset is GATED (log in + accept the terms on the dataset page) and
licensed for **non-commercial research / education only**. Original content
belongs to the original publishers: do not redistribute article text, cite the
corpus and the original sources, and remove items on rightsholder request.

Leakage rules implemented here
------------------------------
* ``published_at`` is always the dataset's top-level ``date``. ``extra_fields.date_trading``
  (the *next NYSE open* the corpus derives for day-level rows) is never used as a
  publication time: it is a trading anchor, not an observation time.
* ``time_known`` is 1 only for ``time_precision == "minute"`` rows whose time is not
  exactly midnight UTC. Everything else is day-level and the pipeline's existing
  market-time logic treats it as end-of-day (usable from the NEXT trading day).
* Rows without a parseable date are dropped and counted, never guessed.

The module has two layers: a thin streaming layer (``iter_subset``; the only code that
touches ``datasets``) and pure row-processing functions that work on any iterable of
dicts, so everything except the network call is unit-testable offline.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Callable, Iterable, Iterator

import pandas as pd

from ..dedup import normalize_title
from ..entities import _compile, normalize_text
from ..universe import COMPANIES
from .base import ARTICLE_COLUMNS

logger = logging.getLogger(__name__)

DATASET_ID = "Brianferrell787/financial-news-multisource"
MAX_BODY_CHARS = 8000
SCAN_TEXT_CHARS = 2000          # how much of the body is searched for company names
PRE_WINDOW_DAYS = 7             # weekend/holiday news before the window still reaches its first days
MIN_TEXT_CHARS = 15

# Extra audit columns written after ARTICLE_COLUMNS (ignored by ingest).
PREPARED_COLUMNS = ARTICLE_COLUMNS + ["subset", "time_precision"]

# ---------------------------------------------------------------------------
# Subset catalogue (from the dataset card; verified for real with `probe`/`scan`)
# ---------------------------------------------------------------------------
# needs_text_scan: the subset carries no ticker metadata, so companies are found by
# name in the text. columns: parquet columns that must be read.
SUBSET_INFO: dict[str, dict] = {
    "yahoo_finance_felixdrinkall": {"tickers": True, "note": "Yahoo Finance JSON 2017-2023, minute-level, tickers"},
    "us_financial_news_2018_jeet": {"tickers": False, "note": "multi-publisher US financial news, ~2018, minute-level"},
    "cnbc_headlines": {"tickers": False, "note": "CNBC headlines + preview, minute-level"},
    "finsen_us_2007_2023": {"tickers": False, "note": "FinSen US, 2007-2023, day-level"},
    "yahoo_finance_articles": {"tickers": True, "note": "Yahoo Finance feed 2025, day-level, tickers"},
    # opt-in (noisy / huge / not company-specific):
    "american_news_jonasbecker": {"tickers": False, "note": "general US news crawl, noisy"},
    "all_the_news_2": {"tickers": False, "note": "general news 2016-2019, noisy"},
    "headlines_10sites_2007_2022": {"tickers": False, "note": "4.5M headlines, mostly non-financial, huge"},
    "frontpage_news": {"tickers": False, "note": "multi-outlet headlines 2015-2020, day-level"},
    "sentarl_combined": {"tickers": True, "note": "20 assets, mostly pre-2017"},
    "benzinga_6000stocks": {"tickers": True, "note": "analyst-rating headlines, mostly pre-2017"},
    "reddit_finance_sp500": {"tickers": False, "note": "social posts, not news"},
}
DEFAULT_SUBSETS = ("yahoo_finance_felixdrinkall", "us_financial_news_2018_jeet", "cnbc_headlines",
                   "finsen_us_2007_2023", "yahoo_finance_articles")
# The corpus re-hosts FNSPID as `fnspid_news`. The project replaces FNSPID entirely, so it
# is refused unless explicitly allowed.
FNSPID_SUBSET = "fnspid_news"

# Dataset tickers -> universe tickers (share classes / renames). Evidence is still
# required from the text before anything reaches the LLM.
TICKER_ALIASES = {"GOOG": "GOOGL", "FB": "META"}

_URL_KEYS = ("url", "link", "web_url")
_PUBLISHER_KEYS = ("publisher", "source_norm", "news_outlet", "publication", "outlet",
                   "source_domain", "source")
_AUTHOR_KEYS = ("author", "authors", "byline_norm", "byline")
_TICKER_KEYS = ("stocks", "tickers", "symbols", "mentioned_companies")


class AccessError(RuntimeError):
    """The dataset is gated or the token is missing / not authorised."""


# ---------------------------------------------------------------------------
# Streaming layer (the only code that touches `datasets` / `huggingface_hub`)
# ---------------------------------------------------------------------------
def hf_token() -> str | None:
    return (os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
            or os.environ.get("HUGGINGFACE_TOKEN") or None)


_ACCESS_HINT = (
    f"Cannot read {DATASET_ID}. The dataset is gated: (1) open https://huggingface.co/datasets/{DATASET_ID}, "
    "log in and accept the research/education-only terms; (2) create a read token at "
    "https://huggingface.co/settings/tokens and set HF_TOKEN in your environment/.env "
    "(or run `huggingface-cli login`).")


def _looks_like_access_error(exc: BaseException) -> bool:
    text = f"{type(exc).__name__} {exc}".lower()
    return any(k in text for k in ("gated", "401", "403", "unauthorized", "forbidden",
                                   "access to this dataset", "must be authenticated", "not authorized"))


def default_loader(subset: str, columns: list[str] | None, token: str | None):
    """Open one subset as a streaming ``IterableDataset`` (no local download of the corpus)."""
    try:
        from datasets import load_dataset
    except ImportError as e:  # pragma: no cover - environment dependent
        raise RuntimeError("The `datasets` package is required: pip install -r requirements-sentiment.txt") from e
    kwargs = dict(path=DATASET_ID, data_files=f"data/{subset}/*.parquet", split="train",
                  streaming=True, token=token or True)
    if columns:
        try:  # column projection: reads only the needed Parquet columns
            return load_dataset(columns=list(columns), **kwargs)
        except TypeError:
            logger.warning("this `datasets` version rejected column projection; reading all columns")
    return load_dataset(**kwargs)


def iter_subset(subset: str, columns: list[str] | None = None, max_rows: int | None = None,
                token: str | None = None, retries: int = 5, loader: Callable = default_loader,
                sleep: Callable[[float], None] = time.sleep) -> Iterator[dict]:
    """Stream rows of one subset with retry + resume.

    On a transient error the stream is reopened and the rows already yielded are skipped,
    so no row is processed twice. Access (gated / auth) errors are raised immediately.
    """
    token = token if token is not None else hf_token()
    seen, attempt = 0, 0
    while True:
        try:
            ds = loader(subset, columns, token)
            if seen:
                ds = ds.skip(seen)
            for row in ds:
                yield row
                seen += 1
                if max_rows is not None and seen >= max_rows:
                    return
            return
        except Exception as e:  # noqa: BLE001 - classified below
            if _looks_like_access_error(e):
                raise AccessError(f"{_ACCESS_HINT}\nOriginal error: {type(e).__name__}: {e}") from e
            attempt += 1
            if attempt > retries:
                raise
            wait = min(2.0 ** attempt, 60.0)
            logger.warning("stream %s failed after %d rows (%s: %s); retry %d/%d in %.0fs",
                           subset, seen, type(e).__name__, str(e)[:160], attempt, retries, wait)
            sleep(wait)


def list_remote_subsets(token: str | None = None) -> dict[str, dict]:
    """{subset: {"files": n, "bytes": total}} from the Hub file listing (no data is downloaded)."""
    try:
        from huggingface_hub import HfApi
    except ImportError as e:  # pragma: no cover
        raise RuntimeError("`huggingface_hub` is required (installed with `datasets`).") from e
    try:
        entries = list(HfApi().list_repo_tree(DATASET_ID, path_in_repo="data", recursive=True,
                                              repo_type="dataset", token=token or hf_token() or True))
    except Exception as e:  # noqa: BLE001
        if _looks_like_access_error(e):
            raise AccessError(f"{_ACCESS_HINT}\nOriginal error: {type(e).__name__}: {e}") from e
        raise
    out: dict[str, dict] = defaultdict(lambda: {"files": 0, "bytes": 0})
    for ent in entries:
        parts = str(ent.path).split("/")
        if len(parts) >= 3 and parts[0] == "data" and str(ent.path).endswith(".parquet"):
            out[parts[1]]["files"] += 1
            out[parts[1]]["bytes"] += int(getattr(ent, "size", 0) or 0)
    return dict(out)


# ---------------------------------------------------------------------------
# Row parsing
# ---------------------------------------------------------------------------
def parse_extra(raw: object) -> dict | None:
    """``extra_fields`` JSON string -> dict, or None if missing / malformed."""
    if isinstance(raw, dict):
        return raw
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        val = json.loads(raw)
    except (ValueError, TypeError):
        return None
    return val if isinstance(val, dict) else None


def _first_str(extra: dict, keys: tuple[str, ...]) -> str:
    for k in keys:
        v = extra.get(k)
        if isinstance(v, (list, tuple)):
            v = ", ".join(str(x) for x in v if x)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""


def extract_tickers(extra: dict | None) -> list[str]:
    """Ticker symbols the dataset attached to the row (normalised, de-duplicated, order kept)."""
    if not extra:
        return []
    for k in _TICKER_KEYS:
        v = extra.get(k)
        if isinstance(v, str):
            v = [x for x in re.split(r"[,;|\s]+", v) if x]
        if isinstance(v, (list, tuple)) and v:
            out: list[str] = []
            for t in v:
                t = str(t).strip().upper().lstrip("$")
                t = TICKER_ALIASES.get(t, t)
                if t and t not in out:
                    out.append(t)
            if out:
                return out
    return []


def split_text(text: object) -> tuple[str, str]:
    """Canonical text is ``title\\n\\nbody``; headline-only rows have no body."""
    s = "" if text is None or (isinstance(text, float) and pd.isna(text)) else str(text)
    s = s.strip()
    if "\n\n" in s:
        title, body = s.split("\n\n", 1)
        return title.strip(), body.strip()[:MAX_BODY_CHARS]
    return s[:300].strip(), (s[300:MAX_BODY_CHARS].strip() if len(s) > 300 else "")


def parse_date_fast(value: object) -> tuple[str | None, bool]:
    """(iso_utc_string | None, is_midnight). Accepts ``YYYY-MM-DD[T ]HH:MM:SS[Z]``."""
    if not isinstance(value, str) or len(value) < 10:
        return None, False
    ts = pd.to_datetime(value, utc=True, errors="coerce")
    if pd.isna(ts):
        return None, False
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ"), (ts.hour == 0 and ts.minute == 0 and ts.second == 0)


def make_article_id(url: str, title: str, published_iso: str) -> str:
    key = (url.strip() if url and url.strip() else normalize_title(title)) + "|" + published_iso
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------------------
# Company-name prefilter (for rows without ticker metadata / extra recall)
# ---------------------------------------------------------------------------
class AliasIndex:
    """Strong (unambiguous) company aliases from ``universe.py``; one regex for the
    cheap yes/no prefilter, per-ticker regexes to find *which* companies matched."""

    def __init__(self):
        ci, cs = [], []
        self._per: dict[str, list] = {}
        for c in COMPANIES:
            ci += list(c.strong)
            cs += list(c.strong_cs)
            rx = [r for r in (_compile(c.strong, True), _compile(c.strong_cs, False)) if r is not None]
            if rx:
                self._per[c.ticker] = rx
        self._any = [r for r in (_compile(ci, True), _compile(cs, False)) if r is not None]

    def hit(self, text: str) -> bool:
        return any(r.search(text) for r in self._any)

    def tickers_in(self, text: str) -> set[str]:
        if not self.hit(text):
            return set()
        return {t for t, rxs in self._per.items() if any(r.search(text) for r in rxs)}


def _scan_text(title: str, body: str) -> str:
    return normalize_text(f"{title} {body[:SCAN_TEXT_CHARS]}")


# ---------------------------------------------------------------------------
# Normalisation (rows -> article table)
# ---------------------------------------------------------------------------
def normalise_rows(rows: Iterable[dict], subset: str) -> tuple[pd.DataFrame, dict]:
    """Raw dataset rows -> DataFrame with ARTICLE_COLUMNS + audit columns + ``tickers`` (list).

    No window / universe filtering here. Returns (frame, stats) with counts of rows that
    were dropped for a bad date or empty text.
    """
    recs: list[dict] = []
    st = Counter()
    for r in rows:
        st["rows_read"] += 1
        iso, midnight = parse_date_fast(r.get("date"))
        if iso is None:
            st["rows_bad_date"] += 1
            continue
        extra = parse_extra(r.get("extra_fields"))
        if extra is None:
            st["rows_bad_extra"] += 1
            extra = {}
        title, body = split_text(r.get("text"))
        if len(title) + len(body) < MIN_TEXT_CHARS:
            st["rows_short_text"] += 1
            continue
        precision = str(extra.get("time_precision") or "").lower()
        known = int(precision != "day" and not midnight)
        if precision == "minute" and midnight:
            st["minute_rows_at_midnight"] += 1   # midnight stamp: treated as day-level
        url = _first_str(extra, _URL_KEYS)
        recs.append({
            "article_id": make_article_id(url, title, iso),
            "published_at": iso, "time_known": known, "title": title, "body": body,
            "url": url, "publisher": _first_str(extra, _PUBLISHER_KEYS),
            "author": _first_str(extra, _AUTHOR_KEYS), "symbol_tag": "",
            "subset": subset, "time_precision": precision or "unknown",
            "tickers": extract_tickers(extra),
        })
    df = pd.DataFrame(recs, columns=ARTICLE_COLUMNS + ["subset", "time_precision", "tickers"])
    return df, dict(st)


def select_and_expand(df: pd.DataFrame, universe: set[str], start: str, end: str,
                      index: AliasIndex | None, scan_titles: bool = True) -> tuple[pd.DataFrame, dict]:
    """Keep articles in the window that concern the universe, one output row per tag.

    A row is kept when (a) the dataset tags one of our tickers, or (b) its title / lead
    text names one of our companies by a strong alias (``scan_titles``). Output has one
    row per (article, universe ticker) with ``symbol_tag`` set, plus one tag-less row for
    text-only matches: the same convention the former adapter used, so `ingest` is unchanged.
    """
    st = Counter()
    if df.empty:
        return pd.DataFrame(columns=PREPARED_COLUMNS), dict(st)
    lo = pd.Timestamp(start, tz="UTC") - pd.Timedelta(days=PRE_WINDOW_DAYS)
    hi = pd.Timestamp(end, tz="UTC") + pd.Timedelta(days=1)
    pub = pd.to_datetime(df["published_at"], utc=True)
    df = df[(pub >= lo) & (pub < hi)]
    st["rows_in_window"] = len(df)

    out: list[dict] = []
    for r in df.to_dict("records"):
        uni_tags = [t for t in r["tickers"] if t in universe]
        if r["tickers"]:
            st["rows_with_ticker_meta"] += 1
        base = {k: r[k] for k in PREPARED_COLUMNS}
        if uni_tags:
            st["kept_by_tag"] += 1
            for t in uni_tags:
                out.append({**base, "symbol_tag": t})
        elif scan_titles and index is not None and index.hit(_scan_text(r["title"], r["body"])):
            st["kept_by_text_only"] += 1
            out.append(dict(base))
        elif not r["tickers"]:
            st["no_ticker_no_company_mention"] += 1
        else:
            st["tagged_only_other_tickers"] += 1
    st["rows_out"] = len(out)
    return pd.DataFrame(out, columns=PREPARED_COLUMNS), dict(st)


# ---------------------------------------------------------------------------
# prepare-news (checkpointed per subset)
# ---------------------------------------------------------------------------
def _fingerprint(subset: str, universe: set[str], start: str, end: str, scan_titles: bool,
                 max_rows: int | None) -> str:
    key = json.dumps([subset, sorted(universe), start, end, scan_titles, max_rows, "v1"])
    return hashlib.sha1(key.encode()).hexdigest()[:12]


def validate_subsets(subsets: Iterable[str], allow_fnspid_subset: bool = False) -> list[str]:
    subsets = list(dict.fromkeys(subsets))
    if FNSPID_SUBSET in subsets and not allow_fnspid_subset:
        raise ValueError(f"`{FNSPID_SUBSET}` is the FNSPID corpus re-hosted inside this dataset. The pipeline "
                         "replaces FNSPID, so it is excluded. Pass --allow-fnspid-subset to override.")
    if not subsets:
        raise ValueError("No subsets selected.")
    return subsets


def prepare_fmns(out_path: str | Path, universe: set[str], start: str, end: str,
                 subsets: Iterable[str] = DEFAULT_SUBSETS, scan_titles: bool = True,
                 max_rows: int | None = None, force: bool = False, chunk_rows: int = 20_000,
                 row_source: Callable[[str, list[str] | None, int | None], Iterable[dict]] | None = None) -> dict:
    """Stream the chosen subsets and write one normalised CSV (``ARTICLE_COLUMNS`` + audit columns).

    Each finished subset is checkpointed under ``<out dir>/fmns_parts``; re-running skips
    subsets whose window / universe / options are unchanged (``force`` recomputes).
    ``row_source(subset, columns, max_rows)`` can replace the network stream (tests).
    """
    out_path = Path(out_path)
    parts = out_path.parent / "fmns_parts"
    parts.mkdir(parents=True, exist_ok=True)
    index = AliasIndex() if scan_titles else None
    source = row_source or (lambda s, c, m: iter_subset(s, c, m))
    summary: dict = {"window": [start, end], "subsets": {}}

    for subset in subsets:
        fp = _fingerprint(subset, universe, start, end, scan_titles, max_rows)
        part_csv, part_meta = parts / f"{subset}.csv", parts / f"{subset}.json"
        if not force and part_meta.exists() and part_csv.exists():
            meta = json.loads(part_meta.read_text())
            if meta.get("fingerprint") == fp:
                logger.info("prepare: %s already done (checkpoint) - skipping", subset)
                summary["subsets"][subset] = {**meta["stats"], "checkpoint": True}
                continue
        stats = Counter()
        tmp = part_csv.with_suffix(".csv.tmp")
        if tmp.exists():
            tmp.unlink()
        first, buf = True, []

        def flush():
            nonlocal first, buf
            if not buf:
                return
            df, s1 = normalise_rows(buf, subset)
            kept, s2 = select_and_expand(df, universe, start, end, index, scan_titles)
            stats.update(s1)
            stats.update(s2)
            if not kept.empty:
                kept.to_csv(tmp, mode="a", header=first, index=False)
                first = False
            buf = []

        for row in source(subset, ["date", "text", "extra_fields"], max_rows):
            buf.append(row)
            if len(buf) >= chunk_rows:
                flush()
                logger.info("prepare %s: %s", subset, dict(stats))
        flush()
        if first:
            pd.DataFrame(columns=PREPARED_COLUMNS).to_csv(tmp, index=False)
        os.replace(tmp, part_csv)
        part_meta.write_text(json.dumps({"fingerprint": fp, "stats": dict(stats)}, indent=1))
        summary["subsets"][subset] = dict(stats)
        logger.info("prepare %s done: %s", subset, dict(stats))

    # ---- concatenate parts ------------------------------------------------
    if out_path.exists():
        out_path.unlink()
    first, total = True, 0
    for subset in subsets:
        for chunk in pd.read_csv(parts / f"{subset}.csv", dtype=str, keep_default_na=False, chunksize=50_000):
            chunk.to_csv(out_path, mode="a", header=first, index=False)
            first, total = False, total + len(chunk)
    if first:
        pd.DataFrame(columns=PREPARED_COLUMNS).to_csv(out_path, index=False)
    summary["rows_written"] = total
    return summary


def load_prepared(path: str | Path, usecols: list[str] | None = None, chunksize: int | None = None):
    kwargs = dict(dtype=str, keep_default_na=False)
    if usecols:
        kwargs["usecols"] = usecols
    return pd.read_csv(path, chunksize=chunksize, **kwargs)


# ---------------------------------------------------------------------------
# Coverage scan (what is actually in each subset?)
# ---------------------------------------------------------------------------
def scan_rows(rows: Iterable[dict], subset: str, universe: set[str], index: AliasIndex | None) -> dict:
    """One pass over a subset: date coverage, precision, metadata and per-(month, ticker) counts.

    ``index`` is given for subsets without ticker metadata (company names are searched
    in the text instead). Result is JSON-serialisable and mergeable.
    """
    a = {"subset": subset, "rows": 0, "bad_date": 0, "bad_extra": 0, "empty_text": 0, "min_date": None,
         "max_date": None, "by_year": Counter(), "precision": Counter(), "minute_at_midnight": 0,
         "with_url": 0, "with_publisher": 0, "with_ticker_meta": 0, "with_universe_ticker": 0,
         "text_chars_sum": 0, "text_n": 0}
    monthly: dict[str, dict[str, dict]] = defaultdict(lambda: defaultdict(lambda: {"n": 0, "days": set()}))
    for r in rows:
        a["rows"] += 1
        iso, midnight = parse_date_fast(r.get("date"))
        if iso is None:
            a["bad_date"] += 1
            continue
        extra = parse_extra(r.get("extra_fields"))
        if extra is None:
            a["bad_extra"] += 1
            extra = {}
        day, ym = iso[:10], iso[:7]
        a["min_date"] = day if a["min_date"] is None or day < a["min_date"] else a["min_date"]
        a["max_date"] = day if a["max_date"] is None or day > a["max_date"] else a["max_date"]
        a["by_year"][iso[:4]] += 1
        precision = str(extra.get("time_precision") or "unknown").lower()
        a["precision"][precision] += 1
        if precision == "minute" and midnight:
            a["minute_at_midnight"] += 1
        a["with_url"] += int(bool(_first_str(extra, _URL_KEYS)))
        a["with_publisher"] += int(bool(_first_str(extra, _PUBLISHER_KEYS)))
        tickers = extract_tickers(extra)
        a["with_ticker_meta"] += int(bool(tickers))
        title, body = ("", "")
        if "text" in r:
            title, body = split_text(r.get("text"))
            a["text_chars_sum"] += len(title) + len(body)
            a["text_n"] += 1
            a["empty_text"] += int(len(title) + len(body) < MIN_TEXT_CHARS)
        hit = {t for t in tickers if t in universe}
        if not hit and index is not None and title:
            hit = index.tickers_in(_scan_text(title, body))
        if hit:
            a["with_universe_ticker"] += 1
        for t in hit:
            cell = monthly[ym][t]
            cell["n"] += 1
            cell["days"].add(int(day[8:10]))
    a["by_year"] = dict(sorted(a["by_year"].items()))
    a["precision"] = dict(a["precision"])
    a["monthly"] = {ym: {t: {"n": c["n"], "days": sorted(c["days"])} for t, c in d.items()}
                    for ym, d in sorted(monthly.items())}
    return a


def merge_monthly(scans: Iterable[dict]) -> dict[str, dict[str, dict]]:
    """Union the ``monthly`` tables of several subset scans (counts summed, days unioned)."""
    out: dict[str, dict[str, dict]] = {}
    for sc in scans:
        for ym, d in sc.get("monthly", {}).items():
            for t, c in d.items():
                cell = out.setdefault(ym, {}).setdefault(t, {"n": 0, "days": set()})
                cell["n"] += c["n"]
                cell["days"] |= set(c["days"])
    return {ym: {t: {"n": c["n"], "days": sorted(c["days"])} for t, c in d.items()} for ym, d in out.items()}


# ---------------------------------------------------------------------------
# Six-year window selection
# ---------------------------------------------------------------------------
def _month_range(first: str, last: str) -> list[str]:
    return [p.strftime("%Y-%m") for p in pd.period_range(first, last, freq="M")]


def select_period(monthly: dict, tickers: list[str], years: int = 6, lo: str = "2017-01",
                  hi: str = "2026-12", min_month_articles: int = 3, month_floor: float = 0.5,
                  tolerance: float = 0.02) -> dict:
    """Pick the best continuous ``years``-year window from observed article counts.

    For every window of ``years*12`` consecutive months inside [lo, hi] AND inside the
    months where the scanned subsets actually contain data:

      month_cov[t] = share of months in which ticker t has >= ``min_month_articles`` articles
      day_cov[t]   = distinct days with >=1 article / business days in the window (cap 1)
      n_ok         = number of tickers with month_cov >= ``month_floor``
      score        = mean over tickers of (month_cov + day_cov) / 2

    Best = highest ``n_ok``, then highest ``score``. Among windows with the best ``n_ok`` and a
    score within ``tolerance`` of the best, the MOST RECENT window wins. Counts are
    pre-deduplication tag/name hits, i.e. an optimistic proxy of final coverage.
    """
    n_months = years * 12
    data_months = sorted(ym for ym, d in monthly.items() if sum(c["n"] for c in d.values()) > 0)
    if not data_months:
        raise ValueError("The scan contains no articles for the universe.")
    first, last = max(lo, data_months[0]), min(hi, data_months[-1])
    all_months = _month_range(first, last)
    if len(all_months) < n_months:
        raise ValueError(f"Only {len(all_months)} months of data between {first} and {last}; "
                         f"need {n_months} for a {years}-year window.")

    def window_metrics(months: list[str]) -> dict:
        start, end = pd.Timestamp(months[0] + "-01"), pd.Timestamp(months[-1] + "-01") + pd.offsets.MonthEnd(0)
        n_bdays = max(1, len(pd.bdate_range(start, end)))
        mcov, dcov = {}, {}
        for t in tickers:
            ok_months, days = 0, 0
            for ym in months:
                c = monthly.get(ym, {}).get(t)
                if c and c["n"] >= min_month_articles:
                    ok_months += 1
                if c:
                    y, m = int(ym[:4]), int(ym[5:])
                    days += sum(1 for d in c["days"] if pd.Timestamp(year=y, month=m, day=d).weekday() < 5)
            mcov[t] = ok_months / len(months)
            dcov[t] = min(1.0, days / n_bdays)
        n_ok = sum(1 for t in tickers if mcov[t] >= month_floor)
        score = sum((mcov[t] + dcov[t]) / 2 for t in tickers) / max(1, len(tickers))
        return {"start": start.strftime("%Y-%m-%d"), "end": end.strftime("%Y-%m-%d"), "n_ok": n_ok,
                "score": score, "month_cov": mcov, "day_cov": dcov}

    cands = [window_metrics(all_months[i:i + n_months]) for i in range(len(all_months) - n_months + 1)]
    best_ok = max(c["n_ok"] for c in cands)
    best_score = max(c["score"] for c in cands if c["n_ok"] == best_ok)
    pool = [c for c in cands if c["n_ok"] == best_ok and c["score"] >= best_score - tolerance]
    chosen = max(pool, key=lambda c: c["start"])          # most recent among near-ties
    return {
        "start": chosen["start"], "end": chosen["end"], "years": years,
        "n_tickers": len(tickers), "tickers_meeting_floor": chosen["n_ok"], "score": round(chosen["score"], 4),
        "params": {"lo": lo, "hi": hi, "min_month_articles": min_month_articles,
                   "month_floor": month_floor, "tolerance": tolerance},
        "data_span": [data_months[0], data_months[-1]],
        "per_ticker": {t: {"month_cov": round(chosen["month_cov"][t], 3), "day_cov": round(chosen["day_cov"][t], 3)}
                       for t in tickers},
        "alternatives": sorted(({"start": c["start"], "end": c["end"], "n_ok": c["n_ok"],
                                 "score": round(c["score"], 4)} for c in cands),
                               key=lambda c: (-c["n_ok"], -c["score"]))[:5],
    }


# ---------------------------------------------------------------------------
# Checkpointed scan driver + persisted window selection
# ---------------------------------------------------------------------------
def scan_subsets(scan_dir: str | Path, universe: set[str], subsets: Iterable[str],
                 max_rows: int | None = None, force: bool = False,
                 row_source: Callable[[str, list[str] | None, int | None], Iterable[dict]] | None = None) -> dict[str, dict]:
    """Scan every subset (checkpointed per subset in ``scan_dir``); return {subset: scan}."""
    scan_dir = Path(scan_dir)
    scan_dir.mkdir(parents=True, exist_ok=True)
    source = row_source or (lambda s, c, m: iter_subset(s, c, m))
    out: dict[str, dict] = {}
    for subset in subsets:
        path = scan_dir / f"{subset}.json"
        key = _fingerprint(subset, universe, "", "", False, max_rows)
        if not force and path.exists():
            saved = json.loads(path.read_text())
            if saved.get("_fingerprint") == key:
                logger.info("scan: %s already done (checkpoint)", subset)
                out[subset] = saved
                continue
        tagged = SUBSET_INFO.get(subset, {}).get("tickers", False)
        index = None if tagged else AliasIndex()
        cols = ["date", "extra_fields"] if tagged else ["date", "text", "extra_fields"]
        res = scan_rows(source(subset, cols, max_rows), subset, universe, index)
        res["_fingerprint"] = key
        res["_capped"] = max_rows is not None
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(res))
        os.replace(tmp, path)
        logger.info("scan %s: %d rows, %s..%s, universe hits %d", subset, res["rows"], res["min_date"],
                    res["max_date"], res["with_universe_ticker"])
        out[subset] = res
    return out


def save_period(path: str | Path, period: dict, subsets: Iterable[str]) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({**period, "subsets": list(subsets)}, indent=1))


def load_period(path: str | Path) -> dict | None:
    path = Path(path)
    return json.loads(path.read_text()) if path.exists() else None
