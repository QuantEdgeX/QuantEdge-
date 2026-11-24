"""Offline tests for the financial-news-multisource adapter (no network, no `datasets`)."""
import json
import tempfile
import unittest
from pathlib import Path

import pandas as pd

from src.sentiment.aggregate import aggregate_daily
from src.sentiment.ingest import ingest_news
from src.sentiment.llm.mock import MockLLM
from src.sentiment.market_time import trading_days_from_prices
from src.sentiment.news import fmns
from src.sentiment.scorer import LLMScorer
from src.sentiment.store import Store

from .helpers import make_prices, test_settings


def row(date, text, **extra):
    return {"date": date, "text": text, "extra_fields": json.dumps(extra)}


ROWS = [
    # minute-level, tagged (GOOG -> GOOGL alias handled elsewhere); 10:00 ET
    row("2023-01-10T15:00:00Z", "Apple beats earnings\n\nApple Inc reported record profit.",
        time_precision="minute", stocks=["AAPL"], url="http://a/1", publisher="Yahoo", authors=["Jo"]),
    # day-level: date is midnight UTC; date_trading (next open) must NOT become the publication time
    row("2023-01-10T00:00:00Z", "Microsoft wins cloud deal\n\nMicrosoft Azure growth continues strongly.",
        time_precision="day", date_trading="2023-01-11T14:30:00Z", url="http://a/2"),
    # minute precision but exactly midnight -> treated as unknown time
    row("2023-01-12T00:00:00Z", "JPMorgan raises guidance on lending\n\nJPMorgan said so.",
        time_precision="minute", stocks=["JPM"]),
    # tagged with a ticker outside the universe and no company mention -> dropped
    row("2023-01-10T15:00:00Z", "Some small cap moves\n\nNothing relevant here at all.",
        time_precision="minute", stocks=["ZZZZ"]),
    # outside window
    row("2016-05-01T15:00:00Z", "Apple old news item\n\nApple Inc old.", time_precision="minute", stocks=["AAPL"]),
    # bad date / malformed extra / too short
    row("garbage", "Apple bad date row\n\nApple Inc.", time_precision="minute"),
    {"date": "2023-01-11T15:00:00Z", "text": "Apple Inc malformed extras row\n\nApple Inc body", "extra_fields": "{not json"},
    row("2023-01-11T15:00:00Z", "hi", time_precision="minute"),
]
UNIVERSE = {"AAPL", "MSFT", "JPM", "V"}


class ParseTests(unittest.TestCase):
    def test_normalise_fields_and_time_rules(self):
        df, st = fmns.normalise_rows(ROWS, "yahoo_finance_felixdrinkall")
        self.assertEqual(st["rows_bad_date"], 1)
        self.assertEqual(st["rows_bad_extra"], 1)
        self.assertEqual(st["rows_short_text"], 1)
        self.assertEqual(st["minute_rows_at_midnight"], 1)
        by = df.set_index("title")
        a = by.loc["Apple beats earnings"]
        self.assertEqual((a.time_known, a.url, a.publisher, a.author), (1, "http://a/1", "Yahoo", "Jo"))
        self.assertEqual(a.body, "Apple Inc reported record profit.")
        m = by.loc["Microsoft wins cloud deal"]
        self.assertEqual(m.time_known, 0)
        self.assertEqual(m.published_at, "2023-01-10T00:00:00Z")      # NOT date_trading
        self.assertEqual(by.loc["JPMorgan raises guidance on lending"].time_known, 0)

    def test_ticker_extraction_and_aliases(self):
        self.assertEqual(fmns.extract_tickers({"stocks": ["goog", "$AAPL", "FB", "AAPL"]}), ["GOOGL", "AAPL", "META"])
        self.assertEqual(fmns.extract_tickers({"mentioned_companies": "MSFT, V"}), ["MSFT", "V"])
        self.assertEqual(fmns.extract_tickers(None), [])

    def test_fnspid_subset_refused_by_default(self):
        with self.assertRaises(ValueError):
            fmns.validate_subsets(["fnspid_news"])
        self.assertEqual(fmns.validate_subsets(["fnspid_news"], allow_fnspid_subset=True), ["fnspid_news"])


class StreamTests(unittest.TestCase):
    def test_retry_resumes_without_duplicates(self):
        data = [{"i": i} for i in range(10)]
        calls = {"n": 0}

        class DS:
            def __init__(self, skip, fail):
                self.skip_n, self.fail = skip, fail

            def skip(self, n):
                return DS(n, self.fail)

            def __iter__(self):
                for k, r in enumerate(data[self.skip_n:]):
                    if self.fail and k == 4:
                        raise ConnectionError("boom")
                    yield r

        def loader(subset, cols, token):
            calls["n"] += 1
            return DS(0, fail=calls["n"] == 1)

        got = list(fmns.iter_subset("x", loader=loader, sleep=lambda _s: None, token="t"))
        self.assertEqual([r["i"] for r in got], list(range(10)))
        self.assertEqual(calls["n"], 2)

    def test_access_error_is_not_retried(self):
        calls = {"n": 0}

        def loader(subset, cols, token):
            calls["n"] += 1
            raise PermissionError("403 Client Error: gated dataset, you must be authenticated")

        with self.assertRaises(fmns.AccessError):
            list(fmns.iter_subset("x", loader=loader, sleep=lambda _s: None, token="t"))
        self.assertEqual(calls["n"], 1)

    def test_max_rows(self):
        class DS:
            def skip(self, n):
                return self

            def __iter__(self):
                return iter({"i": i} for i in range(100))

        got = list(fmns.iter_subset("x", max_rows=7, loader=lambda *a: DS(), token="t"))
        self.assertEqual(len(got), 7)


