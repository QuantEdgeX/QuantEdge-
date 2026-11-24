import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

import numpy as np
import pandas as pd

from src.sentiment.aggregate import aggregate_daily
from src.sentiment.entities import EntityMatcher
from src.sentiment.evaluate_signal import evaluate_arms, forward_returns
from src.sentiment.finbert_baseline import MODEL_ID as FB_ID, score_pending_finbert
from src.sentiment.ingest import ingest_news
from src.sentiment.llm.mock import MockLLM
from src.sentiment.market_time import trading_days_from_prices
from src.sentiment.scorer import LLMScorer, RunAborted
from src.sentiment.store import Store

from .helpers import make_news_csv, make_prices, test_settings

TICKERS = ["AAPL", "JPM", "MSFT", "V"]

NEWS = [
    # Tue 10:00 ET (15:00Z): usable Tue 2023-01-10
    ("Apple beats earnings, shares surge", "Apple Inc reported record profit.", "2023-01-10T15:00:00Z", "AAPL"),
    # same story re-posted 2h later by another outlet -> duplicate
    ("Apple Beats Earnings, Shares Surge!", "Apple Inc reported record profit.", "2023-01-10T17:00:00Z", "AAPL"),
    # Tue 17:00 ET (22:00Z): AFTER cutoff -> Wed 2023-01-11
    ("Apple faces lawsuit over iPhone", "A lawsuit targets Apple Inc.", "2023-01-10T22:00:00Z", "AAPL"),
    # Saturday -> Monday 2023-01-16 (Mon 16th is a business day in bdate_range)
    ("Microsoft wins big cloud contract", "Microsoft Azure growth continues.", "2023-01-14T15:00:00Z", "MSFT"),
    # provider tag with no mention of the company anywhere -> never sent to the LLM
    ("Markets drift sideways", "Nothing about any company.", "2023-01-10T15:30:00Z", "JPM"),
    # two companies in one article
    ("JPMorgan and Microsoft partner on payments", "Shares of both rose.", "2023-01-12T15:00:00Z", "JPM"),
]


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        make_prices(self.tmp / "stock_data.csv", TICKERS)
        make_news_csv(self.tmp / "news.csv", NEWS)
        self.s = test_settings(self.tmp)
        self.store = Store(":memory:")
        self.days = trading_days_from_prices(self.s.stock_data_path)
        self.stats = ingest_news(self.tmp / "news.csv", self.store, self.s, self.days)

    def tearDown(self):
        self._tmp.cleanup()

    def score(self, client=None, **kw):
        sc = LLMScorer(client or MockLLM(), self.store, self.s, sleep=lambda _s: None, **kw)
        return sc, sc.run()

    def daily(self, model_id=MockLLM.model_id, pv="v1"):
        return aggregate_daily(self.store.scored_pairs_df(model_id, pv), self.store.candidates_df(),
                               self.days, TICKERS, self.s.min_relevance)


class IngestTests(Base):
    def test_dedup_dropping_and_candidates(self):
        self.assertEqual(self.stats["duplicates"], 1)
        pairs = {(r.ticker) for r in self.store.candidates_df().itertuples()}
        self.assertEqual(pairs, {"AAPL", "MSFT", "JPM"})
        # the tag-only JPM article ("Markets drift sideways") produced no candidate
        c = self.store.candidates_df()
        self.assertEqual(len(c[c.ticker == "JPM"]), 1)
        self.assertEqual(self.store.stats()["articles_duplicates"], 1)


