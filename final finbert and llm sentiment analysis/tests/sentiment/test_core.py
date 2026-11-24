import unittest
from datetime import time

import numpy as np
import pandas as pd

from src.sentiment.dedup import find_duplicates
from src.sentiment.entities import EntityMatcher
from src.sentiment.market_time import assign_trade_dates
from src.sentiment.ratelimit import RateLimiter, backoff_delay
from src.sentiment.universe import UNIVERSE
from src.sentiment.validation import ResponseFormatError, validate_response

TD = pd.bdate_range("2023-01-02", "2023-01-13").values.astype("datetime64[D]")


def bucket(stamps, known=None):
    ts = pd.Series(pd.to_datetime(stamps, utc=True))
    k = pd.Series([True] * len(ts) if known is None else known)
    return assign_trade_dates(ts, k, TD).dt.strftime("%Y-%m-%d").fillna("NaT").tolist()


class MarketTimeTests(unittest.TestCase):
    def test_cutoff_rule(self):
        # 14:00Z = 09:00 ET (Tue) ; 20:59:59Z = 15:59:59 ET (Tue, on time);
        # 21:00:01Z = 16:00:01 ET -> next day
        self.assertEqual(bucket(["2023-01-03 14:00:00", "2023-01-03 20:59:59",
                                 "2023-01-03 21:00:01"]),
                         ["2023-01-03", "2023-01-03", "2023-01-04"])

    def test_weekend_and_evening_roll_to_monday(self):
        self.assertEqual(bucket(["2023-01-06 22:00:00", "2023-01-07 15:00:00", "2023-01-08 15:00:00"]),
                         ["2023-01-09"] * 3)

    def test_date_only_is_conservative(self):
        # stamped Wed 2023-01-04 with no time -> not usable until Thursday
        self.assertEqual(bucket(["2023-01-04 00:00:00"], known=[False]), ["2023-01-05"])

    def test_no_article_is_ever_assigned_to_a_day_before_publication(self):
        rng = np.random.default_rng(1)
        stamps = pd.to_datetime("2023-01-02") + pd.to_timedelta(rng.integers(0, 12 * 86400, 500), unit="s")
        stamps = stamps.tz_localize("UTC")
        out = assign_trade_dates(pd.Series(stamps), pd.Series([True] * 500), TD).dropna()
        et_cutoff = (out.dt.tz_localize("America/New_York") + pd.Timedelta(hours=16)).dt.tz_convert("UTC")
        self.assertTrue((stamps[out.index] <= et_cutoff).all())

    def test_too_old_or_past_calendar_is_dropped(self):
        self.assertEqual(bucket(["2022-12-01 15:00:00", "2023-01-13 22:00:00"]), ["NaT", "NaT"])


class EntityTests(unittest.TestCase):
    m = EntityMatcher()

    def c(self, title, body="", tags=(), ts=None, req=True):
        ev = self.m.evidence(title, body, tags, ts)
        return {t for t, _ in self.m.candidates(ev, req)}

    def test_universe_has_48(self):
        self.assertEqual(len(UNIVERSE), 48)

    def test_bare_tickers_are_never_evidence(self):
        self.assertEqual(self.c("Stocks V, C, MA, GE and KO all rose today"), set())
        self.assertEqual(self.c("V", tags=["V"]), set())

    def test_names_products_and_context(self):
        self.assertIn("AAPL", self.c("New iPhone launch lifts supplier shares"))
        self.assertIn("JPM", self.c("Shares (NYSE: JPM) rose"))
        self.assertIn("NVDA", self.c("Buy $NVDA now"))
        self.assertEqual(self.c("Nvidia and AMD race", ), {"NVDA", "AMD"})

    def test_ambiguous_word_needs_provider_tag(self):
        self.assertEqual(self.c("Visa applications surge"), set())
        self.assertEqual(self.c("Visa applications surge", tags=["V"]), {"V"})  # LLM decides relevance
        self.assertEqual(self.c("An apple a day"), set())

    def test_tag_without_any_mention_is_dropped(self):
        self.assertEqual(self.c("Weather is nice", tags=["JPM"]), set())
        self.assertEqual(self.c("Weather is nice", tags=["JPM"], req=False), {"JPM"})

    def test_other_entity_with_same_name_is_excluded(self):
        self.assertEqual(self.c("Merck KGaA raises outlook", tags=["MRK"]), set())
        self.assertEqual(self.c("Merck & Co wins approval for Keytruda"), {"MRK"})

    def test_rename_dates(self):
        old, new = pd.Timestamp("2020-05-01", tz="UTC"), pd.Timestamp("2022-05-01", tz="UTC")
        self.assertEqual(self.c("Meta beats estimates", tags=["META"], ts=old), set())
        self.assertEqual(self.c("Meta beats estimates", tags=["META"], ts=new), {"META"})
        self.assertEqual(self.c("Facebook shares fall", ts=old), {"META"})


