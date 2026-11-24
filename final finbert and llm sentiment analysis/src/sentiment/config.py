"""Central configuration for the LLM sentiment pipeline.

Everything tunable lives here and is overridable through environment
variables (or a local ``.env`` file). API keys are read from the
environment only and are never logged or written to disk.
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from datetime import time
from pathlib import Path

logger = logging.getLogger(__name__)

try:  # optional convenience: load .env if python-dotenv is installed
    from dotenv import load_dotenv

    load_dotenv()
except Exception:  # pragma: no cover - dotenv is optional
    pass


def _env_str(name: str, default: str) -> str:
    value = os.environ.get(name)
    return value.strip() if value and value.strip() else default


def _env_int(name: str, default: int) -> int:
    try:
        return int(_env_str(name, str(default)))
    except ValueError:
        raise ValueError(f"Environment variable {name} must be an integer")


def _env_float(name: str, default: float) -> float:
    try:
        return float(_env_str(name, str(default)))
    except ValueError:
        raise ValueError(f"Environment variable {name} must be a number")


def _env_bool(name: str, default: bool) -> bool:
    return _env_str(name, str(default)).lower() in {"1", "true", "yes", "y"}


def _env_time(name: str, default: str) -> time:
    hh, mm = _env_str(name, default).split(":")
    return time(int(hh), int(mm))


@dataclass(frozen=True)
class Settings:
    # ---- paths -----------------------------------------------------
    data_dir: Path = Path("src/data/sentiment")
    stock_data_path: Path = Path("src/data/stock_data.csv")

    # ---- news window -------------------------------------------------
    # Empty = use the window chosen by `select-period` (selected_period.json).
    # NEWS_START / NEWS_END in the environment override it.
    news_start: str = ""
    news_end: str = ""
    period_years: int = 6

    # ---- leakage control ---------------------------------------------
    # An article is usable for trading day D only if it was published at
    # or before this wall-clock time (America/New_York) on day D.
    cutoff_time: time = time(16, 0)
    market_tz: str = "America/New_York"

    # ---- entity matching / aggregation --------------------------------
    min_relevance: float = 0.30
    require_text_evidence: bool = True
    max_candidates_per_article: int = 6
    dedup_window_hours: int = 48
    dedup_jaccard: float = 0.85

    # ---- LLM ---------------------------------------------------------
    llm_provider: str = "gemini"            # gemini | mock
    llm_model: str = "gemini-2.5-flash"     # override with GEMINI_MODEL
    prompt_version: str = "v1"
    batch_size: int = 5                     # articles per request
    max_article_chars: int = 3000
    include_date_in_prompt: bool = False    # hides dates from the LLM
    requests_per_minute: int = 60
    max_workers: int = 1
    max_retries: int = 6
    retry_base_seconds: float = 2.0
    retry_max_seconds: float = 90.0
    request_timeout_seconds: int = 120
    thinking_budget: int | None = None      # Gemini 2.5 only; None = default

    @property
    def db_path(self) -> Path:
        return self.data_dir / "sentiment_cache.sqlite"

    @property
    def period_path(self) -> Path:
        return self.data_dir / "selected_period.json"

    @property
    def raw_dir(self) -> Path:
        return self.data_dir / "raw"

    @property
    def export_dir(self) -> Path:
        return self.data_dir / "exports"

    def gemini_api_key(self) -> str:
        key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        if not key:
            raise RuntimeError(
                "No Gemini API key found. Set GEMINI_API_KEY (or GOOGLE_API_KEY) "
                "in your environment or .env file."
            )
        return key


def load_settings() -> Settings:
    thinking = os.environ.get("GEMINI_THINKING_BUDGET")
    return Settings(
        data_dir=Path(_env_str("SENTIMENT_DATA_DIR", "src/data/sentiment")),
        stock_data_path=Path(_env_str("STOCK_DATA_PATH", "src/data/stock_data.csv")),
        news_start=_env_str("NEWS_START", ""),
        news_end=_env_str("NEWS_END", ""),
        period_years=_env_int("PERIOD_YEARS", 6),
        cutoff_time=_env_time("PREDICTION_CUTOFF_ET", "16:00"),
        market_tz=_env_str("MARKET_TZ", "America/New_York"),
        min_relevance=_env_float("MIN_RELEVANCE", 0.30),
        require_text_evidence=_env_bool("REQUIRE_TEXT_EVIDENCE", True),
        llm_provider=_env_str("LLM_PROVIDER", "gemini").lower(),
        llm_model=_env_str("GEMINI_MODEL", "gemini-2.5-flash"),
        prompt_version=_env_str("PROMPT_VERSION", "v1"),
        batch_size=_env_int("LLM_BATCH_SIZE", 5),
        max_article_chars=_env_int("MAX_ARTICLE_CHARS", 3000),
        include_date_in_prompt=_env_bool("INCLUDE_DATE_IN_PROMPT", False),
        requests_per_minute=_env_int("LLM_REQUESTS_PER_MINUTE", 60),
        max_workers=_env_int("LLM_MAX_WORKERS", 1),
        max_retries=_env_int("LLM_MAX_RETRIES", 6),
        thinking_budget=int(thinking) if thinking not in (None, "") else None,
    )


def setup_logging(level: str | None = None, log_file: Path | None = None) -> None:
    """Console logging, plus an optional file handler."""
    level_name = (level or os.environ.get("LOG_LEVEL", "INFO")).upper()
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    if log_file is not None:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_file, encoding="utf-8"))
    logging.basicConfig(
        level=getattr(logging, level_name, logging.INFO),
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        handlers=handlers,
        force=True,
    )
    # Never let HTTP libraries print request URLs (which can carry keys).
    for noisy in ("httpx", "httpcore", "urllib3", "google_genai"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
