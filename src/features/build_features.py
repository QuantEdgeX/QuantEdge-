import pandas as pd

def create_features(df):
    df['Return'] = df['Close'].pct_change()

    # Moving averages
    df['MA5'] = df['Close'].rolling(window=5).mean()
    df['MA10'] = df['Close'].rolling(window=10).mean()

    # Label: next day movement
    df['Target'] = (df['Close'].shift(-1) > df['Close']).astype(int)

    df.dropna(inplace=True)
    return df

if __name__ == "__main__":
    df = pd.read_csv("data/stock_data.csv")
    df = create_features(df)
    df.to_csv("data/processed_data.csv", index=False)
    print("Features created!")