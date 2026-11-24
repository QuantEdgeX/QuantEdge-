"""LLM scoring of pending (article, ticker) pairs.

Flow per batch of articles
--------------------------
1. One request covers up to ``batch_size`` articles and every candidate
   ticker of each article (request batching).
2. Transient / rate-limit errors retry with exponential backoff + jitter,
   honouring server retry hints; a client-side limiter caps requests/minute.
3. The response is validated strictly. Pairs that came back valid are saved
   immediately; only the invalid or missing ones are re-asked, with a repair
   hint.
4. Pairs still unresolved are re-sent one article per request. If they fail
   again they are stored with status='failed' (never as a fake 0.0) and are
   picked up by ``--retry-failed``.
5. Results are committed after every batch, so an interrupted run resumes
   exactly where it stopped and already-scored pairs are never re-sent.
"""
from __future__ import annotations

import logging
import re
import time
from collections import OrderedDict
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from dataclasses import dataclass

from .config import Settings
from .llm.base import LLMClient, PermanentLLMError, RateLimitError, TransientLLMError
from .prompts import SYSTEM_PROMPT, build_user_prompt
from .ratelimit import RateLimiter, backoff_delay
from .store import Store
from .universe import UNIVERSE
from .validation import ResponseFormatError, validate_response

logger = logging.getLogger(__name__)

FORMAT_ATTEMPTS = 2
ABORT_AFTER_CONSECUTIVE_API_FAILURES = 5


class RunAborted(RuntimeError):
    """Raised when continuing would only burn quota (auth error, API outage)."""


@dataclass
class Task:
    article_id: str
    tickers: list[str]
    title: str
    text: str
    published: str


def truncate_text(text: str, limit: int) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    if len(text) <= limit:
        return text
    cut = text[:limit]
    return cut[: cut.rfind(" ")] if " " in cut[-40:] else cut


