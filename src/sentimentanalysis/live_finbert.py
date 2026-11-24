
import re
import torch
import yfinance as yf
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
)

MARKET_TIMEZONE = ZoneInfo("America/New_York")
# ============================================================
# CONFIGURATION
# ============================================================

FINBERT_MODEL_NAME = "ProsusAI/finbert"
NEWS_COUNT = 30
BATCH_SIZE = 32

_FINBERT_TOKENIZER = None
_FINBERT_MODEL = None
_FINBERT_DEVICE = None

_POSITIVE_INDEX = None
_NEGATIVE_INDEX = None


# ============================================================
# TICKER ALIASES
# ============================================================

TICKER_ALIASES = {
    # Technology
    "AAPL": ["Apple", "Apple Inc"],
    "MSFT": ["Microsoft"],
    "NVDA": ["NVIDIA"],
    "AMD": ["Advanced Micro Devices"],
    "AVGO": ["Broadcom"],
    "ORCL": ["Oracle"],
    "CSCO": ["Cisco", "Cisco Systems"],
    "ADBE": ["Adobe"],

    # Communication Services
    "GOOGL": ["Google", "Alphabet"],
    "META": ["Meta Platforms", "Facebook"],
    "NFLX": ["Netflix"],
    "DIS": ["Walt Disney", "Disney"],
    "CMCSA": ["Comcast"],

    # Consumer Discretionary
    "AMZN": ["Amazon", "Amazon.com"],
    "TSLA": ["Tesla"],
    "HD": ["Home Depot"],
    "MCD": ["McDonald's", "McDonalds"],
    "NKE": ["Nike"],
    "LOW": ["Lowe's", "Lowes"],

    # Financials
    "JPM": ["JPMorgan", "JPMorgan Chase"],
    "BAC": ["Bank of America"],
    "GS": ["Goldman Sachs"],
    "V": ["Visa"],
    "MA": ["Mastercard"],
    "WFC": ["Wells Fargo"],
    "C": ["Citigroup", "Citibank"],

    # Healthcare
    "JNJ": ["Johnson & Johnson", "Johnson and Johnson"],
    "UNH": ["UnitedHealth", "UnitedHealthcare"],
    "LLY": ["Eli Lilly"],
    "PFE": ["Pfizer"],
    "ABBV": ["AbbVie"],
    "MRK": ["Merck"],

    # Industrials
    "CAT": ["Caterpillar"],
    "BA": ["Boeing"],
    "GE": ["GE Aerospace", "General Electric"],
    "HON": ["Honeywell"],
    "UPS": ["United Parcel Service"],
    "RTX": ["RTX Corporation", "Raytheon Technologies", "Raytheon"],

    # Consumer Staples
    "WMT": ["Walmart", "Wal-Mart"],
    "PG": ["Procter & Gamble", "Procter and Gamble"],
    "KO": ["Coca-Cola", "Coca Cola"],
    "PEP": ["PepsiCo"],
    "COST": ["Costco"],

    # Energy
    "XOM": ["ExxonMobil", "Exxon Mobil", "Exxon"],
    "CVX": ["Chevron"],
    "COP": ["ConocoPhillips", "Conoco Phillips"],

    # Utilities
    "NEE": ["NextEra Energy"],
    "DUK": ["Duke Energy"],
}


# Symbols that are too ambiguous to match in ordinary headlines.
# For these, require the company name or a ticker written in
# an explicit stock-market context.
AMBIGUOUS_TICKERS = {
    "C", "V", "CAT", "MA", "GS", "HD", "LOW", "GE", "BA", "PG", "KO"
}


EXPECTED_TICKERS = {
    "AAPL", "MSFT", "NVDA", "AMD", "AVGO", "ORCL", "CSCO", "ADBE",
    "GOOGL", "META", "NFLX", "DIS", "CMCSA",
    "AMZN", "TSLA", "HD", "MCD", "NKE", "LOW",
    "JPM", "BAC", "GS", "V", "MA", "WFC", "C",
    "JNJ", "UNH", "LLY", "PFE", "ABBV", "MRK",
    "CAT", "BA", "GE", "HON", "UPS", "RTX",
    "WMT", "PG", "KO", "PEP", "COST",
    "XOM", "CVX", "COP", "NEE", "DUK"
}

assert set(TICKER_ALIASES) == EXPECTED_TICKERS


# ============================================================
# MATCHING HELPERS
# ============================================================

def contains_phrase(text, phrase):
    """
    Case-insensitive whole-word or phrase matching.
    """

    pattern = (
        r"(?<![a-z0-9])"
        + re.escape(phrase.lower())
        + r"(?![a-z0-9])"
    )

    return bool(re.search(pattern, text.lower()))


