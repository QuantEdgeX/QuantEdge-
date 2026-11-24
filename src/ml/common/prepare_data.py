import pandas as pd
import numpy as np


# ============================================================
# CONFIGURATION
# ============================================================

DATA_PATH = "src/data/processed_data.csv"

TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
TEST_RATIO = 0.15

# Future_Return looks 5 trading days ahead.
# Therefore we leave a 5-row embargo between splits.
EMBARGO_DAYS = 5


# ============================================================
# FEATURES
# ============================================================

FEATURES = [
    "Return",
    "Return_3D",
    "Return_5D",
    "Return_10D",
    "Price_MA5_Ratio",
    "Price_MA10_Ratio",
    "RSI",
    "Volatility",
    "MACD",
    "MACD_Signal",
    "MACD_Hist",
    "Bollinger_Position",
    "Volume_Change",
    "Volume_Ratio",
    "sentiment_score",
]


# ============================================================
# LABELS
# ============================================================

BUY = 1
SELL = 0


# ============================================================
# CREATE BINARY LABELS
# ============================================================

def create_binary_labels(
    future_returns,
    sell_threshold,
    buy_threshold,
):
    """
    Convert Future_Return into BUY/SELL/NEUTRAL.

    SELL:
        Future_Return <= sell_threshold

    BUY:
        Future_Return >= buy_threshold

    NEUTRAL:
        Between the two thresholds.
    """

    labels = np.full(
        len(future_returns),
        -1,
        dtype=int,
    )

    labels[
        future_returns <= sell_threshold
    ] = SELL

    labels[
        future_returns >= buy_threshold
    ] = BUY

    return labels


# ============================================================
# PREPARE ONE TICKER
# ============================================================

def prepare_ticker(stock_df, ticker):
    """
    Prepare train, validation and test data for one ticker.
    """

    stock_df = (
        stock_df
        .sort_values("Date")
        .reset_index(drop=True)
        .copy()
    )

    n = len(stock_df)

    # --------------------------------------------------------
    # CHRONOLOGICAL SPLIT POINTS
    # --------------------------------------------------------

    train_end = int(n * TRAIN_RATIO)
    val_end = int(n * (TRAIN_RATIO + VAL_RATIO))

    # --------------------------------------------------------
    # APPLY EMBARGO
    # --------------------------------------------------------

    train_df = stock_df.iloc[:train_end].copy()

    val_start = train_end + EMBARGO_DAYS

    val_df = stock_df.iloc[
        val_start:val_end
    ].copy()

    test_start = val_end + EMBARGO_DAYS

    test_df = stock_df.iloc[
        test_start:
    ].copy()

    # --------------------------------------------------------
    # TRAIN-ONLY THRESHOLDS
    # --------------------------------------------------------

    sell_threshold = np.percentile(
        train_df["Future_Return"].values,
        30,
    )

    buy_threshold = np.percentile(
        train_df["Future_Return"].values,
        70,
    )

    # --------------------------------------------------------
    # CREATE LABELS
    # --------------------------------------------------------

    train_df["Label"] = create_binary_labels(
        train_df["Future_Return"].values,
        sell_threshold,
        buy_threshold,
    )

    val_df["Label"] = create_binary_labels(
        val_df["Future_Return"].values,
        sell_threshold,
        buy_threshold,
    )

    test_df["Label"] = create_binary_labels(
        test_df["Future_Return"].values,
        sell_threshold,
        buy_threshold,
    )

    # --------------------------------------------------------
    # REMOVE NEUTRAL ROWS
    # --------------------------------------------------------
    #
    # -1 means the Future_Return is in the middle 40%.
    #
    # We don't train the directional models on these rows.
    # We keep the information separately so that the final
    # evaluation can understand what happens to neutral cases.
    # --------------------------------------------------------

    train_model_df = train_df[
        train_df["Label"] != -1
    ].copy()

    val_model_df = val_df[
        val_df["Label"] != -1
    ].copy()

    test_model_df = test_df[
        test_df["Label"] != -1
    ].copy()

    return (
        train_model_df,
        val_model_df,
        test_model_df,
        train_df,
        val_df,
        test_df,
        sell_threshold,
        buy_threshold,
    )


# ============================================================
# PREPARE COMPLETE DATASET
# ============================================================

