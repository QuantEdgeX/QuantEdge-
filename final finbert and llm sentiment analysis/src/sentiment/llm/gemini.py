"""Google Gemini client (``google-genai`` SDK: ``pip install google-genai``).

Uses JSON output mode with a response schema and temperature 0. The schema
only *helps* the model; ``validation.py`` still checks every response.

Errors are mapped onto the taxonomy in ``llm/base.py``:
  429                      -> RateLimitError (honours any retry delay in the message)
  5xx / 408 / network      -> TransientLLMError
  401 / 403 / 404          -> PermanentLLMError(fatal=True)  (bad key / model)
  other 4xx, blocked reply -> PermanentLLMError
"""
from __future__ import annotations

import logging
import re

from .base import PermanentLLMError, RateLimitError, TransientLLMError

logger = logging.getLogger(__name__)

RESPONSE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "results": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "article_id": {"type": "STRING"},
                    "assessments": {
                        "type": "ARRAY",
                        "items": {
                            "type": "OBJECT",
                            "properties": {
                                "ticker": {"type": "STRING"},
                                "sentiment_score": {"type": "NUMBER"},
                                "relevance_score": {"type": "NUMBER"},
                                "sentiment_label": {
                                    "type": "STRING",
                                    "enum": ["negative", "neutral", "positive"],
                                },
                            },
                            "required": ["ticker", "sentiment_score", "relevance_score",
                                         "sentiment_label"],
                        },
                    },
                },
                "required": ["article_id", "assessments"],
            },
        }
    },
    "required": ["results"],
}

_RETRY_HINT = re.compile(r"retry(?:Delay)?\"?\s*(?:in|:)?\s*\"?([\d.]+)\s*s", re.IGNORECASE)


def _retry_after(message: str) -> float | None:
    m = _RETRY_HINT.search(message or "")
    return float(m.group(1)) if m else None


class GeminiClient:
    def __init__(self, api_key: str, model: str, timeout_seconds: int = 120,
                 thinking_budget: int | None = None):
        try:
            from google import genai
            from google.genai import types
        except ImportError as e:  # pragma: no cover
            raise RuntimeError("google-genai is not installed. "
                               "Run: pip install -r requirements-sentiment.txt") from e
        self._types = types
        self.model_id = model
        self._thinking_budget = thinking_budget
        try:
            http_options = types.HttpOptions(timeout=int(timeout_seconds * 1000))
            self._client = genai.Client(api_key=api_key, http_options=http_options)
        except Exception:  # older SDKs without HttpOptions(timeout=...)
            self._client = genai.Client(api_key=api_key)

    def _config(self, system: str, max_output_tokens: int):
        t = self._types
        kwargs = dict(system_instruction=system, temperature=0.0,
                      response_mime_type="application/json",
                      max_output_tokens=max_output_tokens)
        try:
            cfg = t.GenerateContentConfig(response_schema=RESPONSE_SCHEMA, **kwargs)
        except Exception:
            logger.warning("SDK rejected response_schema; falling back to JSON mime type only")
            cfg = t.GenerateContentConfig(**kwargs)
        if self._thinking_budget is not None:
            try:
                cfg.thinking_config = t.ThinkingConfig(thinking_budget=self._thinking_budget)
            except Exception:
                logger.warning("thinking_budget not supported by this SDK/model; ignored")
        return cfg

    def generate_json(self, system: str, user: str, max_output_tokens: int) -> str:
        from google.genai import errors as genai_errors

        try:
            resp = self._client.models.generate_content(
                model=self.model_id, contents=user,
                config=self._config(system, max_output_tokens))
        except genai_errors.APIError as e:
            code = getattr(e, "code", None)
            msg = f"{code} {getattr(e, 'status', '')}: {getattr(e, 'message', e)}"
            if code == 429:
                raise RateLimitError(msg, _retry_after(str(e))) from e
            if code in (401, 403, 404):
                raise PermanentLLMError(msg, fatal=True) from e
            if code in (408, 500, 502, 503, 504) or (isinstance(code, int) and code >= 500):
                raise TransientLLMError(msg) from e
            raise PermanentLLMError(msg) from e
        except (TypeError, ValueError, AttributeError, KeyError):
            raise  # programming errors must surface, not be retried
        except Exception as e:  # network-level failures (timeouts, resets)
            raise TransientLLMError(f"{type(e).__name__}: {e}") from e

        feedback = getattr(resp, "prompt_feedback", None)
        if feedback is not None and getattr(feedback, "block_reason", None):
            raise PermanentLLMError(f"prompt blocked: {feedback.block_reason}")
        text = getattr(resp, "text", None)
        if not text:
            reason = None
            try:
                reason = resp.candidates[0].finish_reason
            except Exception:
                pass
            raise TransientLLMError(f"empty response (finish_reason={reason})")
        return text
