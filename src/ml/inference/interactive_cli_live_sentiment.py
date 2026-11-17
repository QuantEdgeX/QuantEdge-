# src/ml/inference/interactive_cli.py

import os
import sys
import json
import warnings

import joblib
import numpy as np
import pandas as pd
import yfinance as yf

from src.sentimentanalysis.live_finbert import get_live_sentiment

from catboost import CatBoostClassifier
from lightgbm import Booster
from xgboost import XGBClassifier


warnings.filterwarnings("ignore")


# ============================================================
# PATHS
# ============================================================

FINAL_MODEL_DIR = "src/ml/saved_models/final"

CONFIG_PATH = os.path.join(
    FINAL_MODEL_DIR,
    "final_config.json",
)


RF_MODEL_PATH = os.path.join(
    FINAL_MODEL_DIR,
    "random_forest_model.joblib",
)

CAT_MODEL_PATH = os.path.join(
    FINAL_MODEL_DIR,
    "catboost_model.cbm",
)

LGB_MODEL_PATH = os.path.join(
    FINAL_MODEL_DIR,
    "lightgbm_model.txt",
)

XGB_MODEL_PATH = os.path.join(
    FINAL_MODEL_DIR,
    "xgboost_model.json",
)


# ============================================================
# EXACT FINAL 33 FEATURES
# ============================================================

FEATURES = [
    "Return",
    "Return_3D",
    "Return_5D",
    "Return_10D",
    "ROC_20",
    "Price_MA5_Ratio",
    "Price_MA10_Ratio",
    "Price_EMA20_Ratio",
    "Price_EMA50_Ratio",
    "EMA5_EMA20_Ratio",
    "EMA20_EMA50_Ratio",
    "RSI",
    "RSI_Lag1",
    "Stochastic_K_14",
    "Stochastic_D_3",
    "Williams_R_14",
    "ADX14",
    "ATR14_Ratio",
    "Volatility",
    "Volatility_10",
    "Volatility_20",
    "Bollinger_Position",
    "Bollinger_Width",
    "High_Low_Range",
    "Candle_Body",
    "Gap_Return",
    "Volume_Change",
    "Volume_Ratio",
    "Volume_Ratio_20",
    "Volume_ROC_10",
    "Return_Lag1",
    "Return_Lag5",
    "MACD_Hist_Lag1",
    "sentiment_score",
]


# ============================================================
# CONFIG + MODELS
# ============================================================

def load_artifacts():
    if not os.path.exists(CONFIG_PATH):
        raise FileNotFoundError(
            f"Could not find:\n{CONFIG_PATH}\n"
            "Run final_evaluation_sentiment.py first so the saved models expect 34 features."
        )

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        config = json.load(f)

    required = [
        RF_MODEL_PATH,
        CAT_MODEL_PATH,
        LGB_MODEL_PATH,
        XGB_MODEL_PATH,
    ]

    missing = [
        path for path in required
        if not os.path.exists(path)
    ]

    if missing:
        raise FileNotFoundError(
            "Missing saved artifacts:\n"
            + "\n".join(missing)
        )

    print("\nLoading final QuantEdge models...")

    models = {
        "Random Forest": joblib.load(RF_MODEL_PATH),
        "CatBoost": CatBoostClassifier(),
        "LightGBM": Booster(
            model_file=LGB_MODEL_PATH
        ),
        "XGBoost": XGBClassifier(),
    }

    models["CatBoost"].load_model(
        CAT_MODEL_PATH
    )

    models["XGBoost"].load_model(
        XGB_MODEL_PATH
    )



    print("Models loaded successfully.")

    # The saved sentiment-enabled models must accept 34 features.
    # A simple structural check prevents accidentally using the old
    # 33-feature artifacts.
    expected_features = int(
        config.get("feature_count", 34)
    )

    if expected_features != 34:
        raise ValueError(
            "Loaded model configuration does not describe "
            "the 34-feature sentiment-enabled model. "
            f"feature_count={expected_features}"
        )

    return models, config


# ============================================================
# LIVE FINANCIAL SENTIMENT
# ============================================================

def score_live_sentiment(ticker):
    """
    Use the exact same live sentiment function as predict.py.
    All news retrieval and FinBERT scoring are handled by live_finbert.py.
    """
    print("\\n" + "=" * 60)
    print("FETCHING LIVE SENTIMENT")
    print("=" * 60)

    sentiment_score = float(get_live_sentiment(ticker))

    print(
        f"\\nLive FinBERT sentiment: "
        f"{sentiment_score:+.6f}"
    )

    return {
        "score": sentiment_score,
    }


