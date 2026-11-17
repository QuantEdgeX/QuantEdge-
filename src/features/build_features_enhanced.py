import pandas as pd
import numpy as np


def create_enhanced_features(df, sentiment_df):

    # ============================================================
    # VALIDATE AND NORMALIZE INPUT DATA
    # ============================================================

    df = df.copy()
    sentiment_df = sentiment_df.copy()

    required_stock_columns = {
        "Date", "Ticker", "Open", "High", "Low", "Close", "Volume"
    }
    required_sentiment_columns = {
        "date", "ticker", "sentiment_score"
    }

    missing_stock = required_stock_columns - set(df.columns)
    missing_sentiment = required_sentiment_columns - set(sentiment_df.columns)

    if missing_stock:
        raise ValueError(
            f"Stock dataset is missing required columns: {sorted(missing_stock)}"
        )

    if missing_sentiment:
        raise ValueError(
            "Sentiment dataset is missing required columns: "
            f"{sorted(missing_sentiment)}. "
            f"Available columns: {df.columns.tolist() if not missing_stock else sentiment_df.columns.tolist()}"
        )

    # Normalize dates and ticker symbols before merging.
    df["Date"] = pd.to_datetime(df["Date"], errors="coerce").dt.normalize()
    sentiment_df["date"] = pd.to_datetime(
        sentiment_df["date"], errors="coerce"
    ).dt.normalize()

    df["Ticker"] = df["Ticker"].astype(str).str.strip().str.upper()
    sentiment_df["ticker"] = (
        sentiment_df["ticker"].astype(str).str.strip().str.upper()
    )

    if df[["Date", "Ticker"]].isna().any().any():
        raise ValueError("Stock data contains invalid Date or Ticker values.")

    if sentiment_df[["date", "ticker"]].isna().any().any():
        raise ValueError("Sentiment data contains invalid date or ticker values.")

    # Make sure the new sentiment file has one row per date and ticker.
    duplicate_mask = sentiment_df.duplicated(["date", "ticker"], keep=False)
    if duplicate_mask.any():
        examples = sentiment_df.loc[
            duplicate_mask, ["date", "ticker"]
        ].head(10)
        raise ValueError(
            "Duplicate date-ticker rows found in sentiment data. "
            "Aggregate them before merging. Examples:\n"
            f"{examples.to_string(index=False)}"
        )

    # Ensure the stock data also has one row per date and ticker.
    if df.duplicated(["Date", "Ticker"]).any():
        raise ValueError(
            "Stock data contains duplicate Date-Ticker rows. "
            "Resolve duplicates before using a one-to-one merge."
        )

    # Convert sentiment fields to numeric where applicable.
    numeric_sentiment_columns = [
        "sentiment_score",
        "article_count",
        "relevance_weight_sum",
        "n_candidates",
        "n_unscored",
        "has_news",
    ]

    for column in numeric_sentiment_columns:
        if column in sentiment_df.columns:
            sentiment_df[column] = pd.to_numeric(
                sentiment_df[column], errors="coerce"
            )

    # Rename keys to match the stock dataset.
    sentiment_df = sentiment_df.rename(
        columns={"date": "Date", "ticker": "Ticker"}
    )

    # Keep the stock rows and attach sentiment for the SAME ticker and date.
    df = df.merge(
        sentiment_df,
        on=["Date", "Ticker"],
        how="left",
        validate="one_to_one",
        indicator="_sentiment_merge"
    )

    matched_rows = int((df["_sentiment_merge"] == "both").sum())
    unmatched_rows = int((df["_sentiment_merge"] == "left_only").sum())

    print(
        f"Sentiment matches: {matched_rows:,}/{len(df):,} "
        f"({matched_rows / max(len(df), 1):.2%})"
    )
    print(f"Stock rows without a sentiment record: {unmatched_rows:,}")

    df.drop(columns=["_sentiment_merge"], inplace=True)

    # Missing sentiment means no matching scored news record.
    # Keep has_news/article counts so the model can distinguish missing news.
    df["sentiment_score"] = df["sentiment_score"].fillna(0)

    if "has_news" in df.columns:
        df["has_news"] = df["has_news"].fillna(0)

    for column in [
        "article_count",
        "relevance_weight_sum",
        "n_candidates",
        "n_unscored",
    ]:
        if column in df.columns:
            df[column] = df[column].fillna(0)

    print("Ticker-wise, date-wise sentiment merged successfully!")

    # ============================================================
    # SORT
    # ============================================================

    df = df.sort_values(
        by=["Ticker", "Date"]
    ).reset_index(drop=True)

    # ============================================================
    # BASIC RETURNS
    # ============================================================

    df["Return"] = (
        df.groupby("Ticker")["Close"]
        .pct_change()
    )

    df["Return_3D"] = (
        df.groupby("Ticker")["Close"]
        .pct_change(3)
    )

    df["Return_5D"] = (
        df.groupby("Ticker")["Close"]
        .pct_change(5)
    )

    df["Return_10D"] = (
        df.groupby("Ticker")["Close"]
        .pct_change(10)
    )

    # ============================================================
    # EXISTING MOVING AVERAGES
    # ============================================================

    df["MA5"] = (
        df.groupby("Ticker")["Close"]
        .transform(lambda x: x.rolling(5).mean())
    )

    df["MA10"] = (
        df.groupby("Ticker")["Close"]
        .transform(lambda x: x.rolling(10).mean())
    )

    df["Price_MA5_Ratio"] = (
        df["Close"] / df["MA5"] - 1
    )

    df["Price_MA10_Ratio"] = (
        df["Close"] / df["MA10"] - 1
    )

    # ============================================================
    # EXISTING EMA
    # ============================================================

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

    # ============================================================
    # MACD
    # ============================================================

    df["MACD"] = (
        df["EMA12"] - df["EMA26"]
    )

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

    # ============================================================
    # RSI
    # ============================================================

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

    # ============================================================
    # EXISTING VOLATILITY
    # ============================================================

    df["Volatility"] = (
        df.groupby("Ticker")["Return"]
        .transform(
            lambda x: x.rolling(5).std()
        )
    )

    # ============================================================
    # BOLLINGER BANDS
    # ============================================================

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

    df["Bollinger_Position"] = (
        (df["Close"] - lower_band)
        / (upper_band - lower_band)
    )

    # ============================================================
    # EXISTING VOLUME FEATURES
    # ============================================================

    df["Volume_Change"] = (
        df.groupby("Ticker")["Volume"]
        .pct_change()
    )

    df["Volume_MA5"] = (
        df.groupby("Ticker")["Volume"]
        .transform(
            lambda x: x.rolling(5).mean()
        )
    )

    df["Volume_Ratio"] = (
        df["Volume"] / df["Volume_MA5"]
    )

    # ============================================================
    # ============================================================
    # NEW ENHANCED TECHNICAL FEATURES
    # ============================================================
    # ============================================================

    # ------------------------------------------------------------
    # 1. LONGER-TERM MOMENTUM
    # ------------------------------------------------------------

    df["ROC_20"] = (
        df.groupby("Ticker")["Close"]
        .pct_change(20)
    )

    # ------------------------------------------------------------
    # 2. ADDITIONAL EMA TREND FEATURES
    # ------------------------------------------------------------

    df["EMA5"] = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.ewm(
                span=5,
                adjust=False
            ).mean()
        )
    )

    df["EMA20"] = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.ewm(
                span=20,
                adjust=False
            ).mean()
        )
    )

    df["EMA50"] = (
        df.groupby("Ticker")["Close"]
        .transform(
            lambda x: x.ewm(
                span=50,
                adjust=False
            ).mean()
        )
    )

    # Price relative to longer-term EMAs

    df["Price_EMA20_Ratio"] = (
        df["Close"] / df["EMA20"] - 1
    )

    df["Price_EMA50_Ratio"] = (
        df["Close"] / df["EMA50"] - 1
    )

    # EMA crossover relationships

    df["EMA5_EMA20_Ratio"] = (
        df["EMA5"] / df["EMA20"] - 1
    )

    df["EMA20_EMA50_Ratio"] = (
        df["EMA20"] / df["EMA50"] - 1
    )

    # ------------------------------------------------------------
    # 3. ATR / VOLATILITY
    # ------------------------------------------------------------

    prev_close = (
        df.groupby("Ticker")["Close"]
        .shift(1)
    )

    true_range = pd.concat(
        [
            df["High"] - df["Low"],
            (df["High"] - prev_close).abs(),
            (df["Low"] - prev_close).abs()
        ],
        axis=1
    ).max(axis=1)

    df["ATR14"] = (
        true_range
        .groupby(df["Ticker"])
        .transform(
            lambda x: x.ewm(
                alpha=1 / 14,
                adjust=False
            ).mean()
        )
    )

    # Normalize ATR by price

    df["ATR14_Ratio"] = (
        df["ATR14"] / df["Close"]
    )

    # ------------------------------------------------------------
    # 4. MULTIPLE VOLATILITY WINDOWS
    # ------------------------------------------------------------

    df["Volatility_10"] = (
        df.groupby("Ticker")["Return"]
        .transform(
            lambda x: x.rolling(10).std()
        )
    )

    df["Volatility_20"] = (
        df.groupby("Ticker")["Return"]
        .transform(
            lambda x: x.rolling(20).std()
        )
    )

    # ------------------------------------------------------------
    # 5. STOCHASTIC OSCILLATOR
    # ------------------------------------------------------------

    rolling_high_14 = (
        df.groupby("Ticker")["High"]
        .transform(
            lambda x: x.rolling(14).max()
        )
    )

    rolling_low_14 = (
        df.groupby("Ticker")["Low"]
        .transform(
            lambda x: x.rolling(14).min()
        )
    )

    stochastic_range = (
        rolling_high_14 - rolling_low_14
    )

    df["Stochastic_K_14"] = (
        100
        * (df["Close"] - rolling_low_14)
        / stochastic_range
    )

    df["Stochastic_D_3"] = (
        df.groupby("Ticker")["Stochastic_K_14"]
        .transform(
            lambda x: x.rolling(3).mean()
        )
    )

    # ------------------------------------------------------------
    # 6. WILLIAMS %R
    # ------------------------------------------------------------

    df["Williams_R_14"] = (
        -100
        * (rolling_high_14 - df["Close"])
        / stochastic_range
    )

    # ------------------------------------------------------------
    # 7. ADX
    # ------------------------------------------------------------

    high_diff = (
        df.groupby("Ticker")["High"]
        .diff()
    )

    low_diff = (
        -df.groupby("Ticker")["Low"]
        .diff()
    )

    plus_dm = pd.Series(
        np.where(
            (high_diff > low_diff) & (high_diff > 0),
            high_diff,
            0.0
        ),
        index=df.index
    )

    minus_dm = pd.Series(
        np.where(
            (low_diff > high_diff) & (low_diff > 0),
            low_diff,
            0.0
        ),
        index=df.index
    )

    plus_dm_smooth = (
        plus_dm
        .groupby(df["Ticker"])
        .transform(
            lambda x: x.ewm(
                alpha=1 / 14,
                adjust=False
            ).mean()
        )
    )

    minus_dm_smooth = (
        minus_dm
        .groupby(df["Ticker"])
        .transform(
            lambda x: x.ewm(
                alpha=1 / 14,
                adjust=False
            ).mean()
        )
    )

    plus_di = (
        100 * plus_dm_smooth / df["ATR14"]
    )

    minus_di = (
        100 * minus_dm_smooth / df["ATR14"]
    )

    di_sum = plus_di + minus_di

    dx = (
        100
        * (plus_di - minus_di).abs()
        / di_sum.replace(0, np.nan)
    )

    df["ADX14"] = (
        dx.groupby(df["Ticker"])
        .transform(
            lambda x: x.ewm(
                alpha=1 / 14,
                adjust=False
            ).mean()
        )
    )

    # ------------------------------------------------------------
    # 8. BOLLINGER BAND WIDTH
    # ------------------------------------------------------------

    df["Bollinger_Width"] = (
        (upper_band - lower_band)
        / rolling_mean
    )

    # ------------------------------------------------------------
    # 9. DAILY PRICE STRUCTURE
    # ------------------------------------------------------------

    df["High_Low_Range"] = (
        (df["High"] - df["Low"])
        / df["Close"]
    )

    df["Candle_Body"] = (
        (df["Close"] - df["Open"])
        / df["Open"]
    )

    # Gap between previous close and today's open

    df["Gap_Return"] = (
        df["Open"] / prev_close - 1
    )

    # ------------------------------------------------------------
    # 10. LONGER-TERM VOLUME FEATURES
    # ------------------------------------------------------------

    df["Volume_MA20"] = (
        df.groupby("Ticker")["Volume"]
        .transform(
            lambda x: x.rolling(20).mean()
        )
    )

    df["Volume_Ratio_20"] = (
        df["Volume"] / df["Volume_MA20"]
    )

    df["Volume_ROC_10"] = (
        df.groupby("Ticker")["Volume"]
        .pct_change(10)
    )

    # ------------------------------------------------------------
    # 11. LAGGED INFORMATION
    # ------------------------------------------------------------

    df["Return_Lag1"] = (
        df.groupby("Ticker")["Return"]
        .shift(1)
    )

    df["Return_Lag5"] = (
        df.groupby("Ticker")["Return"]
        .shift(5)
    )

    df["RSI_Lag1"] = (
        df.groupby("Ticker")["RSI"]
        .shift(1)
    )

    df["MACD_Hist_Lag1"] = (
        df.groupby("Ticker")["MACD_Hist"]
        .shift(1)
    )

    # ============================================================
    # FUTURE RETURN
    # ============================================================

    # IMPORTANT:
    # This is the target-generation variable.
    # It is NOT used as an input feature.

    df["Future_Return"] = (
        df.groupby("Ticker")["Close"].shift(-5)
        / df["Close"]
    ) - 1

    # ============================================================
    # REMOVE INVALID ROWS
    # ============================================================

    df.replace(
        [np.inf, -np.inf],
        np.nan,
        inplace=True
    )

    df.dropna(
        inplace=True
    )

    # ============================================================
    # FINAL SORT
    # ============================================================

    df = df.sort_values(
        by=["Ticker", "Date"]
    ).reset_index(drop=True)

    return df