class ScorerTests(Base):
    def test_scores_everything_and_cache_prevents_rework(self):
        client = MockLLM()
        sc, res = self.score(client)
        n_pairs = len(self.store.candidates_df())
        self.assertEqual((res["ok"], res["failed"]), (n_pairs, 0))
        calls = client.calls
        sc2, res2 = self.score(client)            # second run: nothing pending
        self.assertEqual((client.calls, res2["pairs_pending"]), (calls, 0))

    def test_new_prompt_version_rescoring_keeps_old_results(self):
        self.score()
        s2 = replace(self.s, prompt_version="v2")
        sc = LLMScorer(MockLLM(), self.store, s2, sleep=lambda _s: None)
        self.assertEqual(sc.run()["ok"], len(self.store.candidates_df()))
        self.assertEqual(len(self.store.scored_pairs_df(MockLLM.model_id, "v1")),
                         len(self.store.scored_pairs_df(MockLLM.model_id, "v2")))

    def test_rate_limits_and_transient_errors_are_retried(self):
        client = MockLLM(rate_limit_first=2, transient_first=3)
        sc, res = self.score(client)
        self.assertEqual(res["failed"], 0)
        self.assertEqual(res["rate_limited"], 2)
        self.assertGreaterEqual(res["retries"], 3)

    def test_garbage_json_is_repaired_with_hint(self):
        client = MockLLM(garbage_first=1)
        sc, res = self.score(client)
        self.assertEqual(res["failed"], 0)
        self.assertIn("could not be used", client.prompts[1])

    def test_out_of_range_values_are_rejected_then_repaired(self):
        client = MockLLM(bad_range_first=1)
        sc, res = self.score(client)
        self.assertEqual(res["failed"], 0)
        self.assertTrue((self.store.scored_pairs_df(client.model_id, "v1")["sentiment"].abs() <= 1).all())

    def test_persistent_omission_is_failed_not_zero_and_retryable(self):
        client = MockLLM(drop_ticker="MSFT")
        sc, res = self.score(client)
        df = self.store.scored_pairs_df(client.model_id, "v1")
        failed = df[df.status == "failed"]
        self.assertTrue(len(failed) >= 1 and set(failed.ticker) == {"MSFT"})
        self.assertTrue(failed["sentiment"].isna().all())            # never a fake 0.0
        self.assertEqual(len(self.store.pending_pairs(client.model_id, "v1")), 0)
        self.assertEqual(len(self.store.pending_pairs(client.model_id, "v1", retry_failed=True)), len(failed))
        d = self.daily(client.model_id)
        self.assertGreater(d["n_unscored"].sum(), 0)                  # surfaced in the output

    def test_fatal_error_aborts_without_writing_failures(self):
        with self.assertRaises(RunAborted):
            self.score(MockLLM(fatal=True))
        self.assertEqual(len(self.store.scored_pairs_df(MockLLM.model_id, "v1")), 0)

    def test_total_api_outage_aborts_after_repeated_failures(self):
        # many articles + permanent outage -> circuit breaker
        make_news_csv(self.tmp / "many.csv", [(f"Apple beats estimate number {i} today", "Apple Inc",
                                                f"2023-02-{1 + i % 27:02d}T15:00:00Z", "AAPL") for i in range(40)])
        store = Store(":memory:")
        ingest_news(self.tmp / "many.csv", store, self.s, self.days)
        sc = LLMScorer(MockLLM(transient_first=10**6), store, replace(self.s, batch_size=2, max_retries=1),
                       sleep=lambda _s: None)
        with self.assertRaises(RunAborted):
            sc.run()

    def test_concurrent_workers_match_sequential(self):
        self.score()
        seq = self.store.scored_pairs_df(MockLLM.model_id, "v1").set_index(["article_id", "ticker"]).sort_index()
        store2 = Store(":memory:")
        ingest_news(self.tmp / "news.csv", store2, self.s, self.days)
        LLMScorer(MockLLM(), store2, replace(self.s, max_workers=3, batch_size=1), sleep=lambda _s: None).run()
        par = store2.scored_pairs_df(MockLLM.model_id, "v1").set_index(["article_id", "ticker"]).sort_index()
        pd.testing.assert_frame_equal(seq[["sentiment", "relevance", "label"]], par[["sentiment", "relevance", "label"]])


