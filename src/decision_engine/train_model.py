import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
import joblib

from src.data.fetch_data import fetch_stock_data
from src.decision_engine.create_dataset import prepare_dataset
from src.sentimentanalysis.main import get_sentiment_data

def train():
    # 1. Fetch stock data
    df = fetch_stock_data("AAPL")  # or your stock

    # 2. Fetch sentiment data
    sentiment_df = get_sentiment_data()

    # 3. Prepare dataset
    df = prepare_dataset(df, sentiment_df)

    features = ['returns', 'moving_avg', 'sentiment_score']
    X = df[features]

    # Convert labels
    mapping = {"BUY": 1, "HOLD": 0, "SELL": -1}
    y = df['decision'].map(mapping)

    # Train-test split
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

    # Train model
    model = RandomForestClassifier()
    model.fit(X_train, y_train)

    # Save model
    joblib.dump(model, "src/decision_engine/decision_model.pkl")

    print("✅ Model trained and saved!")


if __name__ == "__main__":
    train()