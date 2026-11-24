# LLM sentiment pipeline (replacement for the FinBERT feature)

One sentiment score per **ticker per trading day** in [-1, +1], built from timestamped
news (Hugging Face `Brianferrell787/financial-news-multisource`, streamed) scored by Gemini, plus a FinBERT baseline in the identical schema so the
two can be compared fairly. Your existing models and saved artifacts are untouched.

## How a day's score is built

1. **Candidates** – each article is matched to companies by name / product / executive /
   exchange-qualified ticker (`universe.py`, `entities.py`). Bare ticker strings (V, C, MA, GE...)
   are never evidence; a provider tag with no mention in the text is dropped before any API call.
2. **Dedup** – near-identical headlines within 48 h collapse to the *earliest* copy.
3. **Cutoff** – an article counts for the first trading day whose **16:00 ET** cutoff is at or
   after its publication time. After-close, weekend and holiday news go to the next trading day.
   Date-only / midnight timestamps are treated as end-of-day (conservative). For day-level rows the
   corpus' own `date_trading` anchor is ignored; the stamped date is the publication date.
4. **LLM** – Gemini returns JSON per (article, ticker): `sentiment_score`, `relevance_score`,
   `sentiment_label`. Everything is validated; invalid or missing pairs are re-asked, then
   stored as `failed` (never as 0.0).
5. **Aggregate** – `score = Σ(relevance·sentiment) / Σ(relevance)` over articles with
   relevance ≥ 0.30. Days without usable news: score 0.0, `article_count` 0, `has_news` 0.

## Setup

```bash
pip install -r requirements-sentiment.txt
cp .env.example .env            # then set GEMINI_API_KEY (and review the other settings)
```
News source: the Hugging Face dataset `Brianferrell787/financial-news-multisource`, **streamed**
(nothing like the whole 21 GB corpus is downloaded). It is **gated** and licensed for
**non-commercial research / education only**:

1. Open <https://huggingface.co/datasets/Brianferrell787/financial-news-multisource>, log in and accept the terms.
2. Create a read token (<https://huggingface.co/settings/tokens>) and put it in `.env` as `HF_TOKEN`
   (or run `huggingface-cli login`).
3. Respect each original publisher's terms, do not redistribute article text, cite the corpus
   (DOI 10.57967/hf/6432) and the original sources, and delete items on rightsholder request.

The corpus also re-hosts FNSPID as subset `fnspid_news`; it is excluded by default.
All commands run from the repository root.

## Run

```bash
R="python -m src.sentiment.run_pipeline"

$R probe --n 200                                # access + streaming check, sample of each subset
$R scan                                         # stream subsets once: REAL date/ticker coverage (checkpointed)
$R select-period                                # best continuous 6-year window -> selected_period.json
$R prepare-news                                 # stream -> filtered subset for that window (checkpointed per subset)
$R ingest                                       # dedup, trading-day assignment, entity candidates
$R coverage                                     # READ THIS: per-ticker counts, timestamp quality

$R dry-run                                      # pending work + token estimate, no API calls
$R smoke-test --n 3                             # 3 real API calls, prints results, saves nothing
$R score --limit-pairs 200                      # small paid trial; inspect with export-articles
$R score                                        # full run; safe to interrupt and re-run (resumes)
$R score --retry-failed                         # re-attempt only failed pairs

$R aggregate                                    # -> src/data/sentiment/daily_sentiment_llm.csv (selected window only;
                                                #    --full-calendar for every trading day in stock_data.csv)
$R export-articles                              # -> src/data/sentiment/exports/article_scores_llm.csv

# FinBERT baseline on the SAME article/ticker pairs and the SAME aggregation
$R finbert
$R aggregate --scorer finbert                   # -> daily_sentiment_finbert.csv
```

Outputs: `daily_sentiment_*.csv` has `date, ticker, sentiment_score, article_count` plus
`has_news, relevance_weight_sum, n_candidates, n_unscored`. The SQLite cache
(`src/data/sentiment/sentiment_cache.sqlite`) holds every article-level result keyed by
(article, ticker, model, prompt version), so nothing is analysed twice; changing `GEMINI_MODEL` or
`PROMPT_VERSION` triggers fresh scoring and keeps the old results.

## Plug into your features

```bash
python src/features/build_features_enhanced.py \
    --sentiment-file src/data/sentiment/daily_sentiment_llm.csv \
    --output src/data/processed_data_enhanced_llm.csv
```
A file with a `ticker` column is merged on `Date`+`Ticker`; the old date-level file (default
arguments) still works exactly as before. `build_features.py` accepts the same flags. The ticker-level
merge also adds an `article_count` column, which models ignore unless you add it to a `FEATURES` list.

## Comparing the LLM with FinBERT

1. **Cheap first look (no retraining):**
   ```bash
   $R evaluate --arm finbert=src/data/sentiment/daily_sentiment_finbert.csv \
               --arm llm=src/data/sentiment/daily_sentiment_llm.csv \
               --start 2023-01-01
   ```
   Daily cross-sectional rank-IC against the 5-day forward return, with block-bootstrap 95% CIs and a
   paired difference. Use `--start/--end` to look at your validation or test window only.
2. **Real answer:** retrain/evaluate your models once per arm: no sentiment, FinBERT, LLM.
   `final_evaluation_sentiment.py` writes into `src/ml/saved_models/final` and the results folder, so
   run each arm from its own copy of the repo (or back those folders up first) or you will overwrite
   your current saved models.
3. Fix `PROMPT_VERSION`, `MIN_RELEVANCE` and the model **before** looking at test-period results; tune on
   validation only.

## Tests

```bash
python -m unittest discover -s tests -t .
```
(offline: uses a mock LLM; no API key or network needed)

## Known limits

* **Look-ahead in the LLM itself.** Gemini was trained on text covering 2020–2023, so it may "know" how
  stories ended. The prompt forbids hindsight and hides dates by default, but this cannot be eliminated.
  Only data after the model's training cutoff is truly clean; plan a forward test.
* The corpus is a static snapshot: live/CLI inference needs a separate news source feeding the same cache.
* Coverage differs a lot by subset and year (tagged minute-level data is mostly Yahoo Finance 2017-2023).
  `scan` / `select-period` choose the window from observed counts; check `coverage` after `ingest`.
* The same story can appear in several subsets; ingest's near-duplicate removal keeps the earliest copy,
  which can be a day-level (midnight) copy of a timed article. That delays the article to the next
  trading day (safe, never look-ahead) but may lose same-day signal.
* `GOOG`->`GOOGL` and `FB`->`META` dataset tags are mapped to the universe tickers; text evidence is still required.
* FinBERT is not entity-aware: every ticker in an article gets the article's score (relevance fixed at 1;
  use `aggregate --scorer finbert --relevance-from llm` for an LLM-relevance-weighted ablation).
* Requests are batched (several articles per call). Google's asynchronous Batch API is not used.
* The Gemini client follows the documented `google-genai` interface but was only tested here against a
  mock. Run `smoke-test` first; if the model name is rejected, set `GEMINI_MODEL`.
