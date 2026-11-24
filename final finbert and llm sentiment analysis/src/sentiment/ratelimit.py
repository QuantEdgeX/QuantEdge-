"""Client-side rate limiting and exponential backoff with jitter."""
from __future__ import annotations

import random
import threading
import time


class RateLimiter:
    """Thread-safe minimum-interval limiter (requests per minute)."""

    def __init__(self, requests_per_minute: int, clock=time.monotonic, sleep=time.sleep):
        self.interval = 60.0 / requests_per_minute if requests_per_minute > 0 else 0.0
        self._clock, self._sleep = clock, sleep
        self._lock = threading.Lock()
        self._next = 0.0

    def acquire(self) -> None:
        if self.interval <= 0:
            return
        with self._lock:
            now = self._clock()
            wait = self._next - now
            self._next = max(now, self._next) + self.interval
        if wait > 0:
            self._sleep(wait)


def backoff_delay(attempt: int, base: float, cap: float, retry_after: float | None = None,
                  rng=random.random) -> float:
    """Full-jitter exponential backoff, never shorter than a server hint."""
    exp = min(cap, base * (2 ** attempt))
    delay = exp * (0.5 + 0.5 * rng())
    if retry_after:
        delay = max(delay, retry_after)
    return min(delay, max(cap, retry_after or 0))