def print_live_sentiment(sentiment):
    print("\\n  LIVE SENTIMENT")
    print("  " + "-" * 58)
    print(
        f"  Sentiment score   : "
        f"{sentiment['score']:+.6f}"
    )
    print(
        "  Sentiment source  : "
        "src.sentimentanalysis.live_finbert"
    )
    print("  " + "-" * 58)


# ============================================================
# MARKET DATA
# ============================================================

def fetch_market_data(ticker):
    data = yf.download(
        ticker,
        period="1y",
        interval="1d",
        auto_adjust=True,
        actions=False,
        progress=False,
    )

    if data is None or data.empty:
        raise ValueError(
            f"No Yahoo Finance data found for {ticker}."
        )

    if isinstance(data.columns, pd.MultiIndex):
        data.columns = [
            column[0]
            for column in data.columns
        ]

    data = data.reset_index()

    required = [
        "Date",
        "Open",
        "High",
        "Low",
        "Close",
        "Volume",
    ]

    missing = [
        column
        for column in required
        if column not in data.columns
    ]

    if missing:
        raise ValueError(
            "Missing market columns: "
            + ", ".join(missing)
        )

    data = data[required].copy()

    data["Date"] = pd.to_datetime(
        data["Date"]
    )

    for column in required[1:]:
        data[column] = pd.to_numeric(
            data[column],
            errors="coerce",
        )

    data.replace(
        [np.inf, -np.inf],
        np.nan,
        inplace=True,
    )

    data.dropna(
        subset=required[1:],
        inplace=True,
    )

    if len(data) < 60:
        raise ValueError(
            "Not enough historical data to build "
            "the 34 features."
        )

    return data.sort_values(
        "Date"
    ).reset_index(drop=True)


# ============================================================
# FEATURE ENGINEERING
# ============================================================

