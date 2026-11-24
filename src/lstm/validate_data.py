import pandas as pd

DATA_PATH = "src/data/processed_data.csv"

FEATURES = [
    "Return",
    "MA5",
    "MA10",
    "RSI",
    "Volatility",
    "sentiment_score"
]

def validate_data():

    df = pd.read_csv(DATA_PATH)

    print("\n========== DATASET OVERVIEW ==========")

    print(f"Total rows: {len(df)}")
    print(f"Total columns: {len(df.columns)}")

    print("\nColumns:")
    print(df.columns.tolist())

    # Convert date
    df["Date"] = pd.to_datetime(df["Date"])

    # Sort properly
    df = df.sort_values(["Ticker", "Date"])

    # TICKER INFORMATION
    print("\n========== TICKER INFORMATION ==========")

    print("Number of tickers:", df["Ticker"].nunique())

    print("\nRows per ticker:")
    print(df["Ticker"].value_counts().sort_index())

    # DATE RANGE
    print("\n========== DATE RANGE ==========")

    print("Overall:")
    print(df["Date"].min(), "→", df["Date"].max())

    print("\nDate range per ticker:")
    print(
        df.groupby("Ticker")["Date"]
        .agg(["min", "max"])
    )

    # MISSING VALUES
    print("\n========== MISSING VALUES ==========")

    print(df[FEATURES + ["Decision"]].isnull().sum())

    # CLASS DISTRIBUTION
    print("\n========== DECISION DISTRIBUTION ==========")

    print(df["Decision"].value_counts())

    print("\nDecision percentages:")
    print(
        df["Decision"]
        .value_counts(normalize=True)
        .mul(100)
        .round(2)
    )

    # CLASS DISTRIBUTION PER TICKER
    print("\n========== DECISION DISTRIBUTION PER TICKER ==========")

    print(
        pd.crosstab(
            df["Ticker"],
            df["Decision"],
            normalize="index"
        ).round(3)
    )

    # DUPLICATE DATES
    print("\n========== DUPLICATES ==========")

    duplicates = df.duplicated(
        subset=["Ticker", "Date"]
    ).sum()

    print("Duplicate Ticker-Date rows:", duplicates)

    # FEATURE SUMMARY
    print("\n========== FEATURE SUMMARY ==========")

    print(df[FEATURES].describe())

    print("\nValidation complete.")

if __name__ == "__main__":
    validate_data()