if __name__ == "__main__":

    print("=" * 60)
    print("BUILDING ENHANCED FEATURES")
    print("=" * 60)

    # ------------------------------------------------------------
    # LOAD DATA
    # ------------------------------------------------------------

    df = pd.read_csv(
        "src/data/stock_data.csv"
    )

    sentiment_df = pd.read_csv(
        "src/data/daily_sentiment_finbert.csv"
    )

    print(f"Raw stock rows: {len(df):,}")
    print(f"Raw stock columns: {len(df.columns)}")

    # ------------------------------------------------------------
    # CREATE FEATURES
    # ------------------------------------------------------------

    enhanced_df = create_enhanced_features(
        df,
        sentiment_df
    )

    # ------------------------------------------------------------
    # SAVE SEPARATELY
    # ------------------------------------------------------------

    output_path = (
        "src/data/processed_data_enhanced.csv"
    )

    enhanced_df.to_csv(
        output_path,
        index=False
    )

    # Verify that the new sentiment columns are present in the output.
    sentiment_output_columns = [
        column for column in [
            "sentiment_score",
            "article_count",
            "has_news",
            "relevance_weight_sum",
            "n_candidates",
            "n_unscored",
        ]
        if column in enhanced_df.columns
    ]
    print("Sentiment columns in output:", sentiment_output_columns)

    # ------------------------------------------------------------
    # SUMMARY
    # ------------------------------------------------------------

    print()
    print("=" * 60)
    print("ENHANCED FEATURE DATASET CREATED")
    print("=" * 60)

    print(f"Rows:    {len(enhanced_df):,}")
    print(f"Columns: {len(enhanced_df.columns)}")

    print()
    print("Output:")
    print(output_path)

    print()
    print("New technical features:")

    new_features = [
        "ROC_20",
        "EMA5",
        "EMA20",
        "EMA50",
        "Price_EMA20_Ratio",
        "Price_EMA50_Ratio",
        "EMA5_EMA20_Ratio",
        "EMA20_EMA50_Ratio",
        "ATR14",
        "ATR14_Ratio",
        "Volatility_10",
        "Volatility_20",
        "Stochastic_K_14",
        "Stochastic_D_3",
        "Williams_R_14",
        "ADX14",
        "Bollinger_Width",
        "High_Low_Range",
        "Candle_Body",
        "Gap_Return",
        "Volume_MA20",
        "Volume_Ratio_20",
        "Volume_ROC_10",
        "Return_Lag1",
        "Return_Lag5",
        "RSI_Lag1",
        "MACD_Hist_Lag1"
    ]

    for feature in new_features:
        print(f"  ✓ {feature}")

    print()
    print("Enhanced feature creation completed.")