def prepare_data():

    print("\n" + "=" * 60)
    print("LOADING PROCESSED DATA")
    print("=" * 60)

    df = pd.read_csv(DATA_PATH)

    df["Date"] = pd.to_datetime(
        df["Date"]
    )

    df = (
        df
        .sort_values(["Ticker", "Date"])
        .reset_index(drop=True)
    )

    print(f"Total rows: {len(df):,}")
    print(f"Tickers: {df['Ticker'].nunique()}")
    print(
        f"Date range: "
        f"{df['Date'].min().date()} "
        f"to "
        f"{df['Date'].max().date()}"
    )

    # ========================================================
    # STORAGE
    # ========================================================

    train_parts = []
    val_parts = []
    test_parts = []

    all_train_parts = []
    all_val_parts = []
    all_test_parts = []

    threshold_records = []

    # ========================================================
    # PROCESS EACH TICKER
    # ========================================================

    print("\n" + "=" * 60)
    print("PROCESSING TICKERS")
    print("=" * 60)

    for ticker, stock_df in df.groupby("Ticker"):

        (
            train_model_df,
            val_model_df,
            test_model_df,
            train_all_df,
            val_all_df,
            test_all_df,
            sell_threshold,
            buy_threshold,
        ) = prepare_ticker(
            stock_df,
            ticker,
        )

        # ----------------------------------------------------
        # STORE MODEL DATA
        # ----------------------------------------------------

        train_parts.append(
            train_model_df
        )

        val_parts.append(
            val_model_df
        )

        test_parts.append(
            test_model_df
        )

        # ----------------------------------------------------
        # STORE ALL DATA INCLUDING NEUTRAL
        # ----------------------------------------------------

        all_train_parts.append(
            train_all_df
        )

        all_val_parts.append(
            val_all_df
        )

        all_test_parts.append(
            test_all_df
        )

        # ----------------------------------------------------
        # SAVE THRESHOLDS
        # ----------------------------------------------------

        threshold_records.append(
            {
                "Ticker": ticker,
                "Sell_Threshold": sell_threshold,
                "Buy_Threshold": buy_threshold,
            }
        )

        print(
            f"{ticker}: "
            f"train={len(train_model_df):4d} | "
            f"val={len(val_model_df):4d} | "
            f"test={len(test_model_df):4d} | "
            f"SELL <= {sell_threshold:.5f} | "
            f"BUY >= {buy_threshold:.5f}"
        )

    # ========================================================
    # COMBINE TICKERS
    # ========================================================

    train_df = pd.concat(
        train_parts,
        ignore_index=True,
    )

    val_df = pd.concat(
        val_parts,
        ignore_index=True,
    )

    test_df = pd.concat(
        test_parts,
        ignore_index=True,
    )

    all_train_df = pd.concat(
        all_train_parts,
        ignore_index=True,
    )

    all_val_df = pd.concat(
        all_val_parts,
        ignore_index=True,
    )

    all_test_df = pd.concat(
        all_test_parts,
        ignore_index=True,
    )

    thresholds_df = pd.DataFrame(
        threshold_records
    )

    # ========================================================
    # CREATE X / y
    # ========================================================

    X_train = train_df[
        FEATURES
    ].to_numpy()

    y_train = train_df[
        "Label"
    ].to_numpy()

    X_val = val_df[
        FEATURES
    ].to_numpy()

    y_val = val_df[
        "Label"
    ].to_numpy()

    X_test = test_df[
        FEATURES
    ].to_numpy()

    y_test = test_df[
        "Label"
    ].to_numpy()

    # ========================================================
    # INFORMATION
    # ========================================================

    print("\n" + "=" * 60)
    print("FINAL DATASET")
    print("=" * 60)

    print(
        f"X_train: {X_train.shape}"
    )

    print(
        f"X_val  : {X_val.shape}"
    )

    print(
        f"X_test : {X_test.shape}"
    )

    print(
        f"Features: {len(FEATURES)}"
    )

    # ========================================================
    # CLASS DISTRIBUTION
    # ========================================================

    print("\n" + "=" * 60)
    print("MODEL CLASS DISTRIBUTION")
    print("=" * 60)

    print(
        "Train:",
        {
            "SELL": int(
                np.sum(y_train == SELL)
            ),
            "BUY": int(
                np.sum(y_train == BUY)
            ),
        },
    )

    print(
        "Val:",
        {
            "SELL": int(
                np.sum(y_val == SELL)
            ),
            "BUY": int(
                np.sum(y_val == BUY)
            ),
        },
    )

    print(
        "Test:",
        {
            "SELL": int(
                np.sum(y_test == SELL)
            ),
            "BUY": int(
                np.sum(y_test == BUY)
            ),
        },
    )

    # ========================================================
    # NEUTRAL DISTRIBUTION
    # ========================================================

    print("\n" + "=" * 60)
    print("NEUTRAL ROWS")
    print("=" * 60)

    for name, split_df in [
        ("Train", all_train_df),
        ("Validation", all_val_df),
        ("Test", all_test_df),
    ]:

        neutral_count = int(
            np.sum(
                split_df["Label"] == -1
            )
        )

        total_count = len(split_df)

        percentage = (
            neutral_count / total_count * 100
            if total_count > 0
            else 0
        )

        print(
            f"{name}: "
            f"{neutral_count:,} neutral / "
            f"{total_count:,} total "
            f"({percentage:.2f}%)"
        )

    # ========================================================
    # RETURN EVERYTHING
    # ========================================================

    return {
        "X_train": X_train,
        "y_train": y_train,

        "X_val": X_val,
        "y_val": y_val,

        "X_test": X_test,
        "y_test": y_test,

        "train_df": train_df,
        "val_df": val_df,
        "test_df": test_df,

        "all_train_df": all_train_df,
        "all_val_df": all_val_df,
        "all_test_df": all_test_df,

        "thresholds": thresholds_df,

        "features": FEATURES,
    }


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    data = prepare_data()

    print("\nData preparation completed successfully.")
    
