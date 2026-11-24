import pandas as pd
import numpy as np


def create_features(df, sentiment_df):

    # -----------------------------------
    # DATE HANDLING
    # -----------------------------------

    df["Date"] = pd.to_datetime(df["Date"])
    sentiment_df["date"] = pd.to_datetime(sentiment_df["date"])

    # -----------------------------------
    # MERGE SENTIMENT
    # -----------------------------------

    if "ticker" in sentiment_df.columns:

        # Ticker-level sentiment from the src/sentiment pipeline:
        # merge on Date AND Ticker (one score per ticker per day).
        sentiment_df["ticker"] = (
            sentiment_df["ticker"].astype(str).str.strip().str.upper()
        )

        keep = [
            c for c in
            ["date", "ticker", "sentiment_score", "article_count"]
            if c in sentiment_df.columns
        ]

        df = df.merge(
            sentiment_df[keep],
            left_on=["Date", "Ticker"],
            right_on=["date", "ticker"],
            how="left"
        )

        df.drop(columns=["date", "ticker"], inplace=True)

        n_missing = int(df["sentiment_score"].isna().sum())

        if n_missing:
            print(
                f"WARNING: {n_missing:,} rows had no sentiment row "
                f"and were filled with 0 (neutral)."
            )

        if "article_count" in df.columns:
            df["article_count"] = df["article_count"].fillna(0)

    else:

        # Legacy market-wide sentiment: merge on Date only.
        df = df.merge(
            sentiment_df,
            left_on="Date",
            right_on="date",
            how="left"
        )

        df.drop(columns=["date"], inplace=True)

    df["sentiment_score"] = df["sentiment_score"].fillna(0)

    # -----------------------------------
    # SORT
    # -----------------------------------

    df = df.sort_values(
        by=["Ticker", "Date"]
    ).reset_index(drop=True)

    # -----------------------------------
    # RETURNS
    # -----------------------------------

    df["Return"] = (
        df.groupby("Ticker")["Close"]
        .pct_change()
    )
    # -----------------------------------
    # MOMENTUM
    # -----------------------------------

    df["Return_3D"] = (
        df.groupby("Ticker")["Close"].pct_change(3)
    )

    df["Return_5D"] = (
        df.groupby("Ticker")["Close"].pct_change(5)
    )

    df["Return_10D"] = (
        df.groupby("Ticker")["Close"].pct_change(10)
    )

    # -----------------------------------
    # MOVING AVERAGES
    # -----------------------------------

    df["MA5"] = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.rolling(5).mean()
        )
    )

    df["MA10"] = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.rolling(10).mean()
        )
    )

    # Relative position to moving averages
    df["Price_MA5_Ratio"] = (
        df["Close"] / df["MA5"] - 1
    )

    df["Price_MA10_Ratio"] = (
        df["Close"] / df["MA10"] - 1
    )

    # -----------------------------------
    # EMA
    # -----------------------------------

    df["EMA12"] = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.ewm(
                span=12,
                adjust=False
            ).mean()
        )
    )

    df["EMA26"] = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.ewm(
                span=26,
                adjust=False
            ).mean()
        )
    )

    # -----------------------------------
    # MACD
    # -----------------------------------

    df["MACD"] = df["EMA12"] - df["EMA26"]

    df["MACD_Signal"] = (
        df.groupby("Ticker")["MACD"]
        .transform(
            lambda x: x.ewm(
                span=9,
                adjust=False
            ).mean()
        )
    )

    df["MACD_Hist"] = (
        df["MACD"] - df["MACD_Signal"]
    )

    # -----------------------------------
    # RSI
    # -----------------------------------

    delta = (
        df.groupby("Ticker")["Close"]
        .diff()
    )

    gain = (
        delta.where(delta > 0, 0)
        .groupby(df["Ticker"])
        .transform(
            lambda x: x.rolling(14).mean()
        )
    )

    loss = (
        (-delta.where(delta < 0, 0))
        .groupby(df["Ticker"])
        .transform(
            lambda x: x.rolling(14).mean()
        )
    )

    rs = gain / loss

    df["RSI"] = 100 - (
        100 / (1 + rs)
    )

    # -----------------------------------
    # VOLATILITY
    # -----------------------------------

    df["Volatility"] = (
        df.groupby("Ticker")["Return"]
        .transform(
            lambda x: x.rolling(5).std()
        )
    )

    # -----------------------------------
    # BOLLINGER BANDS
    # -----------------------------------

    rolling_mean = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.rolling(20).mean()
        )
    )

    rolling_std = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.rolling(20).std()
        )
    )

    upper_band = rolling_mean + (
        2 * rolling_std
    )

    lower_band = rolling_mean - (
        2 * rolling_std
    )

    # Position between lower and upper band
    df["Bollinger_Position"] = (
        (df["Close"] - lower_band) /
        (upper_band - lower_band)
    )

    # -----------------------------------
    # VOLUME
    # -----------------------------------

    df["Volume_Change"] = (
        df.groupby("Ticker")["Volume"]
        .pct_change()
    )
    # -----------------------------------
    # VOLUME RATIO
    # -----------------------------------

    df["Volume_MA5"] = (
        df.groupby("Ticker")["Volume"]
        .transform(
            lambda x: x.rolling(5).mean()
        )
    )

    df["Volume_Ratio"] = (
        df["Volume"] / df["Volume_MA5"]
    )
    # -----------------------------------
    # FUTURE RETURN
    # -----------------------------------

    df["Future_Return"] = (
        df.groupby("Ticker")["Close"].shift(-5)
        / df["Close"]
    ) - 1

    # -----------------------------------
    # LABEL
    # -----------------------------------

    # def label(x):

    #     if x > 0.003:
    #         return "BUY"

    #     elif x < -0.003:
    #         return "SELL"

    #     else:
    #         return "HOLD"

    # df["Decision"] = (
    #     df["Future_Return"]
    #     .apply(label)
    # )

    # -----------------------------------
    # REMOVE INVALID ROWS
    # -----------------------------------

    df.dropna(inplace=True)

    return df


if __name__ == "__main__":

    import argparse

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--sentiment-file",
        default="src/data/historical_sentiment.csv"
    )

    parser.add_argument(
        "--output",
        default="src/data/processed_data.csv"
    )

    args = parser.parse_args()

    df = pd.read_csv(
        "src/data/stock_data.csv"
    )

    sentiment_df = pd.read_csv(
        args.sentiment_file
    )

    df = create_features(
        df,
        sentiment_df
    )

    df.to_csv(
        args.output,
        index=False
    )

    print("Features created!")
