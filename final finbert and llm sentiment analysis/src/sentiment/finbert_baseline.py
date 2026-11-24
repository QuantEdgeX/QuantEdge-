"""FinBERT baseline in the same schema as the LLM scorer.

It scores the *same* (article, ticker) candidate pairs and is aggregated by the
same code, so FinBERT-vs-LLM comparisons differ only in the scorer.

Differences from your legacy scripts, on purpose:
  * the positive/negative columns are looked up from ``model.config.id2label``
    instead of hard-coded indices;
  * score = P(positive) - P(negative), the same at training and serving time
    (``historical_sentiment.py`` multiplied by confidence, ``live_finbert.py`` did not);
  * no global mean-centering (it uses future data).
FinBERT is not entity-aware: every ticker of an article gets the article's score,
and relevance is fixed at 1.0 (use ``aggregate --relevance-from`` to weight it
with the LLM's relevance instead).
"""
from __future__ import annotations

import logging
from collections import OrderedDict

from .config import Settings
from .scorer import truncate_text
from .store import Store

logger = logging.getLogger(__name__)

MODEL_NAME = "ProsusAI/finbert"
MODEL_ID = "finbert-prosus"


def prompt_version_for(text_mode: str) -> str:
    return f"baseline-{text_mode}"


class FinBertScorer:
    def __init__(self, batch_size: int = 32, device: str | None = None):
        self.batch_size, self._device_arg = batch_size, device
        self._model = self._tok = None

    def _load(self):
        if self._model is not None:
            return
        import torch
        from transformers import AutoModelForSequenceClassification, AutoTokenizer
        self._torch = torch
        self._tok = AutoTokenizer.from_pretrained(MODEL_NAME)
        self._model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME).eval()
        id2label = {int(k): str(v).lower() for k, v in self._model.config.id2label.items()}
        self._pos = next(i for i, l in id2label.items() if l.startswith("pos"))
        self._neg = next(i for i, l in id2label.items() if l.startswith("neg"))
        self._device = self._device_arg or ("cuda" if torch.cuda.is_available() else "cpu")
        self._model.to(self._device)
        logger.info("FinBERT loaded on %s (labels: %s)", self._device, id2label)

    def score_texts(self, texts: list[str]) -> list[float]:
        self._load()
        out: list[float] = []
        torch = self._torch
        for i in range(0, len(texts), self.batch_size):
            enc = self._tok(texts[i:i + self.batch_size], return_tensors="pt", truncation=True,
                            padding=True, max_length=512).to(self._device)
            with torch.no_grad():
                probs = torch.softmax(self._model(**enc).logits, dim=-1)
            out += (probs[:, self._pos] - probs[:, self._neg]).tolist()
        return out


def _label(score: float) -> str:
    return "positive" if score > 0.2 else "negative" if score < -0.2 else "neutral"


def score_pending_finbert(store: Store, settings: Settings, text_mode: str = "title",
                          scorer=None, limit_pairs: int | None = None,
                          chunk_articles: int = 256) -> dict:
    """``scorer`` needs ``score_texts(list[str]) -> list[float]`` (injectable for tests)."""
    scorer = scorer or FinBertScorer()
    pv = prompt_version_for(text_mode)
    pairs = store.pending_pairs(MODEL_ID, pv, limit=limit_pairs)
    pending: "OrderedDict[str, list[str]]" = OrderedDict()
    for aid, tk in pairs:
        pending.setdefault(aid, []).append(tk)
    ids = list(pending)
    logger.info("FinBERT: %d pairs / %d articles pending (%s)", len(pairs), len(ids), pv)
    done = 0
    for i in range(0, len(ids), chunk_articles):
        chunk = ids[i:i + chunk_articles]
        arts = store.get_articles(chunk)
        texts = []
        for aid in chunk:
            a = arts[aid]
            t = a["title"] or ""
            if text_mode == "title_body":
                t = f"{t}. {truncate_text(a['body'] or '', 1200)}"
            texts.append(t)
        scores = scorer.score_texts(texts)
        rows = []
        for aid, s in zip(chunk, scores):
            for tk in pending[aid]:
                rows.append({"article_id": aid, "ticker": tk, "model_id": MODEL_ID,
                             "prompt_version": pv, "status": "ok", "sentiment": float(s),
                             "relevance": 1.0, "label": _label(s)})
        store.save_scores(rows)
        done += len(rows)
    return {"pairs_scored": done, "articles": len(ids)}