def is_relevant_headline(headline, ticker):

    ticker = ticker.upper()
    text = headline.lower()

    aliases = TICKER_ALIASES.get(ticker)

    if aliases is None:
        raise ValueError(f"Unsupported ticker: {ticker}")

    # Company-name matching.
    for alias in aliases:

        if contains_phrase(text, alias):
            return True

    # Unambiguous ticker symbols.
    if ticker not in AMBIGUOUS_TICKERS:

        if contains_phrase(text, ticker):
            return True

    # Ambiguous ticker symbols require explicit stock context.
    else:

        stock_patterns = [
            rf"\b{re.escape(ticker)}\s+stock\b",
            rf"\b{re.escape(ticker)}\s+shares\b",
            rf"\b{re.escape(ticker)}\s+earnings\b",
            rf"\b{re.escape(ticker)}\s+stocks?\b",
            rf"\b{re.escape(ticker)}\s*:\s*(?:NYSE|NASDAQ)\b",
        ]

        if any(
            re.search(pattern, text, re.IGNORECASE)
            for pattern in stock_patterns
        ):
            return True

    return False


# ============================================================
# GENERIC HEADLINE FILTER
# ============================================================

GENERIC_PATTERNS = [
    r"\bwhat'?s moving markets\b",
    r"\bstocks? are mixed\b",
    r"\bmarket today\b",
    r"\bmost active stocks\b",
    r"\bstocks to watch\b",
    r"\bmarket wrap\b",
]


def is_generic_headline(headline):

    text = headline.lower()

    return any(
        re.search(pattern, text)
        for pattern in GENERIC_PATTERNS
    )


# ============================================================
# FINBERT LOADING
# ============================================================

def load_finbert():

    global _FINBERT_TOKENIZER
    global _FINBERT_MODEL
    global _FINBERT_DEVICE
    global _POSITIVE_INDEX
    global _NEGATIVE_INDEX

    if _FINBERT_MODEL is not None:
        return

    print("\nLoading FinBERT...")

    _FINBERT_DEVICE = torch.device(
        "cuda" if torch.cuda.is_available() else "cpu"
    )

    _FINBERT_TOKENIZER = AutoTokenizer.from_pretrained(
        FINBERT_MODEL_NAME
    )

    _FINBERT_MODEL = AutoModelForSequenceClassification.from_pretrained(
        FINBERT_MODEL_NAME
    )

    _FINBERT_MODEL.to(_FINBERT_DEVICE)
    _FINBERT_MODEL.eval()

    id2label = {
        int(key): str(value).lower()
        for key, value in _FINBERT_MODEL.config.id2label.items()
    }

    _POSITIVE_INDEX = next(
        index
        for index, label in id2label.items()
        if label.startswith("pos")
    )

    _NEGATIVE_INDEX = next(
        index
        for index, label in id2label.items()
        if label.startswith("neg")
    )

    print(f"FinBERT loaded on {_FINBERT_DEVICE}")
    print(f"Labels: {id2label}")


# ============================================================
# NEWS EXTRACTION
# ============================================================

def extract_news_title(item):

    content = item.get("content")

    if isinstance(content, dict):

        title = content.get("title")

        if title:
            return str(title).strip()

    title = item.get("title")

    if title:
        return str(title).strip()

    return ""


def extract_publication_time(item):
    """
    Extract the publication timestamp from Yahoo Finance news.

    Supports:
    - content.pubDate: ISO-8601 timestamp
    - providerPublishTime: Unix timestamp
    - content.providerPublishTime: Unix timestamp

    Returns a timezone-aware UTC datetime or None.
    """

    content = item.get("content")

    if not isinstance(content, dict):
        content = {}

    timestamp = (
        content.get("pubDate")
        or item.get("pubDate")
    )

    if timestamp:
        try:
            parsed = datetime.fromisoformat(
                str(timestamp).replace("Z", "+00:00")
            )

            if parsed.tzinfo is None:
                return None

            return parsed.astimezone(timezone.utc)

        except (ValueError, TypeError):
            pass

    unix_timestamp = (
        item.get("providerPublishTime")
        or content.get("providerPublishTime")
    )

    if unix_timestamp is not None:
        try:
            return datetime.fromtimestamp(
                float(unix_timestamp),
                tz=timezone.utc
            )
        except (ValueError, TypeError, OverflowError, OSError):
            pass

    return None