class DedupTests(unittest.TestCase):
    def test_window_and_earliest_wins(self):
        df = pd.DataFrame({
            "article_id": list("abcd"),
            "published_at": pd.to_datetime(["2023-01-03 10:00", "2023-01-03 12:00",
                                            "2023-01-03 13:00", "2023-01-09 10:00"], utc=True),
            "title": ["Apple unveils new iPhone with better camera",
                      "Apple Unveils New iPhone With Better Camera!",
                      "Apple unveils new iPhone with a better camera today",
                      "Apple unveils new iPhone with better camera"],
            "tags": [("AAPL",)] * 4})
        self.assertEqual(find_duplicates(df), {"b": "a", "c": "a"})

    def test_input_order_does_not_matter(self):
        df = pd.DataFrame({
            "article_id": ["late", "early"],
            "published_at": pd.to_datetime(["2023-01-03 12:00", "2023-01-03 09:00"], utc=True),
            "title": ["Fed holds rates steady in surprise move"] * 2, "tags": [("AAPL",)] * 2})
        self.assertEqual(find_duplicates(df), {"late": "early"})


class ValidationTests(unittest.TestCase):
    exp = {"a1": ["AAPL", "MSFT"]}

    def good(self, **over):
        item = {"ticker": "AAPL", "sentiment_score": 0.5, "relevance_score": 0.9,
                "sentiment_label": "positive"}
        return {**item, **over}

    def resp(self, *assessments):
        import json
        return json.dumps({"results": [{"article_id": "a1", "assessments": list(assessments)}]})

    def test_valid_and_fenced(self):
        raw = "```json\n" + self.resp(self.good(), self.good(ticker="MSFT", sentiment_score=-0.4,
                                                              sentiment_label="negative")) + "\n```"
        ok, err = validate_response(raw, self.exp)
        self.assertEqual((len(ok), err), (2, {}))

    def test_rejects_bad_values(self):
        for bad in (self.good(sentiment_score=1.7), self.good(relevance_score=-0.1),
                    self.good(sentiment_score=True), self.good(sentiment_score="0.5"),
                    self.good(sentiment_label="bullish"), self.good(sentiment_label="negative"),
                    self.good(sentiment_score=float("nan"))):
            ok, err = validate_response(self.resp(bad, self.good(ticker="MSFT")), self.exp)
            self.assertIn(("a1", "AAPL"), err, bad)
            self.assertIn(("a1", "MSFT"), ok)

    def test_missing_duplicate_and_unknown(self):
        ok, err = validate_response(self.resp(self.good(), self.good(), self.good(ticker="TSLA")), self.exp)
        self.assertIn("duplicate", err[("a1", "AAPL")])
        self.assertEqual(err[("a1", "MSFT")], "missing from response")
        self.assertEqual(ok, {})

    def test_unparseable_raises(self):
        for raw in ("", "hello", '{"foo": 1}', "[1,2]"):
            with self.assertRaises(ResponseFormatError):
                validate_response(raw, self.exp)


class RateTests(unittest.TestCase):
    def test_backoff_is_bounded_and_honours_hint(self):
        d = [backoff_delay(i, 2.0, 30.0, rng=lambda: 1.0) for i in range(8)]
        self.assertEqual(d[:4], [2.0, 4.0, 8.0, 16.0])
        self.assertTrue(max(d) <= 30.0)
        self.assertGreaterEqual(backoff_delay(0, 2.0, 30.0, retry_after=12.0, rng=lambda: 0.0), 12.0)

    def test_limiter_spaces_requests(self):
        t = {"now": 0.0}
        sleeps = []
        lim = RateLimiter(60, clock=lambda: t["now"], sleep=lambda s: (sleeps.append(s), t.update(now=t["now"] + s)))
        for _ in range(3):
            lim.acquire()
        self.assertEqual(sleeps, [1.0, 1.0])


if __name__ == "__main__":
    unittest.main()
