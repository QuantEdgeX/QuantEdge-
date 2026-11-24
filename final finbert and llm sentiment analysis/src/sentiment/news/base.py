"""Provider-agnostic article schema. Adapters emit DataFrames with these columns."""
from __future__ import annotations

ARTICLE_COLUMNS = [
    "article_id",    # stable id; same story under several tags shares one id
    "published_at",  # tz-aware UTC timestamp (ISO string in CSV)
    "time_known",    # 0/1: False when only a date (or midnight) is known
    "title",
    "body",
    "url",
    "publisher",
    "author",
    "symbol_tag",    # provider's own ticker tag for this row (may be blank)
]
