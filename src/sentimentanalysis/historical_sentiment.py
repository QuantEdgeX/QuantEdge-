import pandas as pd
import re
import torch
import torch.nn.functional as F
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification
)
import os

BASE_DIR = os.path.dirname(__file__)


# CLEAN TEXT
def clean_text(text):

    text = re.sub(r"http\S+", "", str(text))

    text = re.sub(r"[^a-zA-Z0-9\s]", "", text)

    return text.lower()


# LOAD MODEL
print("\nLoading FinBERT model...")

model_name = "ProsusAI/finbert"

tokenizer = AutoTokenizer.from_pretrained(
    model_name
)

model = AutoModelForSequenceClassification.from_pretrained(
    model_name
)

model.eval()

print("FinBERT loaded successfully!\n")


# SENTIMENT FUNCTION
def get_sentiment_score(text):

    inputs = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        padding=True,
        max_length=512
    )

    with torch.no_grad():

        outputs = model(**inputs)

    probs = F.softmax(outputs.logits, dim=1)

    p_pos = probs[0][0].item()

    p_neg = probs[0][1].item()

    confidence = probs.max().item()

    return (p_pos - p_neg) * confidence


# MAIN FUNCTION
def get_sentiment_data():

    print("Loading dataset...\n")

    file_path = os.path.join(
        BASE_DIR,
        "data",
        "stock_news_2016_to_2026.csv"
    )

    df = pd.read_csv(file_path)

    print(f"Original dataset size: {len(df)}")

    # SELECT RANGE
    df = df.iloc[48679:125325]

    df = df.reset_index(drop=True)

    print(f"Rows selected for processing: {len(df)}\n")


    # DATASET COLUMNS
    date_column = "date"

    text_column = "title"


    sentiment_scores = []

    for index, row in df.iterrows():

        print(f"Processing row {index + 1}/{len(df)}")

        text = row[text_column]

        if pd.isna(text):

            sentiment_scores.append(0)

            continue

        text = clean_text(text)

        score = get_sentiment_score(text)

        sentiment_scores.append(score)

        print(f"Generated Score: {score:.4f}\n")


        # CHECKPOINT SAVE
        if (index + 1) % 1000 == 0:

            temp_df = pd.DataFrame({

             date_column:
                df.iloc[:index + 1][date_column].values,

            "sentiment_score":
             sentiment_scores
        })

            temp_output = os.path.join(
                BASE_DIR,
                "output",
                "checkpoint_sentiment.csv"
            )

            temp_df.to_csv(
                temp_output,
                index=False
            )

            print(
                f"Checkpoint saved at row {index + 1}"
            )


    print("Applying sentiment normalization...\n")

    df["sentiment_score"] = sentiment_scores


    # CENTER SCORES
    mean_score = df["sentiment_score"].mean()

    df["sentiment_score"] = (
        df["sentiment_score"] - mean_score
    )


    # DATE-WISE AGGREGATION
    df = df.groupby(date_column)[
        "sentiment_score"
    ].mean().reset_index()


    print("Normalization completed!\n")

    return df[
        [date_column, "sentiment_score"]
    ]


if __name__ == "__main__":

    print(
        "Starting historical sentiment pipeline...\n"
    )

    result = get_sentiment_data()

    print(result.head())

    output_path = os.path.join(
        BASE_DIR,
        "output",
        "historical_sentiment.csv"
    )

    result.to_csv(
        output_path,
        index=False
    )

    print(
        f"\nCSV saved successfully at:\n{output_path}"
    )