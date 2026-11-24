"""LLM client interface and the error taxonomy the scorer relies on."""
from __future__ import annotations

from typing import Protocol


class LLMError(Exception):
    """Base class for provider errors."""


class RateLimitError(LLMError):
    """HTTP 429 / quota exhausted. Retry after a delay."""

    def __init__(self, message: str = "rate limited", retry_after: float | None = None):
        super().__init__(message)
        self.retry_after = retry_after


class TransientLLMError(LLMError):
    """Timeouts, 5xx, empty/truncated responses. Worth retrying."""


class PermanentLLMError(LLMError):
    """This request will never succeed as sent (bad request, blocked content).

    ``fatal=True`` means *no* request will succeed (bad key, unknown model),
    so the whole run must stop instead of burning through the queue.
    """

    def __init__(self, message: str, fatal: bool = False):
        super().__init__(message)
        self.fatal = fatal


class LLMClient(Protocol):
    model_id: str

    def generate_json(self, system: str, user: str, max_output_tokens: int) -> str:
        """Return the model's raw text (expected to be JSON)."""
        ...
