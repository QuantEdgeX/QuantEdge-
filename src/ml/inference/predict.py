import os
import json
import joblib
import numpy as np
import pandas as pd
import yfinance as yf

from lightgbm import Booster
from catboost import CatBoostClassifier

from src.sentimentanalysis.live_finbert import get_live_sentiment


# ============================================================
# PATHS
# ============================================================

LIGHTGBM_PATH = (
    "src/ml/saved_models/lightgbm/"
    "lightgbm_model.txt"
)

CATBOOST_PATH = (
    "src/ml/saved_models/catboost/"
    "catboost_model.cbm"
)

RANDOM_FOREST_PATH = (
    "src/ml/saved_models/random_forest/"
    "random_forest_model.pkl"
)

DECISION_CONFIG_PATH = (
    "src/ml/decision/"
    "decision_config.json"
)

HISTORICAL_SENTIMENT_PATH = (
    "src/data/historical_sentiment.csv"
)


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
# QUANTEDGE LIVE PREDICTOR
# ============================================================

class QuantEdgePredictor:

    def __init__(self):

        print("=" * 60)
        print("INITIALIZING QUANTEDGE LIVE PREDICTOR")
        print("=" * 60)

        self.load_models()
        self.load_decision_config()

        print("\nPredictor ready.")

    # ========================================================
    # LOAD MODELS
    # ========================================================

    def load_models(self):

        print("\nLoading LightGBM...")

        self.lightgbm_model = Booster(
            model_file=LIGHTGBM_PATH
        )

        print("Loading CatBoost...")

        self.catboost_model = CatBoostClassifier()
        self.catboost_model.load_model(
            CATBOOST_PATH
        )

        print("Loading Random Forest...")

        self.random_forest_model = joblib.load(
            RANDOM_FOREST_PATH
        )

        print("All models loaded successfully.")

    # ========================================================
    # LOAD DECISION CONFIG
    # ========================================================

    def load_decision_config(self):

        print("\nLoading decision configuration...")

        with open(
            DECISION_CONFIG_PATH,
            "r",
            encoding="utf-8",
        ) as f:

            config = json.load(f)

        decision_config = config

        self.spread_threshold = float(
            decision_config["spread_threshold"]
        )

        self.probability_boundary = float(
            decision_config.get(
                "probability_boundary",
                0.50,
            )
        )

        print(
            f"Spread threshold: "
            f"{self.spread_threshold:.2f}"
        )

        print(
            f"Probability boundary: "
            f"{self.probability_boundary:.2f}"
        )

    # ========================================================
    # FETCH LIVE MARKET DATA
    # ========================================================

    
    def fetch_market_data(self, ticker):

        ticker = ticker.upper().strip()

        print("\n" + "=" * 60)
        print("FETCHING LIVE MARKET DATA")
        print("=" * 60)

        print(f"Ticker: {ticker}")

        try:
            df = yf.download(
                ticker,
                period="6mo",
                interval="1d",
                auto_adjust=True,
                actions=False,
                progress=False,
                threads=False,
                multi_level_index=False,
            )

            if df is None or df.empty:
                raise ValueError(
                    f"No market data found for {ticker}"
                )

            # Handle MultiIndex columns.
            if isinstance(df.columns, pd.MultiIndex):
                df.columns = df.columns.get_level_values(0)

            df = df.reset_index()

            if "Datetime" in df.columns:
                df.rename(
                    columns={"Datetime": "Date"},
                    inplace=True,
                )

            required_columns = [
                "Date", "Open", "High",
                "Low", "Close", "Volume"
            ]

            missing = [
                col for col in required_columns
                if col not in df.columns
            ]

            if missing:
                raise ValueError(
                    f"Missing columns: {missing}"
                )

            df = df[required_columns].copy()

            df = df.sort_values(
                "Date"
            ).reset_index(drop=True)

            # Remove timezone.
            if isinstance(df["Date"].dtype, pd.DatetimeTZDtype):
                df["Date"] = df["Date"].dt.tz_localize(None)

            print(f"Rows downloaded: {len(df)}")
            print(f"Latest market date: {df['Date'].iloc[-1]}")
            print(f"Latest Close: {df['Close'].iloc[-1]:.2f}")

            return df

        except Exception as e:
            print(
                f"\nMarket data error: "
                f"{type(e).__name__}: {e}"
            )
            raise


    # ========================================================
    # CALCULATE TECHNICAL FEATURES
    # ========================================================

    def calculate_features(
        self,
        df,
    ):

        print("\n" + "=" * 60)
        print("CALCULATING LIVE FEATURES")
        print("=" * 60)

        df = df.copy()

        close = df["Close"]
        volume = df["Volume"]

        # ----------------------------------------------------
        # RETURNS
        # ----------------------------------------------------

        df["Return"] = (
            close.pct_change()
        )

        df["Return_3D"] = (
            close.pct_change(3)
        )

        df["Return_5D"] = (
            close.pct_change(5)
        )

        df["Return_10D"] = (
            close.pct_change(10)
        )

        # ----------------------------------------------------
        # MOVING AVERAGES
        # ----------------------------------------------------

        df["MA5"] = (
            close.rolling(5).mean()
        )

        df["MA10"] = (
            close.rolling(10).mean()
        )

        df["Price_MA5_Ratio"] = (
            close / df["MA5"]
        ) - 1

        df["Price_MA10_Ratio"] = (
            close / df["MA10"]
        ) - 1

        # ----------------------------------------------------
        # EMA
        # ----------------------------------------------------

        df["EMA12"] = (
            close.ewm(
                span=12,
                adjust=False,
            ).mean()
        )

        df["EMA26"] = (
            close.ewm(
                span=26,
                adjust=False,
            ).mean()
        )

        # ----------------------------------------------------
        # MACD
        # ----------------------------------------------------

        df["MACD"] = (
            df["EMA12"]
            - df["EMA26"]
        )

        df["MACD_Signal"] = (
            df["MACD"]
            .ewm(
                span=9,
                adjust=False,
            )
            .mean()
        )

        df["MACD_Hist"] = (
            df["MACD"]
            - df["MACD_Signal"]
        )

        # ----------------------------------------------------
        # RSI
        # ----------------------------------------------------

        delta = close.diff()

        gain = delta.clip(
            lower=0
        )

        loss = -delta.clip(
            upper=0
        )

        avg_gain = (
            gain.ewm(
                alpha=1 / 14,
                adjust=False,
            )
            .mean()
        )

        avg_loss = (
            loss.ewm(
                alpha=1 / 14,
                adjust=False,
            )
            .mean()
        )

        rs = (
            avg_gain
            / avg_loss.replace(
                0,
                np.nan,
            )
        )

        df["RSI"] = (
            100
            - (
                100
                / (1 + rs)
            )
        )

        # ----------------------------------------------------
        # VOLATILITY
        # ----------------------------------------------------

        df["Volatility"] = (
            df["Return"]
            .rolling(5)
            .std()
        )

        # ----------------------------------------------------
        # BOLLINGER POSITION
        # ----------------------------------------------------

        rolling_mean = (
            close
            .rolling(20)
            .mean()
        )

        rolling_std = (
            close
            .rolling(20)
            .std()
        )

        upper_band = (
            rolling_mean
            + 2 * rolling_std
        )

        lower_band = (
            rolling_mean
            - 2 * rolling_std
        )

        band_width = (
            upper_band
            - lower_band
        )

        df["Bollinger_Position"] = (
            (close - lower_band)
            / band_width.replace(
                0,
                np.nan,
            )
        )

        # ----------------------------------------------------
        # VOLUME
        # ----------------------------------------------------

        df["Volume_Change"] = (
            volume.pct_change()
        )

        df["Volume_MA5"] = (
            volume
            .rolling(5)
            .mean()
        )

        df["Volume_Ratio"] = (
            volume
            / df["Volume_MA5"]
        )

        return df

        # ========================================================
    # GET SENTIMENT SCORE
    # ========================================================

    def get_sentiment_score(
        self,
        sentiment_score=None,
    ):

        # ----------------------------------------------------
        # SUPPLIED SENTIMENT
        # ----------------------------------------------------

        if sentiment_score is not None:

            print(
                "\nUsing live FinBERT sentiment:"
                f" {sentiment_score:.6f}"
            )

            return float(sentiment_score)

        # ----------------------------------------------------
        # NO SENTIMENT PROVIDED
        # ----------------------------------------------------

        raise ValueError(
            "No sentiment_score was provided."
        )
    # ========================================================
    # PREPARE MODEL INPUT
    # ========================================================

    def prepare_model_input(
        self,
        df,
        sentiment_score,
    ):

        latest = df.iloc[-1].copy()

        latest["sentiment_score"] = (
            sentiment_score
        )

        # ----------------------------------------------------
        # Make sure every required feature exists
        # ----------------------------------------------------

        missing = [
            feature
            for feature in FEATURES
            if feature not in latest.index
        ]

        if missing:

            raise ValueError(
                "Missing features: "
                + ", ".join(missing)
            )

        X = pd.DataFrame(
            [
                [
                    latest[feature]
                    for feature in FEATURES
                ]
            ],
            columns=FEATURES,
        )

        # ----------------------------------------------------
        # Validate numerical values
        # ----------------------------------------------------

        X = X.astype(float)

        if X.isna().any().any():

            missing_values = (
                X.columns[
                    X.isna().iloc[0]
                ].tolist()
            )

            raise ValueError(
                "NaN values found in features: "
                + ", ".join(missing_values)
            )

        if np.isinf(
            X.to_numpy()
        ).any():

            raise ValueError(
                "Infinite values found in "
                "model features."
            )

        return X, latest

    # ========================================================
    # RUN MODELS
    # ========================================================

    def predict_models(
        self,
        X,
    ):

        # ----------------------------------------------------
        # LightGBM
        # ----------------------------------------------------

        lightgbm_buy = float(
            self.lightgbm_model.predict(X)[0]
        )

        # ----------------------------------------------------
        # CatBoost
        # ----------------------------------------------------

        catboost_buy = float(
            self.catboost_model
            .predict_proba(X)[0, 1]
        )

        # ----------------------------------------------------
        # Random Forest
        # ----------------------------------------------------

        random_forest_buy = float(
            self.random_forest_model
            .predict_proba(
                X.to_numpy()
            )[0, 1]
        )

        # ----------------------------------------------------
        # Ensemble
        # ----------------------------------------------------

        ensemble_buy = (
            lightgbm_buy
            + catboost_buy
            + random_forest_buy
        ) / 3.0

        ensemble_sell = (
            1.0 - ensemble_buy
        )

        spread = abs(
            ensemble_buy
            - ensemble_sell
        )

        # ----------------------------------------------------
        # Decision
        # ----------------------------------------------------

        if spread < self.spread_threshold:

            signal = "HOLD"

        elif (
            ensemble_buy
            >= self.probability_boundary
        ):

            signal = "BUY"

        else:

            signal = "SELL"

        return {
            "lightgbm_buy": lightgbm_buy,
            "lightgbm_sell": (
                1.0 - lightgbm_buy
            ),

            "catboost_buy": catboost_buy,
            "catboost_sell": (
                1.0 - catboost_buy
            ),

            "random_forest_buy": (
                random_forest_buy
            ),
            "random_forest_sell": (
                1.0 - random_forest_buy
            ),

            "ensemble_buy": ensemble_buy,
            "ensemble_sell": ensemble_sell,

            "spread": spread,

            "signal": signal,
        }

    # ========================================================
    # COMPLETE LIVE PREDICTION
    # ========================================================

    def predict(
        self,
        ticker,
        sentiment_score=None,
    ):

        ticker = ticker.upper().strip()

        # ----------------------------------------------------
        # Fetch current market data
        # ----------------------------------------------------

        market_df = (
            self.fetch_market_data(
                ticker
            )
        )

        # ----------------------------------------------------
        # Calculate technical indicators
        # ----------------------------------------------------

        feature_df = (
            self.calculate_features(
                market_df
            )
        )

        # ----------------------------------------------------
        # Get sentiment
        # ----------------------------------------------------

        sentiment = (
            self.get_sentiment_score(
                sentiment_score
            )
        )

        # ----------------------------------------------------
        # Prepare model input
        # ----------------------------------------------------

        X, latest = (
            self.prepare_model_input(
                feature_df,
                sentiment,
            )
        )

        # ----------------------------------------------------
        # Model prediction
        # ----------------------------------------------------

        prediction = (
            self.predict_models(X)
        )

        # ----------------------------------------------------
        # Add market information
        # ----------------------------------------------------

        result = {

            "ticker": ticker,

            "date": str(
                latest["Date"]
            ),

            "close": float(
                latest["Close"]
            ),

            "sentiment_score": sentiment,

            **prediction,
        }

        return result


