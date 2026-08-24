import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler

DATA_PATH = "src/data/processed_data.csv"

FEATURES = [
    "Return",
    "Price_MA5_Ratio",
    "Price_MA10_Ratio",
    "RSI",
    "Volatility",
    "MACD",
    "MACD_Signal",
    "MACD_Hist",
    "Bollinger_Position",
    "Volume_Change",
    "sentiment_score"
]

SEQUENCE_LENGTH = 60
TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
TEST_RATIO = 0.15

HOLD_BAND = 0.20  

def label_from_quantiles(future_returns, low_q, high_q):
    labels = np.full(len(future_returns), "HOLD", dtype=object)
    labels[future_returns >= high_q] = "BUY"
    labels[future_returns <= low_q] = "SELL"
    return labels


LABEL_MAP = {"BUY": 0, "HOLD": 1, "SELL": 2}


def prepare_sequences():
    df = pd.read_csv(DATA_PATH)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values(["Ticker", "Date"]).reset_index(drop=True)

    X_train_all, y_train_all = [], []
    X_val_all, y_val_all = [], []
    X_test_all, y_test_all = [], []
    scalers = {}
    thresholds = {}

    for ticker, stock_df in df.groupby("Ticker"):
        stock_df = stock_df.sort_values("Date").reset_index(drop=True)

        n = len(stock_df)
        train_end = int(n * TRAIN_RATIO)
        val_end = int(n * (TRAIN_RATIO + VAL_RATIO))

        train_df = stock_df.iloc[:train_end].copy()
        val_df = stock_df.iloc[train_end:val_end].copy()
        test_df = stock_df.iloc[val_end:].copy()

        print(
            f"{ticker}: "
            f"{len(train_df)} train | "
            f"{len(val_df)} validation | "
            f"{len(test_df)} test"
        )

        # -----------------------------------
        # LABELS: quantile thresholds fit on TRAIN ONLY
        # -----------------------------------
        half_band = HOLD_BAND / 2.0
        low_q = train_df["Future_Return"].quantile(0.5 - half_band)
        high_q = train_df["Future_Return"].quantile(0.5 + half_band)
        thresholds[ticker] = (low_q, high_q)

        train_df["Decision"] = label_from_quantiles(
            train_df["Future_Return"].values, low_q, high_q
        )
        val_df["Decision"] = label_from_quantiles(
            val_df["Future_Return"].values, low_q, high_q
        )
        test_df["Decision"] = label_from_quantiles(
            test_df["Future_Return"].values, low_q, high_q
        )

        # -----------------------------------
        # SCALE (fit only on training data)
        # -----------------------------------
        scaler = StandardScaler()
        train_features = scaler.fit_transform(train_df[FEATURES])
        val_features = scaler.transform(val_df[FEATURES])
        test_features = scaler.transform(test_df[FEATURES])
        scalers[ticker] = scaler

        train_labels = train_df["Decision"].map(LABEL_MAP).values
        val_labels = val_df["Decision"].map(LABEL_MAP).values
        test_labels = test_df["Decision"].map(LABEL_MAP).values

        # -----------------------------------
        # TRAIN SEQUENCES
        # -----------------------------------
        for i in range(SEQUENCE_LENGTH, len(train_features)):
            X_train_all.append(train_features[i - SEQUENCE_LENGTH:i])
            y_train_all.append(train_labels[i])

        # -----------------------------------
        # VALIDATION SEQUENCES (context from tail of train)
        # -----------------------------------
        val_context = np.concatenate(
            [train_features[-SEQUENCE_LENGTH:], val_features], axis=0
        )
        for i in range(SEQUENCE_LENGTH, len(val_context)):
            X_val_all.append(val_context[i - SEQUENCE_LENGTH:i])
            y_val_all.append(val_labels[i - SEQUENCE_LENGTH])

        # -----------------------------------
        # TEST SEQUENCES (context from tail of val)
        # -----------------------------------
        test_context = np.concatenate(
            [val_features[-SEQUENCE_LENGTH:], test_features], axis=0
        )
        for i in range(SEQUENCE_LENGTH, len(test_context)):
            X_test_all.append(test_context[i - SEQUENCE_LENGTH:i])
            y_test_all.append(test_labels[i - SEQUENCE_LENGTH])

    X_train = np.array(X_train_all)
    y_train = np.array(y_train_all)
    X_val = np.array(X_val_all)
    y_val = np.array(y_val_all)
    X_test = np.array(X_test_all)
    y_test = np.array(y_test_all)

    print("\n========== SEQUENCE DATA ==========")
    print("X_train shape:", X_train.shape)
    print("y_train shape:", y_train.shape)
    print("X_val shape:", X_val.shape)
    print("y_val shape:", y_val.shape)
    print("X_test shape:", X_test.shape)
    print("y_test shape:", y_test.shape)

    print("\nTraining class distribution:")
    print(np.bincount(y_train))
    print("\nValidation class distribution:")
    print(np.bincount(y_val))
    print("\nTesting class distribution:")
    print(np.bincount(y_test))

    print("\nPer-ticker Future_Return thresholds (low_q, high_q):")
    for ticker, (low_q, high_q) in thresholds.items():
        print(f"  {ticker}: {low_q:.5f}, {high_q:.5f}")

    return X_train, y_train, X_val, y_val, X_test, y_test, scalers


if __name__ == "__main__":
    prepare_sequences()