def fetch_live_news(
    ticker,
    count=NEWS_COUNT,
    as_of=None
):
    """
    Fetch ticker-specific news published no later than as_of.

    All comparisons are performed in UTC.
    """

    ticker = ticker.upper()

    if ticker not in TICKER_ALIASES:
        raise ValueError(f"Unsupported ticker: {ticker}")

    if as_of is None:
        as_of = datetime.now(timezone.utc)

    if as_of.tzinfo is None:
        raise ValueError("as_of must be timezone-aware.")

    as_of = as_of.astimezone(timezone.utc)

    print(f"\nSearching Yahoo Finance news for {ticker}...")
    print(f"Publication cutoff: {as_of.astimezone(MARKET_TIMEZONE)}")

    search = yf.Search(
        ticker,
        news_count=count
    )

    news_items = getattr(search, "news", None) or []

    accepted = []
    rejected = []
    seen = set()

    stats = {
        "missing_timestamp": 0,
        "future_timestamp": 0,
        "irrelevant": 0,
        "generic": 0,
        "duplicates": 0,
    }

    for item in news_items:

        if not isinstance(item, dict):
            continue

        title = extract_news_title(item)

        if not title:
            continue

        normalized = title.lower().strip()

        if normalized in seen:
            stats["duplicates"] += 1
            continue

        seen.add(normalized)

        published_at = extract_publication_time(item)

        # Reject articles whose publication time cannot be verified.
        if published_at is None:
            stats["missing_timestamp"] += 1
            rejected.append((title, "Missing publication timestamp"))
            continue

        # Reject news published after the prediction cutoff.
        if published_at > as_of:
            stats["future_timestamp"] += 1
            rejected.append((title, "Published after cutoff"))
            continue

        if not is_relevant_headline(title, ticker):
            stats["irrelevant"] += 1
            rejected.append((title, "Ticker not matched"))
            continue

        if is_generic_headline(title):
            stats["generic"] += 1
            rejected.append((title, "Generic market headline"))
            continue

        accepted.append({
            "title": title,
            "published_at": published_at,
        })

    accepted.sort(
        key=lambda item: item["published_at"],
        reverse=True
    )

    print(f"\nTotal Yahoo results: {len(news_items)}")
    print(f"Accepted headlines: {len(accepted)}")
    print(f"Rejected headlines: {len(rejected)}")

    print("\nAccepted headlines:")

    for index, article in enumerate(accepted[:count], 1):

        local_time = article["published_at"].astimezone(
            MARKET_TIMEZONE
        )

        print(
            f"{index}. [{local_time:%Y-%m-%d %H:%M %Z}] "
            f"{article['title']}"
        )

    print("\nRejection statistics:")

    for reason, total in stats.items():
        print(f"{reason}: {total}")

    return accepted[:count]


# ============================================================
# FINBERT SCORING
# ============================================================

def score_headlines(headlines):

    if not headlines:
        return []

    load_finbert()

    scores = []

    for start in range(0, len(headlines), BATCH_SIZE):

        batch = headlines[start:start + BATCH_SIZE]

        encoded = _FINBERT_TOKENIZER(
            batch,
            padding=True,
            truncation=True,
            max_length=512,
            return_tensors="pt"
        )

        encoded = {
            key: value.to(_FINBERT_DEVICE)
            for key, value in encoded.items()
        }

        with torch.no_grad():

            outputs = _FINBERT_MODEL(**encoded)

            probabilities = torch.softmax(
                outputs.logits,
                dim=-1
            )

            batch_scores = (
                probabilities[:, _POSITIVE_INDEX]
                - probabilities[:, _NEGATIVE_INDEX]
            )

            scores.extend(batch_scores.cpu().tolist())

    return scores


# ============================================================
# LIVE SENTIMENT
# ============================================================


def get_live_sentiment(ticker, as_of=None):

    ticker = ticker.upper()

    articles = fetch_live_news(
        ticker,
        as_of=as_of
    )

    if not articles:

        print(f"\nNo eligible news found for {ticker}.")
        print("Using neutral sentiment_score = 0.0")

        return 0.0

    headlines = [
        article["title"]
        for article in articles
    ]

    scores = score_headlines(headlines)

    print("\n" + "=" * 60)
    print(f"FINBERT RESULTS: {ticker}")
    print("=" * 60)

    for article, score in zip(articles, scores):

        published_at = article["published_at"].astimezone(
            MARKET_TIMEZONE
        )

        print(f"\nPublished: {published_at}")
        print(f"Headline: {article['title']}")
        print(f"Sentiment: {score:.6f}")

    sentiment_score = sum(scores) / len(scores)

    print("\n" + "=" * 60)
    print(f"Eligible articles: {len(scores)}")
    print(f"Average sentiment: {sentiment_score:.6f}")
    print("=" * 60)

    return float(sentiment_score)


# ============================================================
# TEST
# ============================================================

if __name__ == "__main__":

    print(f"Alias coverage verified: {len(TICKER_ALIASES)} tickers")

    ticker = input("Enter ticker: ").strip().upper()

    try:

        score = get_live_sentiment(ticker)

        print(
            f"\nFinal live sentiment for {ticker}: {score:.6f}"
        )

    except Exception as error:

        print(f"\nError: {error}")
