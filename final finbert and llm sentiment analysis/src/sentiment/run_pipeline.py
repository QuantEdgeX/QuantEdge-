"""Command-line entry point for the LLM sentiment pipeline.

Run from the repository root:  python -m src.sentiment.run_pipeline <command> ...
See src/sentiment/README.md for the full workflow.
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from .aggregate import aggregate_daily, coverage_report
from .config import Settings, load_settings, setup_logging
from .entities import EntityMatcher
from .evaluate_signal import evaluate_arms, forward_returns
from .ingest import ingest_news
from .market_time import trading_days_from_prices
from .news import fmns
from .scorer import LLMScorer, RunAborted, Task, truncate_text
from .store import Store
from .universe import UNIVERSE

logger = logging.getLogger("sentiment.cli")

PREPARED_NAME = "fmns_subset.csv"


# ---------------------------------------------------------------------
def get_tickers(settings: Settings) -> list[str]:
    if settings.stock_data_path.exists():
        return sorted(pd.read_csv(settings.stock_data_path, usecols=["Ticker"])["Ticker"].unique())
    logger.warning("%s not found; using the built-in 48-ticker universe", settings.stock_data_path)
    return sorted(UNIVERSE)


def llm_identity(settings: Settings) -> str:
    if settings.llm_provider == "mock":
        from .llm.mock import MockLLM
        return MockLLM.model_id
    return settings.llm_model


def build_client(settings: Settings):
    if settings.llm_provider == "mock":
        from .llm.mock import MockLLM
        logger.warning("Using the MOCK LLM (keyword heuristic) - for offline testing only.")
        return MockLLM()
    if settings.llm_provider == "gemini":
        from .llm.gemini import GeminiClient
        return GeminiClient(settings.gemini_api_key(), settings.llm_model,
                            settings.request_timeout_seconds, settings.thinking_budget)
    raise ValueError(f"Unknown LLM_PROVIDER {settings.llm_provider!r} (use gemini or mock)")


def daily_path(settings: Settings, arm: str) -> Path:
    return settings.data_dir / f"daily_sentiment_{arm}.csv"


# ---- commands -------------------------------------------------------
def _subsets(a) -> list[str]:
    names = a.subsets.split(",") if getattr(a, "subsets", None) else list(fmns.DEFAULT_SUBSETS)
    return fmns.validate_subsets([n.strip() for n in names if n.strip()],
                                 getattr(a, "allow_fnspid_subset", False))


def _window(a, s: Settings) -> tuple[str, str]:
    """NEWS_START/NEWS_END (or --start/--end) override; otherwise selected_period.json."""
    start = getattr(a, "start", None) or s.news_start
    end = getattr(a, "end", None) or s.news_end
    if start and end:
        return start, end
    period = fmns.load_period(s.period_path)
    if not period:
        sys.exit("No news window: run `scan` then `select-period` first, or set NEWS_START / NEWS_END.")
    return start or period["start"], end or period["end"]


def cmd_probe(a, s: Settings):
    """Verify access + streaming and show a small sample of each subset (schema, dates, metadata)."""
    universe = set(get_tickers(s))
    try:
        remote = fmns.list_remote_subsets()
        print(f"Subsets on the Hub ({len(remote)}):")
        for name, info in sorted(remote.items()):
            print(f"  {name:32s} {info['files']:3d} shard(s)  {info['bytes'] / 1e6:9.1f} MB")
        index = fmns.AliasIndex()
        report = {}
        for sub in _subsets(a):
            rows = list(fmns.iter_subset(sub, None, a.n))
            tagged = fmns.SUBSET_INFO.get(sub, {}).get("tickers", False)
            sc = fmns.scan_rows(rows, sub, universe, None if tagged else index)
            sc.pop("monthly", None)
            report[sub] = sc
            print(f"\n== {sub}: {sc['rows']} sampled rows, dates {sc['min_date']} .. {sc['max_date']}")
            print(f"   precision={sc['precision']} url={sc['with_url']} publisher={sc['with_publisher']} "
                  f"ticker-meta={sc['with_ticker_meta']} universe-hits={sc['with_universe_ticker']} "
                  f"bad_date={sc['bad_date']} bad_extra={sc['bad_extra']} empty_text={sc['empty_text']}")
            for r in rows[:2]:
                title, _ = fmns.split_text(r.get("text"))
                print(f"   e.g. {r.get('date')}  {title[:90]!r}  extra_keys={sorted((fmns.parse_extra(r.get('extra_fields')) or {}))[:8]}")
        s.data_dir.mkdir(parents=True, exist_ok=True)
        (s.data_dir / "fmns_probe.json").write_text(json.dumps(report, indent=1, default=str))
        print(f"\nSaved {s.data_dir / 'fmns_probe.json'}. Samples are heads of each subset: use `scan` for real coverage.")
    except fmns.AccessError as e:
        sys.exit(str(e))


def cmd_scan(a, s: Settings):
    """Stream the chosen subsets (date + metadata only where possible) and record real coverage."""
    try:
        res = fmns.scan_subsets(s.data_dir / "fmns_scan", set(get_tickers(s)), _subsets(a),
                                max_rows=a.max_rows, force=a.force)
    except fmns.AccessError as e:
        sys.exit(str(e))
    for name, sc in res.items():
        print(f"{name:32s} rows={sc['rows']:>9,} {sc['min_date']}..{sc['max_date']} "
              f"universe-hits={sc['with_universe_ticker']:>8,} precision={sc['precision']}")
        print(f"{'':32s} by year: {sc['by_year']}")


def cmd_select_period(a, s: Settings):
    subsets = _subsets(a)
    scans = fmns.scan_subsets(s.data_dir / "fmns_scan", set(get_tickers(s)), subsets, max_rows=None,
                              force=False, row_source=lambda *_: (_ for _ in ()).throw(
                                  SystemExit("Run `scan` first (no saved scan for a requested subset).")))
    period = fmns.select_period(fmns.merge_monthly(scans.values()), get_tickers(s), years=s.period_years,
                                lo=a.lo, hi=a.hi, min_month_articles=a.min_month_articles)
    fmns.save_period(s.period_path, period, subsets)
    print(json.dumps({k: v for k, v in period.items() if k != "per_ticker"}, indent=2))
    weak = sorted(period["per_ticker"].items(), key=lambda kv: kv[1]["month_cov"])[:8]
    print("Weakest tickers (month_cov / day_cov):", [(t, v["month_cov"], v["day_cov"]) for t, v in weak])
    print(f"Saved {s.period_path}")


def cmd_prepare_news(a, s: Settings):
    start, end = _window(a, s)
    out = s.raw_dir / PREPARED_NAME
    try:
        stats = fmns.prepare_fmns(out, set(get_tickers(s)), start, end, _subsets(a),
                                  scan_titles=not a.no_scan_titles, max_rows=a.max_rows, force=a.force)
    except fmns.AccessError as e:
        sys.exit(str(e))
    print(json.dumps(stats, indent=2))
    print(f"Wrote {out}")


def cmd_ingest(a, s: Settings):
    prepared = Path(a.prepared) if a.prepared else s.raw_dir / PREPARED_NAME
    days = trading_days_from_prices(s.stock_data_path)
    store = Store(s.db_path)
    stats = ingest_news(prepared, store, s, days, EntityMatcher())
    print(json.dumps(stats, indent=2, default=str))
    print(json.dumps(store.stats(), indent=2))


def cmd_coverage(a, s: Settings):
    store = Store(s.db_path)
    print("Cache:", json.dumps(store.stats()))
    arts = pd.read_sql_query(
        "SELECT published_at, time_known, trade_date FROM articles WHERE dup_of IS NULL", store.conn)
    if arts.empty:
        print("No articles ingested.")
        return
    arts["published_at"] = pd.to_datetime(arts["published_at"], utc=True)
    print(f"\nTime known (not date-only/midnight): {100 * arts['time_known'].mean():.1f}% of articles")
    print(f"Unassignable to a trading day (dropped): {int(arts['trade_date'].isna().sum())}")
    print("\nArticles by year:\n", arts["published_at"].dt.year.value_counts().sort_index().to_string())
    hrs = arts[arts["time_known"] == 1]["published_at"].dt.hour.value_counts().sort_index()
    print("\nPublish hour (UTC) histogram, timed articles only:\n", hrs.to_string())
    cand = store.candidates_df()
    per_ticker = cand.groupby("ticker")["article_id"].nunique().reindex(get_tickers(s)).fillna(0).astype(int)
    print(f"\nCandidate articles per ticker (min {per_ticker.min()}, median {int(per_ticker.median())}, "
          f"max {per_ticker.max()}):")
    print(per_ticker.sort_values().to_string())
    zero = per_ticker[per_ticker == 0].index.tolist()
    if zero:
        print(f"\nWARNING: no candidate articles at all for: {zero}")


def cmd_dry_run(a, s: Settings):
    store = Store(s.db_path)
    mid = llm_identity(s)
    pairs = store.pending_pairs(mid, s.prompt_version, retry_failed=a.retry_failed)
    arts = len({p[0] for p in pairs})
    batches = -(-arts // s.batch_size)
    rows = store.conn.execute(
        "SELECT SUM(MIN(LENGTH(COALESCE(body,'')), ?) + LENGTH(COALESCE(title,''))) FROM articles a "
        "WHERE a.article_id IN (SELECT article_id FROM candidates)", (s.max_article_chars,)).fetchone()[0] or 0
    pending_ids = {p[0] for p in pairs}
    est_in_tokens = int(rows * (len(pending_ids) / max(1, store.stats()["articles_canonical"])) / 4) \
        + batches * 700
    print(f"Model: {mid}   prompt: {s.prompt_version}")
    print(f"Pending pairs: {len(pairs):,}   articles: {arts:,}   requests (batch={s.batch_size}): {batches:,}")
    print(f"Rough input tokens (chars/4 + prompt overhead): ~{est_in_tokens:,}")
    if s.requests_per_minute > 0:
        print(f"At {s.requests_per_minute} req/min (rate cap): >= {batches / s.requests_per_minute:,.0f} min "
              f"of request spacing, {s.max_workers} worker(s)")
    else:
        print("Client-side rate limit disabled (LLM_REQUESTS_PER_MINUTE=0).")
    print("Multiply tokens by your model's current per-token price before running `score`.")


def cmd_smoke_test(a, s: Settings):
    store = Store(s.db_path)
    client = build_client(s)
    scorer = LLMScorer(client, store, s)
    pairs = store.pending_pairs(client.model_id, s.prompt_version, limit=a.n * 4)
    by_art: dict[str, list[str]] = {}
    for aid, tk in pairs:
        by_art.setdefault(aid, []).append(tk)
    ids = list(by_art)[: a.n]
    arts = store.get_articles(ids)
    tasks = [Task(i, by_art[i], arts[i]["title"], truncate_text(arts[i]["body"], s.max_article_chars),
                  arts[i]["published_at"]) for i in ids]
    rows = scorer.score_tasks(tasks)
    for t in tasks:
        print(f"\n[{t.article_id}] {t.title[:110]}")
        for r in rows:
            if r["article_id"] == t.article_id:
                print(f"   {r['ticker']:5s} {r['status']:6s} sent={r['sentiment']} rel={r['relevance']} "
                      f"{r['label']} {r['error'] or ''}")
    print("\nSmoke test only: nothing was saved to the cache.")


def cmd_score(a, s: Settings):
    store = Store(s.db_path)
    scorer = LLMScorer(build_client(s), store, s)
    try:
        res = scorer.run(retry_failed=a.retry_failed, limit_pairs=a.limit_pairs)
    except RunAborted as e:
        logger.error("%s", e)
        sys.exit(2)
    print(json.dumps(res, indent=2))


def cmd_finbert(a, s: Settings):
    from .finbert_baseline import score_pending_finbert
    print(json.dumps(score_pending_finbert(Store(s.db_path), s, a.text, limit_pairs=a.limit_pairs)))


def _scorer_identity(a, s: Settings) -> tuple[str, str]:
    if a.scorer == "finbert":
        from .finbert_baseline import MODEL_ID, prompt_version_for
        return MODEL_ID, prompt_version_for(a.finbert_text)
    return llm_identity(s), s.prompt_version


def _restrict_days(a, s: Settings, days):
    """Limit the output calendar to the selected news window (unless --full-calendar)."""
    if getattr(a, "full_calendar", False):
        return days
    try:
        start, end = _window(a, s)
    except SystemExit:
        return days
    d = pd.to_datetime(pd.Series(np.asarray(days).astype("datetime64[D]")))
    inside = d[(d >= pd.Timestamp(start)) & (d <= pd.Timestamp(end))]
    if inside.empty:
        sys.exit(f"{s.stock_data_path} has no trading days between {start} and {end}.")
    if d.min() > pd.Timestamp(start) or d.max() < pd.Timestamp(end):
        logger.warning("Price calendar (%s..%s) does not fully cover the news window %s..%s",
                       d.min().date(), d.max().date(), start, end)
    return inside.values.astype("datetime64[D]")


def cmd_aggregate(a, s: Settings):
    store = Store(s.db_path)
    model_id, pv = _scorer_identity(a, s)
    days = trading_days_from_prices(s.stock_data_path)
    scores = store.scored_pairs_df(model_id, pv)
    if scores.empty:
        sys.exit(f"No scores for model={model_id} prompt={pv}. Run the scoring step first.")
    override = None
    if a.relevance_from:
        override = store.scored_pairs_df(llm_identity(s), s.prompt_version)
        override = override[override["status"] == "ok"][["article_id", "ticker", "relevance"]]
    days = _restrict_days(a, s, days)
    daily = aggregate_daily(scores, store.candidates_df(), days, get_tickers(s), s.min_relevance, override)
    out = Path(a.out) if a.out else daily_path(s, a.scorer)
    out.parent.mkdir(parents=True, exist_ok=True)
    daily.to_csv(out, index=False)
    print(f"Wrote {out}  ({len(daily):,} rows, {daily['ticker'].nunique()} tickers)")
    print(f"Cells with news: {100 * daily['has_news'].mean():.1f}%   "
          f"cells with unscored candidates: {int((daily['n_unscored'] > 0).sum())}")
    print("\nLowest-coverage tickers:\n", coverage_report(daily).head(10).to_string())


def cmd_export_articles(a, s: Settings):
    store = Store(s.db_path)
    model_id, pv = _scorer_identity(a, s)
    df = store.scored_pairs_df(model_id, pv)
    out = Path(a.out) if a.out else s.export_dir / f"article_scores_{a.scorer}.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out, index=False)
    print(f"Wrote {out} ({len(df):,} rows)")


def cmd_evaluate(a, s: Settings):
    arms = {}
    for spec in a.arm:
        name, _, path = spec.partition("=")
        arms[name] = pd.read_csv(path)
    fwd = forward_returns(s.stock_data_path, a.horizon)
    summary, diffs = evaluate_arms(arms, fwd, a.start, a.end, a.horizon, n_boot=a.n_boot)
    pd.set_option("display.width", 200)
    print(summary.round(4).to_string(index=False))
    if not diffs.empty:
        print("\nPaired difference vs first arm (block bootstrap):")
        print(diffs.round(4).to_string(index=False))
    if a.out:
        summary.to_csv(a.out, index=False)


# ---- argparse -------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m src.sentiment.run_pipeline",
                                description="LLM sentiment pipeline for QuantEdge")
    p.add_argument("--log-level", default=None)
    sub = p.add_subparsers(dest="command", required=True)

    def news_args(c, with_window=True):
        c.add_argument("--subsets", default=None,
                       help=f"comma-separated subsets (default: {','.join(fmns.DEFAULT_SUBSETS)})")
        c.add_argument("--allow-fnspid-subset", action="store_true",
                       help="permit the re-hosted FNSPID subset (excluded by default)")
        c.add_argument("--max-rows", type=int, default=None, help="cap rows per subset (trial runs)")
        c.add_argument("--force", action="store_true", help="ignore per-subset checkpoints")
        if with_window:
            c.add_argument("--start", default=None)
            c.add_argument("--end", default=None)

    c = sub.add_parser("probe", help="verify Hugging Face access/streaming; sample each subset")
    c.add_argument("--n", type=int, default=200, help="rows to sample per subset")
    c.add_argument("--subsets", default=None)
    c.add_argument("--allow-fnspid-subset", action="store_true")
    c.set_defaults(fn=cmd_probe)

    c = sub.add_parser("scan", help="stream subsets once; record real date/ticker coverage (checkpointed)")
    news_args(c, with_window=False)
    c.set_defaults(fn=cmd_scan)

    c = sub.add_parser("select-period", help="choose the best continuous 6-year window from the scan")
    c.add_argument("--subsets", default=None)
    c.add_argument("--allow-fnspid-subset", action="store_true")
    c.add_argument("--lo", default="2017-01")
    c.add_argument("--hi", default="2026-12")
    c.add_argument("--min-month-articles", type=int, default=3)
    c.set_defaults(fn=cmd_select_period)

    c = sub.add_parser("prepare-news", help="stream Hugging Face subsets into a filtered, normalised CSV")
    news_args(c)
    c.add_argument("--no-scan-titles", action="store_true", help="keep only dataset-tagged rows")
    c.set_defaults(fn=cmd_prepare_news)

    c = sub.add_parser("ingest", help="dedup, assign trading days, match entities, fill cache")
    c.add_argument("--prepared", default=None)
    c.set_defaults(fn=cmd_ingest)

    sub.add_parser("coverage", help="data-quality / coverage report").set_defaults(fn=cmd_coverage)

    c = sub.add_parser("dry-run", help="count pending work and estimate size; no API calls")
    c.add_argument("--retry-failed", action="store_true")
    c.set_defaults(fn=cmd_dry_run)

    c = sub.add_parser("smoke-test", help="score a few pending articles, print, save nothing")
    c.add_argument("--n", type=int, default=3)
    c.set_defaults(fn=cmd_smoke_test)

    c = sub.add_parser("score", help="LLM-score pending (article, ticker) pairs")
    c.add_argument("--limit-pairs", type=int, default=None)
    c.add_argument("--retry-failed", action="store_true")
    c.set_defaults(fn=cmd_score)

    c = sub.add_parser("finbert", help="FinBERT baseline on the same pairs")
    c.add_argument("--text", choices=["title", "title_body"], default="title")
    c.add_argument("--limit-pairs", type=int, default=None)
    c.set_defaults(fn=cmd_finbert)

    for name, fn, h in (("aggregate", cmd_aggregate, "build the daily ticker-level dataset"),
                        ("export-articles", cmd_export_articles, "article-level results to CSV")):
        c = sub.add_parser(name, help=h)
        c.add_argument("--scorer", choices=["llm", "finbert"], default="llm")
        c.add_argument("--finbert-text", choices=["title", "title_body"], default="title")
        c.add_argument("--out", default=None)
        if name == "aggregate":
            c.add_argument("--full-calendar", action="store_true",
                           help="output every trading day in stock_data.csv, not only the news window")
            c.add_argument("--start", default=None)
            c.add_argument("--end", default=None)
            c.add_argument("--relevance-from", choices=["llm"], default=None,
                           help="weight by the LLM's relevance (ablation for the FinBERT arm)")
        c.set_defaults(fn=fn)

    c = sub.add_parser("evaluate", help="model-free IC comparison of daily files")
    c.add_argument("--arm", action="append", required=True, metavar="NAME=CSV",
                   help="repeat; the first arm is the reference")
    c.add_argument("--start", default=None)
    c.add_argument("--end", default=None)
    c.add_argument("--horizon", type=int, default=5)
    c.add_argument("--n-boot", type=int, default=2000)
    c.add_argument("--out", default=None)
    c.set_defaults(fn=cmd_evaluate)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    settings = load_settings()
    setup_logging(args.log_level, settings.data_dir / "pipeline.log")
    args.fn(args, settings)


if __name__ == "__main__":
    main()