class AggregationTests(Base):
    def test_no_future_information_and_calendar_mapping(self):
        self.score()
        d = self.daily().set_index(["ticker", "date"])
        aapl = d.loc["AAPL"]
        self.assertEqual(aapl.loc["2023-01-10", "article_count"], 1)    # the duplicate is not counted
        self.assertGreater(aapl.loc["2023-01-10", "sentiment_score"], 0)  # "beats ... surge"
        # the 17:00 ET lawsuit article must NOT appear on Jan 10 (after cutoff) but on Jan 11
        self.assertEqual(aapl.loc["2023-01-11", "article_count"], 1)
        self.assertLess(aapl.loc["2023-01-11", "sentiment_score"], 0)
        # Saturday MSFT article lands on Monday Jan 16, not on the prior Friday
        self.assertEqual(d.loc[("MSFT", "2023-01-13"), "article_count"], 0)
        self.assertEqual(d.loc[("MSFT", "2023-01-16"), "article_count"], 1)

    def test_missing_news_is_explicit_and_grid_is_complete(self):
        self.score()
        d = self.daily()
        self.assertEqual(len(d), len(self.days) * len(TICKERS))
        quiet = d[(d.ticker == "V")]
        self.assertTrue((quiet.sentiment_score == 0).all() and (quiet.has_news == 0).all()
                        and (quiet.article_count == 0).all())
        self.assertEqual(list(d.columns[:4]), ["date", "ticker", "sentiment_score", "article_count"])
        self.assertTrue(d.sentiment_score.between(-1, 1).all())

    def test_relevance_weighted_mean_and_threshold(self):
        scores = pd.DataFrame({
            "article_id": ["a", "b", "c"], "ticker": ["AAPL"] * 3, "status": ["ok"] * 3,
            "sentiment": [1.0, -1.0, 1.0], "relevance": [0.9, 0.3, 0.1],
            "trade_date": ["2023-01-10"] * 3})
        cands = scores[["article_id", "ticker", "trade_date"]]
        d = aggregate_daily(scores, cands, self.days, ["AAPL"], min_relevance=0.3)
        row = d[d.date == "2023-01-10"].iloc[0]
        self.assertAlmostEqual(row.sentiment_score, (0.9 * 1 + 0.3 * -1) / 1.2)
        self.assertEqual(row.article_count, 2)          # c is below the relevance threshold
        self.assertEqual(row.n_unscored, 0)

    def test_finbert_arm_shares_pairs_and_schema(self):
        class Fake:
            def score_texts(self, texts):
                return [0.5 if "beats" in t.lower() else -0.1 for t in texts]
        score_pending_finbert(self.store, self.s, scorer=Fake())
        d = aggregate_daily(self.store.scored_pairs_df(FB_ID, "baseline-title"),
                            self.store.candidates_df(), self.days, TICKERS, self.s.min_relevance)
        self.assertEqual(list(d.columns[:4]), ["date", "ticker", "sentiment_score", "article_count"])
        self.assertEqual(d.article_count.sum(), len(self.store.candidates_df()))


class FeatureMergeTests(unittest.TestCase):
    def test_ticker_level_merge_and_legacy_path(self):
        from src.features.build_features_enhanced import create_enhanced_features
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            make_prices(tmp / "p.csv", ["AAPL", "MSFT"], start="2022-01-03", end="2022-12-30")
            px = pd.read_csv(tmp / "p.csv")
            days = sorted(px.Date.unique())
            pick = days[100]
            tl = pd.DataFrame({"date": [pick, pick], "ticker": ["AAPL", "MSFT"],
                               "sentiment_score": [0.4, -0.3], "article_count": [3, 2]})
            out = create_enhanced_features(px.copy(), tl)
            row = out[out.Date == pd.Timestamp(pick)].set_index("Ticker")
            self.assertAlmostEqual(row.loc["AAPL", "sentiment_score"], 0.4)
            self.assertAlmostEqual(row.loc["MSFT", "sentiment_score"], -0.3)
            self.assertEqual(row.loc["AAPL", "article_count"], 3)
            self.assertEqual(out[out.Date != pd.Timestamp(pick)]["sentiment_score"].abs().sum(), 0)
            legacy = pd.DataFrame({"date": [pick], "sentiment_score": [0.2]})
            out2 = create_enhanced_features(px.copy(), legacy)
            r2 = out2[out2.Date == pd.Timestamp(pick)]
            self.assertTrue((r2.sentiment_score == 0.2).all() and len(r2) == 2)  # broadcast, as before
            self.assertNotIn("article_count", out2.columns)


class EvaluateTests(unittest.TestCase):
    def test_detects_real_signal_and_not_noise(self):
        with tempfile.TemporaryDirectory() as t:
            tmp = Path(t)
            tickers = [f"T{i}" for i in range(20)]
            make_prices(tmp / "p.csv", tickers, start="2022-01-03", end="2023-06-30", seed=5)
            fwd = forward_returns(tmp / "p.csv", 5).dropna()
            rng = np.random.default_rng(0)
            base = fwd.copy()
            base["article_count"], base["has_news"] = 1, 1
            sig, noise = base.copy(), base.copy()
            sig["sentiment_score"] = sig["fwd_return"] + rng.normal(0, 0.01, len(sig))   # peeks at the future
            noise["sentiment_score"] = rng.normal(0, 1, len(noise))
            keep = ["date", "ticker", "sentiment_score", "article_count", "has_news"]
            summary, diffs = evaluate_arms({"noise": noise[keep], "oracle": sig[keep]}, fwd, n_boot=300)
            m = summary.set_index(["arm", "scope"])
            self.assertGreater(m.loc[("oracle", "all cells"), "mean_IC"], 0.5)
            lo, hi = m.loc[("noise", "all cells"), ["ci95_low", "ci95_high"]]
            self.assertTrue(lo < 0 < hi)
            self.assertTrue(bool(diffs.iloc[0]["ci_excludes_zero"]))


if __name__ == "__main__":
    unittest.main()
