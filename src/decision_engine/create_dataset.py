import pandas as pd

def create_labels(df, threshold=0.01):
    df['future_return'] = df['Close'].shift(-1) / df['Close'] - 1

    def label(x):
        if x > threshold:
            return "BUY"
        elif x < -threshold:
            return "SELL"
        else:
            return "HOLD"

    df['decision'] = df['future_return'].apply(label)
    return df


def prepare_dataset(df, sentiment_df):
    # Merge stock + sentiment (assumes both have 'Date')
    df = df.merge(sentiment_df, on='Date', how='left')

    # Fill missing sentiment
    df['sentiment_score'] = df['sentiment_score'].fillna(0)

    # Create returns
    df['returns'] = df['Close'].pct_change()

    # Moving average
    df['moving_avg'] = df['Close'].rolling(window=5).mean()

    # Drop NaN
    df = df.dropna()

    # Create labels
    df = create_labels(df)

    return df