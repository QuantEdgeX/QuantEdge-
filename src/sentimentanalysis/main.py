import yfinance as yf
import pandas as pd
import torch

from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification
)

MODEL_NAME = "ProsusAI/finbert"

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

    positive = probs[0][0].item()
    negative = probs[0][1].item()
    neutral = probs[0][2].item()

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


trusted_sources = [
    "Reuters",
    "Bloomberg",
    "CNBC",
    "Yahoo Finance",
    "MarketWatch",
    "The Wall Street Journal",
    "Barrons"
]


ticker = input("Enter stock ticker: ").upper()

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


        # Filter trusted sources only
        # if source not in trusted_sources:
        #     continue


        # Sentiment analysis
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


if len(scores) == 0:

    print("No trusted news headlines found.")

    exit()


avg_sentiment = sum(scores) / len(scores)


if avg_sentiment > 0.2:
    mood = "Bullish"

elif avg_sentiment < -0.2:
    mood = "Bearish"

else:
    mood = "Neutral"


results_df = pd.DataFrame(results)


print("\n========== FINAL RESULT ==========")

print("Stock:", ticker)

print("Total Headlines:", len(results))

print("Sentiment Score:", round(avg_sentiment, 3))

print("Market Mood:", mood)