class PrepareAndPipelineTests(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.tmp = Path(self._t.name)

    def tearDown(self):
        self._t.cleanup()

    def _prepare(self, **kw):
        self.calls = []

        def src(subset, cols, m):
            self.calls.append(subset)
            return iter(ROWS)

        return fmns.prepare_fmns(self.tmp / "raw" / "out.csv", UNIVERSE, "2023-01-02", "2023-04-28",
                                 ["yahoo_finance_felixdrinkall"], row_source=src, chunk_rows=3, **kw)

    def test_prepare_filters_and_checkpoints(self):
        st = self._prepare()
        got = pd.read_csv(self.tmp / "raw" / "out.csv", keep_default_na=False)
        self.assertEqual(sorted(got.title), ["Apple Inc malformed extras row", "Apple beats earnings",
                                             "JPMorgan raises guidance on lending", "Microsoft wins cloud deal"])
        tags = got.set_index("title")["symbol_tag"]
        self.assertEqual((tags["Apple beats earnings"], tags["Microsoft wins cloud deal"]), ("AAPL", ""))
        self.assertEqual(list(got.columns[:9]), ["article_id", "published_at", "time_known", "title", "body",
                                                 "url", "publisher", "author", "symbol_tag"])
        self.assertEqual(st["subsets"]["yahoo_finance_felixdrinkall"]["kept_by_text_only"], 2)  # MSFT + malformed-extras row
        self._prepare()                                   # second run: checkpoint, no streaming
        self.assertEqual(self.calls, [])
        self._prepare(force=True)
        self.assertEqual(self.calls, ["yahoo_finance_felixdrinkall"])

    def test_end_to_end_no_lookahead_and_schema(self):
        self._prepare()
        make_prices(self.tmp / "stock_data.csv", ["AAPL", "JPM", "MSFT", "V"])
        s = test_settings(self.tmp)
        days = trading_days_from_prices(s.stock_data_path)
        store = Store(":memory:")
        ingest_news(self.tmp / "raw" / "out.csv", store, s, days)
        LLMScorer(MockLLM(), store, s, sleep=lambda _x: None).run()
        daily = aggregate_daily(store.scored_pairs_df(MockLLM.model_id, "v1"), store.candidates_df(), days,
                                ["AAPL", "JPM", "MSFT", "V"], s.min_relevance)
        self.assertEqual(list(daily.columns[:4]), ["date", "ticker", "sentiment_score", "article_count"])
        self.assertTrue(daily.sentiment_score.between(-1, 1).all())
        d = daily.set_index(["date", "ticker"])
        # 10:00 ET Tuesday, timed -> same trading day
        self.assertEqual(d.loc[("2023-01-10", "AAPL"), "article_count"], 1)
        # day-level Microsoft item dated 2023-01-10 -> only usable the NEXT trading day
        self.assertEqual(d.loc[("2023-01-10", "MSFT"), "article_count"], 0)
        self.assertEqual(d.loc[("2023-01-11", "MSFT"), "article_count"], 1)
        # midnight-stamped JPM (2023-01-12) -> 2023-01-13
        self.assertEqual(d.loc[("2023-01-12", "JPM"), "article_count"], 0)
        self.assertEqual(d.loc[("2023-01-13", "JPM"), "article_count"], 1)


class ScanAndPeriodTests(unittest.TestCase):
    def test_scan_rows_counts(self):
        sc = fmns.scan_rows([r for r in ROWS], "yahoo_finance_felixdrinkall", UNIVERSE, fmns.AliasIndex())
        self.assertEqual(sc["rows"], len(ROWS))
        self.assertEqual(sc["bad_date"], 1)
        self.assertEqual(sc["monthly"]["2023-01"]["AAPL"]["n"], 2)       # 1 tagged + 1 by name
        self.assertEqual(sc["monthly"]["2023-01"]["MSFT"]["days"], [10])     # found by name
        self.assertEqual(sc["precision"]["day"], 1)

    def _monthly(self, first, last, tickers, n=5):
        return {ym: {t: {"n": n, "days": list(range(1, 22))} for t in tickers}
                for ym in fmns._month_range(first, last)}

    def test_prefers_most_recent_when_equal(self):
        tk = ["AAPL", "MSFT"]
        res = fmns.select_period(self._monthly("2017-01", "2023-12", tk), tk)
        self.assertEqual((res["start"], res["end"]), ("2018-01-01", "2023-12-31"))   # latest 72 months
        self.assertEqual(res["tickers_meeting_floor"], 2)

    def test_avoids_sparse_recent_year(self):
        tk = ["AAPL", "MSFT"]
        m = self._monthly("2017-01", "2024-12", tk)
        for ym in fmns._month_range("2023-07", "2024-12"):   # sparse recent 18 months
            m[ym] = {"AAPL": {"n": 1, "days": [3]}}
        res = fmns.select_period(m, tk)
        self.assertLessEqual(res["end"], "2023-08-31")   # stays out of the sparse tail (within tolerance)

    def test_not_enough_data(self):
        with self.assertRaises(ValueError):
            fmns.select_period(self._monthly("2020-01", "2023-12", ["AAPL"]), ["AAPL"])


if __name__ == "__main__":
    unittest.main()