class LLMScorer:
    def __init__(self, client: LLMClient, store: Store, settings: Settings,
                 limiter: RateLimiter | None = None, sleep=time.sleep):
        self.client, self.store, self.settings = client, store, settings
        self.model_id = client.model_id
        self.prompt_version = settings.prompt_version
        self.limiter = limiter or RateLimiter(settings.requests_per_minute)
        self._sleep = sleep
        self.counters = {"requests": 0, "retries": 0, "rate_limited": 0,
                         "format_errors": 0, "ok": 0, "failed": 0}

    # ------------------------------------------------------------------
    def _items(self, tasks: list[Task]) -> list[dict]:
        items = []
        for t in tasks:
            item = {"article_id": t.article_id, "title": t.title,
                    "text": t.text,
                    "companies": [{"ticker": tk, "name": UNIVERSE[tk].name} for tk in t.tickers]}
            if self.settings.include_date_in_prompt:
                item["published"] = t.published[:10]
            items.append(item)
        return items

    def _call(self, user: str, n_pairs: int) -> str:
        max_tokens = 400 + 120 * n_pairs
        last: Exception | None = None
        for attempt in range(self.settings.max_retries + 1):
            self.limiter.acquire()
            self.counters["requests"] += 1
            try:
                return self.client.generate_json(SYSTEM_PROMPT, user, max_tokens)
            except RateLimitError as e:
                self.counters["rate_limited"] += 1
                last, hint = e, e.retry_after
            except TransientLLMError as e:
                last, hint = e, None
            if attempt >= self.settings.max_retries:
                break
            delay = backoff_delay(attempt, self.settings.retry_base_seconds,
                                  self.settings.retry_max_seconds, hint)
            self.counters["retries"] += 1
            logger.warning("LLM call failed (%s); retry %d/%d in %.1fs",
                           type(last).__name__, attempt + 1, self.settings.max_retries, delay)
            self._sleep(delay)
        raise TransientLLMError(f"gave up after {self.settings.max_retries} retries: {last}")

    def _row(self, aid, ticker, status, rec=None, error=None) -> dict:
        row = {"article_id": aid, "ticker": ticker, "model_id": self.model_id,
               "prompt_version": self.prompt_version, "status": status, "error": error}
        if rec:
            row.update(sentiment=rec["sentiment"], relevance=rec["relevance"], label=rec["label"])
        return row

    # ------------------------------------------------------------------
    def score_tasks(self, tasks: list[Task], allow_split: bool = True) -> list[dict]:
        """Score tasks; returns one result row per (article, ticker). Thread-safe."""
        rows: dict[tuple[str, str], dict] = {}
        remaining = list(tasks)
        hint: str | None = None
        last_error = "unknown"
        api_failure = False

        for attempt in range(FORMAT_ATTEMPTS):
            if not remaining:
                break
            expected = {t.article_id: t.tickers for t in remaining}
            n_pairs = sum(len(v) for v in expected.values())
            try:
                raw = self._call(build_user_prompt(self._items(remaining), hint), n_pairs)
                ok, errors = validate_response(raw, expected)
                api_failure = False
            except ResponseFormatError as e:
                self.counters["format_errors"] += 1
                last_error, hint = f"format: {e}", str(e)
                continue
            except TransientLLMError as e:
                last_error, api_failure = f"api: {e}", True
                break
            except PermanentLLMError as e:
                if e.fatal:
                    raise RunAborted(f"fatal LLM error: {e}") from e
                last_error, api_failure = f"api: {e}", True
                break

            for (aid, tk), rec in ok.items():
                rows[(aid, tk)] = self._row(aid, tk, "ok", rec)
            if errors:
                self.counters["format_errors"] += len(errors)
                hint = "; ".join(f"{a}/{t}: {m}" for (a, t), m in list(errors.items())[:5])
                last_error = f"validation: {hint}"
            bad = {a for (a, _t) in errors}
            remaining = [Task(t.article_id, [tk for tk in t.tickers if (t.article_id, tk) in errors],
                              t.title, t.text, t.published)
                         for t in remaining if t.article_id in bad]

        if remaining:
            if allow_split and (len(tasks) > 1 or len(remaining) > 1) and not api_failure:
                for t in remaining:  # re-ask article by article
                    for r in self.score_tasks([t], allow_split=False):
                        rows[(r["article_id"], r["ticker"])] = r
            else:
                for t in remaining:
                    for tk in t.tickers:
                        rows[(t.article_id, tk)] = self._row(t.article_id, tk, "failed",
                                                             error=last_error[:500])
        return list(rows.values())

    # ------------------------------------------------------------------
    def _load_tasks(self, ids: list[str], pending: "OrderedDict[str, list[str]]") -> list[Task]:
        arts = self.store.get_articles(ids)
        limit = self.settings.max_article_chars
        return [Task(i, pending[i], arts[i]["title"] or "", truncate_text(arts[i]["body"] or "", limit),
                     arts[i]["published_at"]) for i in ids]

    def run(self, retry_failed: bool = False, limit_pairs: int | None = None,
            progress_every: int = 20) -> dict:
        pairs = self.store.pending_pairs(self.model_id, self.prompt_version,
                                         retry_failed=retry_failed, limit=limit_pairs)
        pending: "OrderedDict[str, list[str]]" = OrderedDict()
        for aid, tk in pairs:
            pending.setdefault(aid, []).append(tk)
        ids = list(pending)
        n_batches = (len(ids) + self.settings.batch_size - 1) // self.settings.batch_size
        logger.info("Scoring %d pairs / %d articles in %d batches with %s (prompt %s)",
                    len(pairs), len(ids), n_batches, self.model_id, self.prompt_version)
        if not ids:
            logger.info("Nothing to do: every candidate pair is already scored.")
            return dict(self.counters, batches=0, pairs_pending=0)

        batches = [ids[i:i + self.settings.batch_size] for i in range(0, len(ids), self.settings.batch_size)]
        started, done, consecutive_api_fail = time.time(), 0, 0

        def handle(rows: list[dict]) -> None:
            nonlocal consecutive_api_fail
            self.store.save_scores(rows)
            n_ok = sum(r["status"] == "ok" for r in rows)
            n_bad = len(rows) - n_ok
            self.counters["ok"] += n_ok
            self.counters["failed"] += n_bad
            api_only = n_bad and n_ok == 0 and all(str(r["error"]).startswith("api:") for r in rows)
            consecutive_api_fail = consecutive_api_fail + 1 if api_only else 0
            if consecutive_api_fail >= ABORT_AFTER_CONSECUTIVE_API_FAILURES:
                raise RunAborted(f"{consecutive_api_fail} consecutive batches failed at the API "
                                 "level; stopping. Progress is saved; re-run to resume.")

        def log_progress() -> None:
            el = time.time() - started
            eta = el / done * (len(batches) - done) if done else 0
            logger.info("Batch %d/%d | ok=%d failed=%d requests=%d retries=%d | elapsed %.0fs, ETA %.0fs",
                        done, len(batches), self.counters["ok"], self.counters["failed"],
                        self.counters["requests"], self.counters["retries"], el, eta)

        workers = max(1, self.settings.max_workers)
        if workers == 1:
            for b in batches:
                handle(self.score_tasks(self._load_tasks(b, pending)))
                done += 1
                if done % progress_every == 0 or done == len(batches):
                    log_progress()
        else:
            with ThreadPoolExecutor(max_workers=workers) as ex:
                it, inflight = iter(batches), set()
                try:
                    while True:
                        while len(inflight) < workers * 2:
                            b = next(it, None)
                            if b is None:
                                break
                            inflight.add(ex.submit(self.score_tasks, self._load_tasks(b, pending)))
                        if not inflight:
                            break
                        finished, inflight = wait(inflight, return_when=FIRST_COMPLETED)
                        for f in finished:
                            handle(f.result())
                            done += 1
                            if done % progress_every == 0 or done == len(batches):
                                log_progress()
                except BaseException:
                    for f in inflight:
                        f.cancel()
                    raise

        logger.info("Scoring finished: %s", self.counters)
        return dict(self.counters, batches=len(batches), pairs_pending=len(pairs))
