import yfinance as yf
import pandas as pd
import torch

from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification
)

MODEL_NAME = "ProsusAI/finbert"

# Load tokenizer and model once
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

model = AutoModelForSequenceClassification.from_pretrained(MODEL_NAME)


def analyze_sentiment(text):

    inputs = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        padding=True,
        max_length=512
    )

    with torch.no_grad():
        outputs = model(**inputs)

    probs = torch.nn.functional.softmax(
        outputs.logits,
        dim=-1
    )

    negative = probs[0][0].item()

    neutral = probs[0][1].item()

    positive = probs[0][2].item()

    score = positive - negative

    if score > 0.2:
        sentiment = "Bullish"

    elif score < -0.2:
        sentiment = "Bearish"

    else:
        sentiment = "Neutral"

    return {
        "positive": positive,
        "negative": negative,
        "neutral": neutral,
        "score": score,
        "sentiment": sentiment
    }


def get_live_sentiment(ticker):

    stock = yf.Ticker(ticker)

    news = stock.news

    results = []

    scores = []

    for item in news:

        try:

            content = item['content']

            headline = content['title']

            source = content['provider']['displayName']

            timestamp = content['pubDate']

            # Analyze headline sentiment
            result = analyze_sentiment(headline)

            score = result['score']

            scores.append(score)

            results.append({

                "headline": headline,

                "source": source,

                "timestamp": timestamp,

                "positive": result['positive'],

                "negative": result['negative'],

                "neutral": result['neutral'],

                "score": score,

                "sentiment": result['sentiment']
            })

        except:
            pass

    # No news fallback
    if len(scores) == 0:

        return {
            "sentiment_score": 0,
            "market_mood": "Neutral",
            "headlines": pd.DataFrame()
        }

    avg_sentiment = sum(scores) / len(scores)

    if avg_sentiment > 0.2:
        mood = "Bullish"

    elif avg_sentiment < -0.2:
        mood = "Bearish"

    else:
        mood = "Neutral"

    results_df = pd.DataFrame(results)

    return {

        "sentiment_score": avg_sentiment,

        "market_mood": mood,

        "headlines": results_df
    }


if __name__ == "__main__":

    ticker = input("Enter stock ticker: ").upper()

    result = get_live_sentiment(ticker)

    print("\n========== FINAL RESULT ==========")

    print("Stock:", ticker)

    print("Sentiment Score:",
          round(result['sentiment_score'], 3))

    print("Market Mood:",
          result['market_mood'])

    print("Total Headlines:",
          len(result['headlines']))