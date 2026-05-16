import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import joblib

from src.data.fetch_data import fetch_stock_data
from src.decision_engine.create_dataset import prepare_dataset
from src.sentimentanalysis.main import get_sentiment_data

def train():
    # 1. Fetch stock data
    df = fetch_stock_data("AAPL")  

    # 2. Fetch sentiment data
    sentiment_df = get_sentiment_data()

    # 3. Prepare dataset
    df = prepare_dataset(df, sentiment_df)

    features = ['returns', 'moving_avg', 'sentiment_score', 'RSI', 'volatility']
    X = df[features]

    # Convert labels
    mapping = {"BUY": 1, "HOLD": 0, "SELL": -1}
    y = df['decision'].map(mapping)

    # Train-test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y,
        test_size=0.2,
        shuffle=False
    )

    # Train model
    model = RandomForestClassifier(
        n_estimators=200,
        max_depth=10,
        random_state=42
    )
    model.fit(X_train, y_train)

    # Predictions
    y_pred = model.predict(X_test)

   # Evaluation
    print(f"Accuracy: {classification_report(y_test, y_pred)}")

    # Save model
    joblib.dump(model, "src/decision_engine/decision_model.pkl")

    print("Model trained and saved!")

if __name__ == "__main__":
    train()