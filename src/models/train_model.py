import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import joblib

def train():

    # Load processed dataset
    df = pd.read_csv("src/data/processed_data.csv")

    # Features
    features = [
    'Return',
    'MA5',
    'MA10',
    'RSI',
    'Volatility',
]

    # Add sentiment only if column exists
    if 'sentiment_score' in df.columns:
        features.append('sentiment_score')

    X = df[features]

    # Labels
    mapping = {"BUY": 1, "HOLD": 0, "SELL": -1}

    y = df['Decision'].map(mapping)

    # Train/test split
    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=0.2,
        shuffle=False
    )

    # Train model
    model = RandomForestClassifier(
        n_estimators=300,
        max_depth=15,
        min_samples_split=10,
        min_samples_leaf=5,
        class_weight='balanced',
        random_state=42
    )

    model.fit(X_train, y_train)

    # Predictions
    y_pred = model.predict(X_test)

    # Evaluation
    print(classification_report(y_test, y_pred))

    # Save trained model
    joblib.dump(
        model,
        "src/models/decision_model.pkl"
    )

    print(df['Decision'].value_counts())

    print("Model trained and saved!")

if __name__ == "__main__":
    train()
    