def build_features(data, sentiment_score):
    df = data.copy()

    # Basic returns
    df["Return"] = df["Close"].pct_change()
    df["Return_3D"] = df["Close"].pct_change(3)
    df["Return_5D"] = df["Close"].pct_change(5)
    df["Return_10D"] = df["Close"].pct_change(10)

    # Moving averages
    df["MA5"] = df["Close"].rolling(5).mean()
    df["MA10"] = df["Close"].rolling(10).mean()

    df["Price_MA5_Ratio"] = (
        df["Close"] / df["MA5"] - 1
    )

    df["Price_MA10_Ratio"] = (
        df["Close"] / df["MA10"] - 1
    )

    # EMA + MACD
    df["EMA12"] = df["Close"].ewm(
        span=12,
        adjust=False,
    ).mean()

    df["EMA26"] = df["Close"].ewm(
        span=26,
        adjust=False,
    ).mean()

    df["MACD"] = (
        df["EMA12"] - df["EMA26"]
    )

    df["MACD_Signal"] = df["MACD"].ewm(
        span=9,
        adjust=False,
    ).mean()

    df["MACD_Hist"] = (
        df["MACD"] - df["MACD_Signal"]
    )

    # RSI
    delta = df["Close"].diff()

    gain = delta.where(
        delta > 0,
        0,
    ).rolling(14).mean()

    loss = (
        -delta.where(
            delta < 0,
            0,
        )
    ).rolling(14).mean()

    rs = gain / loss

    df["RSI"] = (
        100 - 100 / (1 + rs)
    )

    # Volatility
    df["Volatility"] = (
        df["Return"].rolling(5).std()
    )

    # Bollinger
    rolling_mean = (
        df["Close"].rolling(20).mean()
    )

    rolling_std = (
        df["Close"].rolling(20).std()
    )

    upper_band = (
        rolling_mean + 2 * rolling_std
    )

    lower_band = (
        rolling_mean - 2 * rolling_std
    )

    df["Bollinger_Position"] = (
        (df["Close"] - lower_band)
        / (upper_band - lower_band)
    )

    # Volume
    df["Volume_Change"] = (
        df["Volume"].pct_change()
    )

    df["Volume_MA5"] = (
        df["Volume"].rolling(5).mean()
    )

    df["Volume_Ratio"] = (
        df["Volume"] / df["Volume_MA5"]
    )

    # Enhanced momentum
    df["ROC_20"] = (
        df["Close"].pct_change(20)
    )

    # EMAs
    df["EMA5"] = df["Close"].ewm(
        span=5,
        adjust=False,
    ).mean()

    df["EMA20"] = df["Close"].ewm(
        span=20,
        adjust=False,
    ).mean()

    df["EMA50"] = df["Close"].ewm(
        span=50,
        adjust=False,
    ).mean()

    df["Price_EMA20_Ratio"] = (
        df["Close"] / df["EMA20"] - 1
    )

    df["Price_EMA50_Ratio"] = (
        df["Close"] / df["EMA50"] - 1
    )

    df["EMA5_EMA20_Ratio"] = (
        df["EMA5"] / df["EMA20"] - 1
    )

    df["EMA20_EMA50_Ratio"] = (
        df["EMA20"] / df["EMA50"] - 1
    )

    # ATR
    prev_close = df["Close"].shift(1)

    true_range = pd.concat(
        [
            df["High"] - df["Low"],
            (df["High"] - prev_close).abs(),
            (df["Low"] - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)

    df["ATR14"] = true_range.ewm(
        alpha=1 / 14,
        adjust=False,
    ).mean()

    df["ATR14_Ratio"] = (
        df["ATR14"] / df["Close"]
    )

    # Volatility windows
    df["Volatility_10"] = (
        df["Return"].rolling(10).std()
    )

    df["Volatility_20"] = (
        df["Return"].rolling(20).std()
    )

    # Stochastic
    rolling_high_14 = (
        df["High"].rolling(14).max()
    )

    rolling_low_14 = (
        df["Low"].rolling(14).min()
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
        df["Stochastic_K_14"]
        .rolling(3)
        .mean()
    )

    # Williams %R
    df["Williams_R_14"] = (
        -100
        * (rolling_high_14 - df["Close"])
        / stochastic_range
    )

    # ADX
    high_diff = df["High"].diff()
    low_diff = -df["Low"].diff()

    plus_dm = pd.Series(
        np.where(
            (high_diff > low_diff)
            & (high_diff > 0),
            high_diff,
            0.0,
        ),
        index=df.index,
    )

    minus_dm = pd.Series(
        np.where(
            (low_diff > high_diff)
            & (low_diff > 0),
            low_diff,
            0.0,
        ),
        index=df.index,
    )

    plus_dm_smooth = plus_dm.ewm(
        alpha=1 / 14,
        adjust=False,
    ).mean()

    minus_dm_smooth = minus_dm.ewm(
        alpha=1 / 14,
        adjust=False,
    ).mean()

    plus_di = (
        100
        * plus_dm_smooth
        / df["ATR14"]
    )

    minus_di = (
        100
        * minus_dm_smooth
        / df["ATR14"]
    )

    di_sum = plus_di + minus_di

    dx = (
        100
        * (plus_di - minus_di).abs()
        / di_sum.replace(0, np.nan)
    )

    df["ADX14"] = dx.ewm(
        alpha=1 / 14,
        adjust=False,
    ).mean()

    # Bollinger width
    df["Bollinger_Width"] = (
        (upper_band - lower_band)
        / rolling_mean
    )

    # Price structure
    df["High_Low_Range"] = (
        (df["High"] - df["Low"])
        / df["Close"]
    )

    df["Candle_Body"] = (
        (df["Close"] - df["Open"])
        / df["Open"]
    )

    df["Gap_Return"] = (
        df["Open"] / prev_close - 1
    )

    # Longer-term volume
    df["Volume_MA20"] = (
        df["Volume"].rolling(20).mean()
    )

    df["Volume_Ratio_20"] = (
        df["Volume"] / df["Volume_MA20"]
    )

    df["Volume_ROC_10"] = (
        df["Volume"].pct_change(10)
    )

    # Lags
    df["Return_Lag1"] = (
        df["Return"].shift(1)
    )

    df["Return_Lag5"] = (
        df["Return"].shift(5)
    )

    df["RSI_Lag1"] = (
        df["RSI"].shift(1)
    )

    df["MACD_Hist_Lag1"] = (
        df["MACD_Hist"].shift(1)
    )

    # --------------------------------------------------------
    # LIVE ticker-specific sentiment
    # --------------------------------------------------------
    # The 34th feature is supplied by FinBERT from the
    # current ticker's latest news headlines.
    df["sentiment_score"] = float(
        sentiment_score
    )

    df.replace(
        [np.inf, -np.inf],
        np.nan,
        inplace=True,
    )

    valid = df.dropna(
        subset=FEATURES
    )

    if valid.empty:
        raise ValueError(
            "Unable to construct a complete feature row."
        )

    latest = valid.iloc[-1]

    X = (
        latest[FEATURES]
        .astype(float)
        .to_numpy()
        .reshape(1, -1)
    )

    return latest, X


# ============================================================
# PREDICTION
# ============================================================

def predict(
    ticker,
    models,
    config,
):
    print(
        f"\nFetching live market data for {ticker}..."
    )

    data = fetch_market_data(ticker)

    # --------------------------------------------------------
    # LIVE TICKER-SPECIFIC SENTIMENT
    # --------------------------------------------------------

    sentiment = score_live_sentiment(
        ticker
    )

    print_live_sentiment(
        sentiment
    )

    # --------------------------------------------------------
    # BUILD EXACT 34-FEATURE VECTOR
    # --------------------------------------------------------

    latest, X = build_features(
        data,
        sentiment["score"],
    )

    if X.shape[1] != 34:
        raise ValueError(
            f"Expected 34 features but built "
            f"{X.shape[1]}."
        )

    # --------------------------------------------------------
    # INDIVIDUAL MODEL PROBABILITIES
    # --------------------------------------------------------

    raw = {
        "Random Forest": float(
            models["Random Forest"]
            .predict_proba(X)[0, 1]
        ),
        "CatBoost": float(
            models["CatBoost"]
            .predict_proba(X)[0, 1]
        ),
        "LightGBM": float(
            models["LightGBM"]
            .predict(X)[0]
        ),
        "XGBoost": float(
            models["XGBoost"]
            .predict_proba(X)[0, 1]
        ),
    }

    # --------------------------------------------------------
    # FROZEN ENSEMBLE
    # --------------------------------------------------------

    weights = {
        name: float(weight)
        for name, weight in
        config["ensemble_weights"].items()
    }

    ensemble_buy = sum(
        weights[name] * raw[name]
        for name in weights
    )

    ensemble_sell = (
        1.0 - ensemble_buy
    )

    spread = abs(
        ensemble_buy
        - ensemble_sell
    )

    threshold = 0.10  # Fixed HOLD threshold: 10%

    boundary = float(
        config["probability_boundary"]
    )

    if spread < threshold:
        signal = "HOLD"
    elif ensemble_buy >= boundary:
        signal = "BUY"
    else:
        signal = "SELL"

    return {
        "ticker": ticker,
        "date": latest["Date"],
        "close": float(latest["Close"]),
        "sentiment": sentiment,
        "raw": raw,
        "ensemble_buy": ensemble_buy,
        "ensemble_sell": ensemble_sell,
        "spread": spread,
        "threshold": threshold,
        "signal": signal,
    }


# ============================================================
# DISPLAY
# ============================================================

def print_result(result):
    print("\n" + "=" * 72)
    print(
        f"  QUANTEDGE RESULT | {result['ticker']}"
    )
    print("=" * 72)

    print(
        f"  Market date : "
        f"{result['date'].date()}"
    )

    print(
        f"  Close       : "
        f"{result['close']:.2f}"
    )

    sentiment = result["sentiment"]

    print(
        f"  Live sentiment: "
        f"{sentiment['score']:+.4f}"
    )

    print("\n  MODEL PROBABILITIES")
    print("  " + "-" * 58)

    for name in [
        "Random Forest",
        "CatBoost",
        "LightGBM",
        "XGBoost",
    ]:
        print(
            f"  {name:<15} "
            f"BUY probability: {result['raw'][name]:>7.2%}"
        )

    print("\n  ENSEMBLE")
    print("  " + "-" * 58)

    print(
        f"  BUY probability  : "
        f"{result['ensemble_buy']:.2%}"
    )

    print(
        f"  SELL probability : "
        f"{result['ensemble_sell']:.2%}"
    )

    print(
        f"  Spread           : "
        f"{result['spread']:.2%}"
    )

    print(
        f"  HOLD threshold   : "
        f"{result['threshold']:.2%}"
    )


    print("\n" + "  " + "-" * 58)

    print(
        f"  FINAL SIGNAL     : "
        f"{result['signal']}"
    )

    print("  " + "-" * 58)


# ============================================================
# MAIN
# ============================================================

def main():
    print("\\n" + "=" * 72)
    print("                 QUANTEDGE")
    print("       ML STOCK DECISION ENGINE + LIVE SENTIMENT")
    print("=" * 72)

    try:
        models, config = load_artifacts()
    except Exception as exc:
        print("\\nCould not load QuantEdge artifacts.")
        print(exc)
        sys.exit(1)

    print("\\nEnter a ticker symbol to get a prediction.")
    print("Type 'exit' to quit.")

    while True:
        ticker = input("\\nEnter ticker: ").strip().upper()

        if ticker in {"EXIT", "QUIT", "Q"}:
            print("\\nExiting QuantEdge. Goodbye.")
            break

        if not ticker:
            print("Please enter a valid ticker symbol.")
            continue

        try:
            result = predict(
                ticker,
                models,
                config,
            )
            print_result(result)
        except Exception:
            import traceback
            print(f"\\nError analyzing {ticker}:")
            traceback.print_exc()


if __name__ == "__main__":
    main()
