import pandas as pd
import numpy as np


# ============================================================
# CONFIGURATION
# ============================================================

DATA_PATH = "src/data/processed_data.csv"

TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
TEST_RATIO = 0.15


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

    "sentiment_score"
]


# ============================================================
# LABEL MAP
# ============================================================

LABEL_MAP = {
    "BUY": 0,
    "HOLD": 1,
    "SELL": 2
}


# ============================================================
# CREATE LABELS
# ============================================================

def create_labels(
    future_returns,
    sell_threshold,
    buy_threshold
):

    labels = np.full(
        len(future_returns),
        "HOLD",
        dtype=object
    )

    labels[
        future_returns <= sell_threshold
    ] = "SELL"

    labels[
        future_returns >= buy_threshold
    ] = "BUY"

    return labels


# ============================================================
# PREPARE DATA
# ============================================================

def prepare_data():

    print("\n========== LOADING DATA ==========")

    df = pd.read_csv(DATA_PATH)

    df["Date"] = pd.to_datetime(
        df["Date"]
    )

    df = df.sort_values(
        ["Ticker", "Date"]
    ).reset_index(drop=True)


    X_train_all = []
    y_train_all = []

    X_val_all = []
    y_val_all = []

    X_test_all = []
    y_test_all = []

    test_ids_all = []


    # ========================================================
    # PROCESS EACH STOCK
    # ========================================================

    for ticker, stock_df in df.groupby("Ticker"):

        stock_df = stock_df.sort_values(
            "Date"
        ).reset_index(drop=True)


        # ----------------------------------------------------
        # CHRONOLOGICAL SPLIT
        # ----------------------------------------------------

        n = len(stock_df)

        train_end = int(
            n * TRAIN_RATIO
        )

        val_end = int(
            n * (TRAIN_RATIO + VAL_RATIO)
        )


        train_df = stock_df.iloc[
            :train_end
        ].copy()

        val_df = stock_df.iloc[
            train_end:val_end
        ].copy()

        test_df = stock_df.iloc[
            val_end:
        ].copy()


        print(
            f"{ticker}: "
            f"{len(train_df)} train | "
            f"{len(val_df)} validation | "
            f"{len(test_df)} test"
        )


        # ----------------------------------------------------
        # TRAIN-ONLY LABEL THRESHOLDS
        # ----------------------------------------------------

        sell_threshold = np.percentile(
            train_df["Future_Return"].values,
            30
        )

        buy_threshold = np.percentile(
            train_df["Future_Return"].values,
            70
        )


        print(
            f"  SELL <= {sell_threshold:.5f} | "
            f"BUY >= {buy_threshold:.5f}"
        )


        # ----------------------------------------------------
        # CREATE LABELS
        # ----------------------------------------------------

        train_df["Decision"] = create_labels(
            train_df["Future_Return"].values,
            sell_threshold,
            buy_threshold
        )

        val_df["Decision"] = create_labels(
            val_df["Future_Return"].values,
            sell_threshold,
            buy_threshold
        )

        test_df["Decision"] = create_labels(
            test_df["Future_Return"].values,
            sell_threshold,
            buy_threshold
        )


        # ----------------------------------------------------
        # FEATURES
        # ----------------------------------------------------

        X_train_all.append(
            train_df[FEATURES].values
        )

        y_train_all.append(
            train_df["Decision"]
            .map(LABEL_MAP)
            .values
        )


        X_val_all.append(
            val_df[FEATURES].values
        )

        y_val_all.append(
            val_df["Decision"]
            .map(LABEL_MAP)
            .values
        )


        X_test_all.append(
            test_df[FEATURES].values
        )

        y_test_all.append(
            test_df["Decision"]
            .map(LABEL_MAP)
            .values
        )


        # ----------------------------------------------------
        # TEST IDS
        # ----------------------------------------------------

        test_ids_all.append(
            test_df[
                ["Ticker", "Date"]
            ].copy()
        )


    # ========================================================
    # COMBINE STOCKS
    # ========================================================

    X_train = np.concatenate(
        X_train_all
    )

    y_train = np.concatenate(
        y_train_all
    )

    X_val = np.concatenate(
        X_val_all
    )

    y_val = np.concatenate(
        y_val_all
    )

    X_test = np.concatenate(
        X_test_all
    )

    y_test = np.concatenate(
        y_test_all
    )

    test_ids = pd.concat(
        test_ids_all,
        ignore_index=True
    )


    # ========================================================
    # INFORMATION
    # ========================================================

    print(
        "\n========== DATA =========="
    )

    print(
        "X_train:",
        X_train.shape
    )

    print(
        "X_val  :",
        X_val.shape
    )

    print(
        "X_test :",
        X_test.shape
    )

    print(
        "\nFeatures:",
        len(FEATURES)
    )

    print(
        "Test IDs:",
        len(test_ids)
    )


    # ========================================================
    # CLASS DISTRIBUTION
    # ========================================================

    print(
        "\n========== CLASS DISTRIBUTION =========="
    )

    print(
        "Train:",
        np.bincount(
            y_train,
            minlength=3
        )
    )

    print(
        "Val  :",
        np.bincount(
            y_val,
            minlength=3
        )
    )

    print(
        "Test :",
        np.bincount(
            y_test,
            minlength=3
        )
    )


    return (
        X_train,
        y_train,
        X_val,
        y_val,
        X_test,
        y_test,
        test_ids
    )


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    prepare_data()