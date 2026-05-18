import pandas as pd

def create_features(df, sentiment_df):

    # Convert dates
    df['Date'] = pd.to_datetime(df['Date'])
    sentiment_df['date'] = pd.to_datetime(sentiment_df['date'])

    # Merge sentiment data
    df = df.merge(
    sentiment_df,
    left_on='Date',
    right_on='date',
    how='left'
    )

    df.drop(columns=['date'], inplace=True)

    # Fill missing sentiment values
    df['sentiment_score'] = df['sentiment_score'].fillna(0)

    # Sort data properly
    df = df.sort_values(by=["Ticker", "Date"])

    # Daily returns
    df['Return'] = df.groupby('Ticker')['Close'].pct_change()

    # Moving averages
    df['MA5'] = df.groupby('Ticker')['Close'].transform(
        lambda x: x.rolling(window=5).mean()
    )

    df['MA10'] = df.groupby('Ticker')['Close'].transform(
        lambda x: x.rolling(window=10).mean()
    )

    # RSI Calculation
    delta = df.groupby('Ticker')['Close'].diff()

    gain = (
        delta.where(delta > 0, 0)
        .groupby(df['Ticker'])
        .transform(lambda x: x.rolling(window=14).mean())
    )

    loss = (
        (-delta.where(delta < 0, 0))
        .groupby(df['Ticker'])
        .transform(lambda x: x.rolling(window=14).mean())
    )

    rs = gain / loss

    df['RSI'] = 100 - (100 / (1 + rs))

    # Volatility
    df['Volatility'] = df.groupby('Ticker')['Return'].transform(
        lambda x: x.rolling(window=5).std()
    )

    # Future return for labels
    df['Future_Return'] = (
        df.groupby('Ticker')['Close'].shift(-1) / df['Close']
    ) - 1

    # BUY / HOLD / SELL labels
    def label(x):
        if x > 0.003:
            return "BUY"
        elif x < -0.003:
            return "SELL"
        else:
            return "HOLD"

    df['Decision'] = df['Future_Return'].apply(label)

    # Remove NaN rows
    df.dropna(inplace=True)

    return df


if __name__ == "__main__":

    # Load stock data
    df = pd.read_csv("src/data/stock_data.csv")

    # Load historical sentiment data
    sentiment_df = pd.read_csv("src/data/historical_sentiment.csv")

    # Create features
    df = create_features(df, sentiment_df)

    # Save processed dataset
    df.to_csv("src/data/processed_data.csv", index=False)

    print("Features created!")