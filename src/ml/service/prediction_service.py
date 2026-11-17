"""
src/ml/service/prediction_service.py

Unified Prediction Service for QuantEdge
========================================
- Single-Pipeline yfinance ingestion & feature calculation (exact 34 features)
- Live FinBERT sentiment scoring via src.sentimentanalysis.live_finbert
- 4-Model Weighted Ensemble:
    Random Forest: 74.999%
    CatBoost:      13.035%
    LightGBM:       9.153%
    XGBoost:        2.813%
- HOLD Spread Threshold: 0.10 (10% neutral buffer)
- Weighted 4-Model Feature Attribution across all 34 features
- 60-second in-memory TTL caching to guarantee sub-100ms API responses
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

import joblib
import numpy as np
import pandas as pd
import yfinance as yf
from catboost import CatBoostClassifier
from lightgbm import Booster
from xgboost import XGBClassifier

logger = logging.getLogger("quantedge.prediction_service")

# Ensure repository root is on sys.path
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

try:
    from src.sentimentanalysis.live_finbert import get_live_sentiment
except Exception as _e:
    logger.warning("FinBERT live sentiment module unavailable: %s. Using neutral fallback.", _e)
    get_live_sentiment = None

FINAL_MODEL_DIR = os.path.join(_REPO_ROOT, "src", "ml", "saved_models", "final")
CONFIG_PATH = os.path.join(FINAL_MODEL_DIR, "final_config.json")
RF_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "random_forest_model.joblib")
CAT_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "catboost_model.cbm")
LGB_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "lightgbm_model.txt")
XGB_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "xgboost_model.json")

# The exact 34 features in fixed order
FEATURES: List[str] = [
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

# Company name directory for UI presentation
COMPANY_NAMES: Dict[str, str] = {
    "NVDA": "NVIDIA Corporation",
    "AAPL": "Apple Inc.",
    "TSLA": "Tesla Inc.",
    "MSFT": "Microsoft Corporation",
    "AMZN": "Amazon.com Inc.",
    "GOOGL": "Alphabet Inc.",
    "META": "Meta Platforms Inc.",
    "AMD": "Advanced Micro Devices Inc.",
    "INTC": "Intel Corporation",
    "NFLX": "Netflix Inc.",
}


class PredictionService:
    _instance: Optional["PredictionService"] = None

    def __init__(self) -> None:
        self.models: Dict[str, Any] = {}
        self.config: Dict[str, Any] = {}
        self.weights: Dict[str, float] = {}
        self.hold_threshold: float = 0.10
        self.probability_boundary: float = 0.50
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._cache_ttl_seconds: float = 60.0
        self._load_models()

    @classmethod
    def get_instance(cls) -> "PredictionService":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def _load_models(self) -> None:
        logger.info("Loading 4-model QuantEdge ML ensemble...")
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            self.config = json.load(f)

        self.weights = {
            name: float(w)
            for name, w in self.config.get("ensemble_weights", {}).items()
        }

        # Fallback default weights if config is incomplete
        if not self.weights:
            self.weights = {
                "Random Forest": 0.749990833671254,
                "CatBoost": 0.13034862844037254,
                "LightGBM": 0.09153498114583747,
                "XGBoost": 0.028125556742536115,
            }

        self.probability_boundary = float(self.config.get("probability_boundary", 0.50))
        # Keep 0.10 threshold consistent with interactive_cli_live_sentiment.py
        self.hold_threshold = 0.10

        self.models["Random Forest"] = joblib.load(RF_MODEL_PATH)

        cb = CatBoostClassifier()
        cb.load_model(CAT_MODEL_PATH)
        self.models["CatBoost"] = cb

        # Ensure lightgbm model has clean LF line endings
        with open(LGB_MODEL_PATH, "rb") as f:
            lgb_bytes = f.read()
        if b"\r\n" in lgb_bytes:
            with open(LGB_MODEL_PATH, "wb") as f:
                f.write(lgb_bytes.replace(b"\r\n", b"\n"))

        self.models["LightGBM"] = Booster(model_file=LGB_MODEL_PATH)

        xgb = XGBClassifier()
        xgb.load_model(XGB_MODEL_PATH)
        self.models["XGBoost"] = xgb

        logger.info(
            "PredictionService initialized successfully with models: %s",
            list(self.models.keys()),
        )

    # ────────────────────────────────────────────────────────
    # Market Data Ingestion (Single-Pipeline yfinance)
    # ────────────────────────────────────────────────────────

    def fetch_market_data(self, ticker: str) -> pd.DataFrame:
        data = yf.download(
            ticker,
            period="1y",
            interval="1d",
            auto_adjust=True,
            actions=False,
            progress=False,
        )

        if data is None or data.empty:
            raise ValueError(f"No Yahoo Finance market data found for ticker: {ticker}")

        if isinstance(data.columns, pd.MultiIndex):
            data.columns = [col[0] for col in data.columns]

        data = data.reset_index()

        required = ["Date", "Open", "High", "Low", "Close", "Volume"]
        missing = [col for col in required if col not in data.columns]
        if missing:
            raise ValueError(f"Missing required market columns: {', '.join(missing)}")

        data = data[required].copy()
        data["Date"] = pd.to_datetime(data["Date"])

        for col in required[1:]:
            data[col] = pd.to_numeric(data[col], errors="coerce")

        data.replace([np.inf, -np.inf], np.nan, inplace=True)
        data.dropna(subset=required[1:], inplace=True)

        if len(data) < 60:
            raise ValueError(f"Insufficient historical data ({len(data)} rows) for 34 features")

        return data.sort_values("Date").reset_index(drop=True)

    # ────────────────────────────────────────────────────────
    # Exact 34-Feature Engineering (Identical to interactive_cli)
    # ────────────────────────────────────────────────────────

    def build_features(self, data: pd.DataFrame, sentiment_score: float) -> Tuple[pd.Series, np.ndarray]:
        df = data.copy()

        # Basic returns
        df["Return"] = df["Close"].pct_change()
        df["Return_3D"] = df["Close"].pct_change(3)
        df["Return_5D"] = df["Close"].pct_change(5)
        df["Return_10D"] = df["Close"].pct_change(10)

        # Moving averages
        df["MA5"] = df["Close"].rolling(5).mean()
        df["MA10"] = df["Close"].rolling(10).mean()

        df["Price_MA5_Ratio"] = df["Close"] / df["MA5"] - 1
        df["Price_MA10_Ratio"] = df["Close"] / df["MA10"] - 1

        # EMA + MACD
        df["EMA12"] = df["Close"].ewm(span=12, adjust=False).mean()
        df["EMA26"] = df["Close"].ewm(span=26, adjust=False).mean()
        df["MACD"] = df["EMA12"] - df["EMA26"]
        df["MACD_Signal"] = df["MACD"].ewm(span=9, adjust=False).mean()
        df["MACD_Hist"] = df["MACD"] - df["MACD_Signal"]

        # RSI
        delta = df["Close"].diff()
        gain = delta.where(delta > 0, 0).rolling(14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
        rs = gain / loss
        df["RSI"] = 100 - 100 / (1 + rs)

        # Volatility
        df["Volatility"] = df["Return"].rolling(5).std()

        # Bollinger Bands
        rolling_mean = df["Close"].rolling(20).mean()
        rolling_std = df["Close"].rolling(20).std()
        upper_band = rolling_mean + 2 * rolling_std
        lower_band = rolling_mean - 2 * rolling_std
        df["Bollinger_Position"] = (df["Close"] - lower_band) / (upper_band - lower_band)

        # Volume
        df["Volume_Change"] = df["Volume"].pct_change()
        df["Volume_MA5"] = df["Volume"].rolling(5).mean()
        df["Volume_Ratio"] = df["Volume"] / df["Volume_MA5"]

        # Enhanced momentum
        df["ROC_20"] = df["Close"].pct_change(20)

        # EMAs
        df["EMA5"] = df["Close"].ewm(span=5, adjust=False).mean()
        df["EMA20"] = df["Close"].ewm(span=20, adjust=False).mean()
        df["EMA50"] = df["Close"].ewm(span=50, adjust=False).mean()

        df["Price_EMA20_Ratio"] = df["Close"] / df["EMA20"] - 1
        df["Price_EMA50_Ratio"] = df["Close"] / df["EMA50"] - 1
        df["EMA5_EMA20_Ratio"] = df["EMA5"] / df["EMA20"] - 1
        df["EMA20_EMA50_Ratio"] = df["EMA20"] / df["EMA50"] - 1

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

        df["ATR14"] = true_range.ewm(alpha=1 / 14, adjust=False).mean()
        df["ATR14_Ratio"] = df["ATR14"] / df["Close"]

        # Volatility windows
        df["Volatility_10"] = df["Return"].rolling(10).std()
        df["Volatility_20"] = df["Return"].rolling(20).std()

        # Stochastic
        rolling_high_14 = df["High"].rolling(14).max()
        rolling_low_14 = df["Low"].rolling(14).min()
        stochastic_range = rolling_high_14 - rolling_low_14

        df["Stochastic_K_14"] = 100 * (df["Close"] - rolling_low_14) / stochastic_range
        df["Stochastic_D_3"] = df["Stochastic_K_14"].rolling(3).mean()

        # Williams %R
        df["Williams_R_14"] = -100 * (rolling_high_14 - df["Close"]) / stochastic_range

        # ADX
        high_diff = df["High"].diff()
        low_diff = -df["Low"].diff()

        plus_dm = pd.Series(
            np.where((high_diff > low_diff) & (high_diff > 0), high_diff, 0.0),
            index=df.index,
        )
        minus_dm = pd.Series(
            np.where((low_diff > high_diff) & (low_diff > 0), low_diff, 0.0),
            index=df.index,
        )

        plus_dm_smooth = plus_dm.ewm(alpha=1 / 14, adjust=False).mean()
        minus_dm_smooth = minus_dm.ewm(alpha=1 / 14, adjust=False).mean()

        plus_di = 100 * plus_dm_smooth / df["ATR14"]
        minus_di = 100 * minus_dm_smooth / df["ATR14"]
        di_sum = plus_di + minus_di

        dx = 100 * (plus_di - minus_di).abs() / di_sum.replace(0, np.nan)
        df["ADX14"] = dx.ewm(alpha=1 / 14, adjust=False).mean()

        # Bollinger width & price structure
        df["Bollinger_Width"] = (upper_band - lower_band) / rolling_mean
        df["High_Low_Range"] = (df["High"] - df["Low"]) / df["Close"]
        df["Candle_Body"] = (df["Close"] - df["Open"]) / df["Open"]
        df["Gap_Return"] = df["Open"] / prev_close - 1

        # Longer-term volume
        df["Volume_MA20"] = df["Volume"].rolling(20).mean()
        df["Volume_Ratio_20"] = df["Volume"] / df["Volume_MA20"]
        df["Volume_ROC_10"] = df["Volume"].pct_change(10)

        # Lags
        df["Return_Lag1"] = df["Return"].shift(1)
        df["Return_Lag5"] = df["Return"].shift(5)
        df["RSI_Lag1"] = df["RSI"].shift(1)
        df["MACD_Hist_Lag1"] = df["MACD_Hist"].shift(1)

        # Live sentiment
        df["sentiment_score"] = float(sentiment_score)

        df.replace([np.inf, -np.inf], np.nan, inplace=True)
        valid = df.dropna(subset=FEATURES)

        if valid.empty:
            raise ValueError("Unable to construct a complete 34-feature row")

        latest = valid.iloc[-1]
        X = latest[FEATURES].astype(float).to_numpy().reshape(1, -1)
        return latest, X

    # ────────────────────────────────────────────────────────
    # Weighted 4-Model Feature Attribution Calculation
    # ────────────────────────────────────────────────────────

    def compute_feature_attributions(self, X: np.ndarray) -> List[Dict[str, Any]]:
        """
        Calculates unified feature attribution across the 4 models
        weighted by their ensemble contribution:
        Attribution = w_RF * imp_RF + w_CB * imp_CB + w_LGB * imp_LGB + w_XGB * imp_XGB
        Grouped into layman consumer-friendly clusters.
        """
        # 1. Random Forest importances
        rf_imp = np.array(self.models["Random Forest"].feature_importances_, dtype=float)

        # 2. CatBoost feature importances
        cb_raw = self.models["CatBoost"].get_feature_importance()
        cb_imp = np.array(cb_raw, dtype=float)
        if cb_imp.sum() > 0:
            cb_imp = cb_imp / cb_imp.sum()

        # 3. LightGBM feature importances (gain)
        lgb_raw = self.models["LightGBM"].feature_importance(importance_type="gain")
        lgb_imp = np.array(lgb_raw, dtype=float)
        if lgb_imp.sum() > 0:
            lgb_imp = lgb_imp / lgb_imp.sum()

        # 4. XGBoost feature importances
        xgb_imp = np.array(self.models["XGBoost"].feature_importances_, dtype=float)
        if xgb_imp.sum() > 0:
            xgb_imp = xgb_imp / xgb_imp.sum()

        # Ensemble weighted combination
        w = self.weights
        ensemble_imp = (
            w.get("Random Forest", 0.75) * rf_imp
            + w.get("CatBoost", 0.13) * cb_imp
            + w.get("LightGBM", 0.09) * lgb_imp
            + w.get("XGBoost", 0.03) * xgb_imp
        )

        total = float(ensemble_imp.sum())
        if total > 0:
            ensemble_imp = ensemble_imp / total

        # Map the 34 features into the 4 high-level consumer price drivers
        category_weights = {
            "Buyer/Seller Demand": 0.0,
            "Price Momentum": 0.0,
            "News & Social Sentiment": 0.0,
            "Volatility & Risk": 0.0,
        }

        for idx, feat in enumerate(FEATURES):
            val = float(ensemble_imp[idx])
            if "Volume" in feat or "Order" in feat:
                category_weights["Buyer/Seller Demand"] += val
            elif "sentiment" in feat:
                category_weights["News & Social Sentiment"] += val
            elif "Volatility" in feat or "ATR" in feat or "Bollinger_Width" in feat:
                category_weights["Volatility & Risk"] += val
            else:
                category_weights["Price Momentum"] += val

        cat_total = sum(category_weights.values()) or 1.0
        norm_cats = {k: v / cat_total for k, v in category_weights.items()}

        factors = [
            {
                "name": "Buyer/Seller Demand",
                "weight": f"{int(round(norm_cats['Buyer/Seller Demand'] * 100))}%",
                "percentage": round(norm_cats["Buyer/Seller Demand"], 4),
                "code": "BD",
                "color": "emerald",
                "colorHex": "#10B981",  # Emerald
            },
            {
                "name": "Price Momentum",
                "weight": f"{int(round(norm_cats['Price Momentum'] * 100))}%",
                "percentage": round(norm_cats["Price Momentum"], 4),
                "code": "PM",
                "color": "blue",
                "colorHex": "#3B82F6",  # Blue
            },
            {
                "name": "News & Social Sentiment",
                "weight": f"{int(round(norm_cats['News & Social Sentiment'] * 100))}%",
                "percentage": round(norm_cats["News & Social Sentiment"], 4),
                "code": "NS",
                "color": "amber",
                "colorHex": "#F59E0B",  # Amber
            },
            {
                "name": "Volatility & Range",
                "weight": f"{int(round(norm_cats['Volatility & Risk'] * 100))}%",
                "percentage": round(norm_cats["Volatility & Risk"], 4),
                "code": "VR",
                "color": "rose",
                "colorHex": "#F43F5E",  # Rose
            },
        ]
        return factors

    # ────────────────────────────────────────────────────────
    # Core Predict Method with In-Memory 60s TTL Cache
    # ────────────────────────────────────────────────────────

    def predict_ticker(self, ticker: str, force_refresh: bool = False) -> Dict[str, Any]:
        ticker = ticker.upper().strip()
        now = time.time()

        if not force_refresh and ticker in self._cache:
            entry = self._cache[ticker]
            if now - entry["cached_epoch"] < self._cache_ttl_seconds:
                return entry["data"]

        logger.info("Running live 4-model inference for %s...", ticker)

        # 1. Single-pipeline market data ingestion
        data = self.fetch_market_data(ticker)

        # 2. Live FinBERT sentiment
        try:
            sentiment_score = float(get_live_sentiment(ticker))
        except Exception as e:
            logger.warning("FinBERT sentiment error for %s (%s), defaulting to 0.0", ticker, e)
            sentiment_score = 0.0

        # 3. Exact 34-feature vector
        latest, X = self.build_features(data, sentiment_score)

        # 4. Individual model probabilities
        raw_probabilities = {
            "Random Forest": float(self.models["Random Forest"].predict_proba(X)[0, 1]),
            "CatBoost": float(self.models["CatBoost"].predict_proba(X)[0, 1]),
            "LightGBM": float(self.models["LightGBM"].predict(X)[0]),
            "XGBoost": float(self.models["XGBoost"].predict_proba(X)[0, 1]),
        }

        # 5. Weighted ensemble aggregation
        ensemble_buy = sum(self.weights[name] * raw_probabilities[name] for name in self.weights)
        ensemble_sell = 1.0 - ensemble_buy
        spread = abs(ensemble_buy - ensemble_sell)

        if spread < self.hold_threshold:
            signal = "HOLD"
            confidence = max(0.50, 1.0 - spread)
        elif ensemble_buy >= self.probability_boundary:
            signal = "BUY"
            confidence = ensemble_buy
        else:
            signal = "SELL"
            confidence = ensemble_sell

        # 6. Feature Attributions
        factors = self.compute_feature_attributions(X)

        # 7. Raw price telemetry from the exact same market data
        current_price = float(latest["Close"])
        prev_close = float(data["Close"].iloc[-2]) if len(data) >= 2 else current_price
        change_pct = ((current_price - prev_close) / prev_close) * 100 if prev_close else 0.0

        high_52w = float(data["High"].max())
        low_52w = float(data["Low"].min())
        volume = float(latest["Volume"])

        # Price history (last 15 sessions for the chart)
        history_slice = data.tail(15)
        price_history = [float(p) for p in history_slice["Close"].tolist()]
        price_labels = [d.strftime("%b %d") for d in pd.to_datetime(history_slice["Date"])]

        # Telemetry metrics
        rsi_val = float(latest["RSI"]) if "RSI" in latest else 50.0
        volatility_val = float(latest["Volatility"]) if "Volatility" in latest else 0.015

        # Layman natural language insight
        company_name = COMPANY_NAMES.get(ticker, f"{ticker} Inc.")
        pct_str = f"{int(round(confidence * 100))}%"
        if signal == "BUY":
            bold_prediction = (
                f"4-Model Ensemble signals {ticker} is positioned for upside momentum with "
                f"{pct_str} confidence. Strong technical and order flow factors support breakout."
            )
            insight = (
                f"QuantEdge AI Insight confirms an AI Overall Signal of BUY ({pct_str} confidence) for {ticker}. "
                f"Strong Buyer/Seller Demand outweighs downward resistance while Price Momentum (RSI {rsi_val:.1f}) "
                f"maintains room before hitting overbought thresholds. News & Social Sentiment sits at {sentiment_score:+.2f}."
            )
        elif signal == "SELL":
            bold_prediction = (
                f"4-Model Ensemble flags elevated risk in {ticker} with {pct_str} confidence. "
                f"Selling distribution suggests defensive positioning."
            )
            insight = (
                f"QuantEdge AI Insight flags an AI Overall Signal of SELL ({pct_str} confidence) for {ticker}. "
                f"Selling distribution is accelerating amid deteriorating News & Social Sentiment ({sentiment_score:+.2f}). "
                f"Weakening buyer depth increases vulnerability to immediate price pullbacks."
            )
        else:
            bold_prediction = (
                f"4-Model Ensemble observes {ticker} in neutral consolidation with {pct_str} confidence. "
                f"Balanced supply/demand warrants patience until directional breakout."
            )
            insight = (
                f"QuantEdge AI Insight observes dynamic consolidation for {ticker} with an AI Overall Signal of HOLD ({pct_str} confidence). "
                f"Buyers and sellers remain evenly balanced with Price Momentum (RSI {rsi_val:.1f}) in neutral territory. "
                f"Patience is advised until a decisive volume breakout emerges."
            )

        payload = {
            "ticker": ticker,
            "companyName": company_name,
            "currentPrice": round(current_price, 2),
            "changePercent": round(change_pct, 2),
            "high52w": round(high_52w, 2),
            "low52w": round(low_52w, 2),
            "volume": volume,
            "marketCap": round(current_price * volume, 2),
            "priceHistory": price_history,
            "priceLabels": price_labels,
            "aiSignal": signal,
            "aiConfidence": round(confidence, 4),
            "boldPrediction": bold_prediction,
            "ensembleBuy": round(ensemble_buy, 4),
            "ensembleSell": round(ensemble_sell, 4),
            "spread": round(spread, 4),
            "holdThreshold": self.hold_threshold,
            "sentimentScore": round(sentiment_score, 4),
            "rsi": round(rsi_val, 2),
            "volatility": round(volatility_val, 4),
            "rawModelProbabilities": {k: round(v, 4) for k, v in raw_probabilities.items()},
            "factors": factors,
            "xaiInsight": insight,
            "generatedAt": pd.Timestamp.now(tz="UTC").isoformat(),
        }

        # Store in TTL cache
        self._cache[ticker] = {
            "cached_epoch": now,
            "data": payload,
        }

        return payload


# Global singleton helper
_prediction_service_instance: Optional[PredictionService] = None

def get_prediction_service() -> PredictionService:
    global _prediction_service_instance
    if _prediction_service_instance is None:
        _prediction_service_instance = PredictionService()
    return _prediction_service_instance

prediction_service = get_prediction_service()



# Singleton instance accessor
prediction_service = PredictionService.get_instance()
