import pandas as pd
import re
import torch
import torch.nn.functional as F
from transformers import AutoTokenizer, AutoModelForSequenceClassification

# ---------------- LOAD DATA ----------------
df = pd.read_csv("data/Combined_News_DJIA.csv")

# start small for testing (increase later)
df = df.sample(n=20, random_state=42)

# get all headline columns
text_columns = [col for col in df.columns if "Top" in col]

# ---------------- CLEAN TEXT ----------------
def clean_text(text):
    text = re.sub(r"http\S+", "", str(text))          # remove URLs
    text = re.sub(r"[^a-zA-Z0-9\s]", "", text)        # remove special characters
    return text.lower()

# ---------------- LOAD FINBERT ----------------
model_name = "ProsusAI/finbert"

tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForSequenceClassification.from_pretrained(model_name)
model.eval()

# ---------------- SENTIMENT FUNCTION ----------------
def get_sentiment_score(text):
    inputs = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        padding=True,
        max_length=128   # shorter = faster
    )

    with torch.no_grad():
        outputs = model(**inputs)

    probs = F.softmax(outputs.logits, dim=1)

    p_pos = probs[0][0].item()
    p_neg = probs[0][1].item()
    confidence = probs.max().item()

    return (p_pos - p_neg) * confidence

# ---------------- CALCULATE DAILY SENTIMENT ----------------
daily_scores = []

for i, row in df.iterrows():
    scores = []

    for col in text_columns:
        headline = row[col]

        if pd.isna(headline):
            continue

        headline = clean_text(headline)
        headline = headline[:150]   # speed optimization

        score = get_sentiment_score(headline)
        scores.append(score)

    # average score for that day
    if len(scores) > 0:
        avg_score = sum(scores) / len(scores)
    else:
        avg_score = 0

    daily_scores.append(avg_score)

# ---------------- FINAL OUTPUT ----------------
df["date"] = pd.to_datetime(df["Date"]).dt.date
df["sentiment_score"] = daily_scores

result = df[["date", "sentiment_score"]]

print(result.head())

result.to_csv("daily_sentiment.csv", index=False)