# ============================================================
# DISPLAY RESULT
# ============================================================

def display_result(
    result,
):

    print("\n")
    print("=" * 60)
    print("QUANTEDGE LIVE PREDICTION")
    print("=" * 60)

    print(
        f"Ticker:             "
        f"{result['ticker']}"
    )

    print(
        f"Latest market date: "
        f"{result['date']}"
    )

    print(
        f"Latest close:       "
        f"{result['close']:.2f}"
    )

    print(
        f"Sentiment score:    "
        f"{result['sentiment_score']:.6f}"
    )

    print("\n" + "-" * 60)
    print("INDIVIDUAL MODELS")
    print("-" * 60)

    print(
        f"LightGBM BUY:       "
        f"{result['lightgbm_buy']:.2%}"
    )

    print(
        f"LightGBM SELL:      "
        f"{result['lightgbm_sell']:.2%}"
    )

    print()

    print(
        f"CatBoost BUY:       "
        f"{result['catboost_buy']:.2%}"
    )

    print(
        f"CatBoost SELL:      "
        f"{result['catboost_sell']:.2%}"
    )

    print()

    print(
        f"Random Forest BUY:  "
        f"{result['random_forest_buy']:.2%}"
    )

    print(
        f"Random Forest SELL: "
        f"{result['random_forest_sell']:.2%}"
    )

    print("\n" + "-" * 60)
    print("ENSEMBLE")
    print("-" * 60)

    print(
        f"Ensemble BUY:       "
        f"{result['ensemble_buy']:.2%}"
    )

    print(
        f"Ensemble SELL:      "
        f"{result['ensemble_sell']:.2%}"
    )

    print(
        f"Spread:             "
        f"{result['spread']:.2%}"
    )

    print("\n" + "=" * 60)

    print(
        f"FINAL SIGNAL:       "
        f"{result['signal']}"
    )

    print("=" * 60)


