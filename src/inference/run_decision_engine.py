import pandas as pd
import joblib

from src.data.fetch_data import fetch_stock_data
from src.sentimentanalysis.finbert_sentiment import get_live_sentiment


def calculate_rsi(series, window=14):

    delta = series.diff()

    gain = delta.where(delta > 0, 0).rolling(window=window).mean()

    loss = (-delta.where(delta < 0, 0)).rolling(window=window).mean()

    rs = gain / loss

    rsi = 100 - (100 / (1 + rs))

    return rsi


def run():

    # User input
    ticker = input("Enter stock ticker: ").upper()

    # Fetch latest stock data
    df = fetch_stock_data(
        tickers=[ticker],
        start="2023-01-01"
    )

    # Remove multi-index if present
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)

    # Technical indicators
    df['Return'] = df['Close'].pct_change()

    df['MA5'] = df['Close'].rolling(window=5).mean()

    df['MA10'] = df['Close'].rolling(window=10).mean()

    df['RSI'] = calculate_rsi(df['Close'])

    df['Volatility'] = df['Return'].rolling(window=5).std()

    # Real-time sentiment
    sentiment_data = get_live_sentiment(ticker)

    if sentiment_data is None:
        sentiment_score = 0
        market_mood = "Neutral"

    else:
        sentiment_score = sentiment_data.get(
            "sentiment_score",
            0
        )

        market_mood = sentiment_data.get(
            "market_mood",
            "Neutral"
        )

    df['sentiment_score'] = float(sentiment_score)

    # Remove NaN rows
    df.dropna(inplace=True)

    if df.empty:
        print("No valid data after preprocessing.")
        return

    # Latest row
    latest = df.iloc[-1]

    # Features
    features = pd.DataFrame([{
        'Return': latest['Return'],
        'MA5': latest['MA5'],
        'MA10': latest['MA10'],
        'RSI': latest['RSI'],
        'Volatility': latest['Volatility'],
        'sentiment_score': latest['sentiment_score']
    }])

    # Load trained model
    model = joblib.load(
        "./src/models/decision_model.pkl"
    )

    # Prediction
    pred = model.predict(features)[0]

    # Confidence
    probabilities = model.predict_proba(features)[0]
    confidence = max(probabilities) * 100

    # Decode prediction
    if pred == 1:
        decision = "BUY"

    elif pred == -1:
        decision = "SELL"

    else:
        decision = "HOLD"

    # Output
    print("\n========== FINAL RESULT ==========")

    print(f"Stock: {ticker}")

    print(f"\nCurrent Price: {latest['Close']:.2f}")

    print("\nTechnical Indicators:")

    print(f"RSI: {latest['RSI']:.2f}")
    print(f"MA5: {latest['MA5']:.2f}")
    print(f"MA10: {latest['MA10']:.2f}")
    print(f"Volatility: {latest['Volatility']:.4f}")

    print("\nSentiment Analysis:")

    print(f"Sentiment Score: {sentiment_score:.3f}")
    print(f"Market Mood: {market_mood}")

    print("\nAI Trading Decision:")

    print(f"Prediction: {decision}")
    print(f"Confidence: {confidence:.2f}%")


if __name__ == "__main__":
    run()