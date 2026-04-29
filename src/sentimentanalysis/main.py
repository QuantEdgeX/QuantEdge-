import pandas as pd
import re
import torch
import torch.nn.functional as F
from transformers import AutoTokenizer, AutoModelForSequenceClassification

# ---------------- CLEAN TEXT ----------------
def clean_text(text):
    text = re.sub(r"http\S+", "", str(text))
    text = re.sub(r"[^a-zA-Z0-9\s]", "", text)
    return text.lower()


# ---------------- LOAD MODEL (load once) ----------------
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
        max_length=128
    )

    with torch.no_grad():
        outputs = model(**inputs)

    probs = F.softmax(outputs.logits, dim=1)

    p_pos = probs[0][0].item()
    p_neg = probs[0][1].item()
    confidence = probs.max().item()

    return (p_pos - p_neg) * confidence


# ✅ MAIN FUNCTION (IMPORTANT FOR YOU)
def get_sentiment_data():
    import os

    BASE_DIR = os.path.dirname(__file__)
    file_path = os.path.join(BASE_DIR, "data", "Combined_News_DJIA.csv")

    df = pd.read_csv(file_path)

    # small sample (you can remove later)
    df = df.sample(n=20, random_state=42)

    text_columns = [col for col in df.columns if "Top" in col]

    daily_scores = []

    for _, row in df.iterrows():
        scores = []

        for col in text_columns:
            headline = row[col]

            if pd.isna(headline):
                continue

            headline = clean_text(headline)
            headline = headline[:150]

            score = get_sentiment_score(headline)
            scores.append(score)

        avg_score = sum(scores) / len(scores) if scores else 0
        daily_scores.append(avg_score)

    df["Date"] = pd.to_datetime(df["Date"])
    df["sentiment_score"] = daily_scores

    return df[["Date", "sentiment_score"]]


# optional run for testing
if __name__ == "__main__":
    result = get_sentiment_data()
    print(result.head())