#============================================================
# INTERACTIVE CLI
# ============================================================

def main():

    predictor = QuantEdgePredictor()

    print("\n")
    print("=" * 60)
    print("QUANTEDGE LIVE STOCK PREDICTION")
    print("=" * 60)

    print(
        "\nEnter a US stock ticker."
    )

    print(
        "Examples: AAPL, TSLA, NVDA, MSFT"
    )

    print(
        "Type EXIT to stop."
    )

    while True:

        print()

        ticker = input(
            "Enter ticker: "
        ).strip().upper()

        if ticker == "EXIT":

            print(
                "\nExiting QuantEdge."
            )

            break

        if not ticker:

            print(
                "Please enter a ticker."
            )

            continue

        try:

            # ------------------------------------------------
            # GET LIVE FINBERT SENTIMENT
            # ------------------------------------------------

            print("\n" + "=" * 60)
            print("FETCHING LIVE SENTIMENT")
            print("=" * 60)

            sentiment_score = get_live_sentiment(ticker)

            print(
                f"\nLive FinBERT sentiment: "
                f"{sentiment_score:.6f}"
            )

            # ------------------------------------------------
            # COMPLETE LIVE PREDICTION
            # ------------------------------------------------

            # Run prediction exactly once.
            result = predictor.predict(
                ticker,
                sentiment_score=sentiment_score
            )

            # ------------------------------------------------
            # DISPLAY RESULT
            # ------------------------------------------------

            display_result(
                result
            )

        except Exception as e:

            print("\n" + "=" * 60)
            print("PREDICTION ERROR")
            print("=" * 60)

            print(
                str(e)
            )

            print(
                "\nPlease check the ticker "
                "and try again."
            )


if __name__ == "__main__":
    main()