# src/ml/models/final_evaluation.py

import os
import json
import time
import warnings
import joblib

import numpy as np
import pandas as pd

from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    log_loss,
    roc_auc_score,
    brier_score_loss,
)

from catboost import CatBoostClassifier
from lightgbm import LGBMClassifier
from xgboost import XGBClassifier
from scipy.optimize import minimize


warnings.filterwarnings("ignore")


# ============================================================
# PATHS
# ============================================================

DATA_PATH = (
    "src/data/processed_data_enhanced.csv"
)

WEIGHTS_PATH = (
    "src/ml/models/"
    "final_ensemble_weights.json"
)

DECISION_CONFIG_PATH = (
    "src/ml/decision/"
    "decision_config.json"
)

BEST_PARAMS_PATH = (
    "src/ml/models/"
    "best_hyperparameters.json"
)

OUTPUT_DIR = (
    "src/ml/models/final_results"
)

os.makedirs(
    OUTPUT_DIR,
    exist_ok=True,
)

PREDICTIONS_PATH = os.path.join(
    OUTPUT_DIR,
    "final_test_predictions.csv",
)

METRICS_PATH = os.path.join(
    OUTPUT_DIR,
    "final_test_metrics.json",
)

MODEL_SUMMARY_PATH = os.path.join(
    OUTPUT_DIR,
    "final_model_summary.json",
)

# ============================================================
# FINAL SAVED MODEL DIRECTORY
# ============================================================

FINAL_MODEL_DIR = "src/ml/saved_models/final"

RF_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "random_forest_model.joblib")
CAT_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "catboost_model.cbm")
LGB_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "lightgbm_model.txt")
XGB_MODEL_PATH = os.path.join(FINAL_MODEL_DIR, "xgboost_model.json")


FINAL_CONFIG_PATH = os.path.join(FINAL_MODEL_DIR, "final_config.json")

os.makedirs(FINAL_MODEL_DIR, exist_ok=True)


# ============================================================
# CONFIGURATION
# ============================================================

TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
EMBARGO_DAYS = 5

HORIZON = 5

SELL_QUANTILE = 0.30
BUY_QUANTILE = 0.70


# ============================================================
# FINAL FEATURE SET
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

    # Sentiment feature
    "sentiment_score",
]


# ============================================================
# FROZEN ENSEMBLE
# ============================================================

DEFAULT_WEIGHTS = {
    "Random Forest": 0.50,
    "CatBoost": 0.10,
    "LightGBM": 0.10,
    "XGBoost": 0.30,
}


# ============================================================
# UTILITY
# ============================================================

def timer():
    return time.time()


def elapsed(start):
    return time.time() - start


# ============================================================
# LOAD JSON
# ============================================================

def load_json(path):

    if not os.path.exists(path):
        raise FileNotFoundError(
            f"File not found:\n{path}"
        )

    with open(
        path,
        "r",
        encoding="utf-8",
    ) as f:
        return json.load(f)


# ============================================================
# LOAD FROZEN CONFIGURATION
# ============================================================

def load_frozen_configuration():

    print("\n" + "=" * 80)
    print("LOADING FROZEN CONFIGURATION")
    print("=" * 80)

    # --------------------------------------------------------
    # Ensemble weights
    # --------------------------------------------------------

    if os.path.exists(
        WEIGHTS_PATH
    ):

        weights_json = load_json(
            WEIGHTS_PATH
        )

        weights = {}

        for model_name in DEFAULT_WEIGHTS:

            if model_name in weights_json:
                weights[model_name] = float(
                    weights_json[model_name]
                )
            else:
                weights[model_name] = (
                    DEFAULT_WEIGHTS[
                        model_name
                    ]
                )

    else:

        print(
            "Warning: frozen weight file "
            "not found. Using expected "
            "frozen weights."
        )

        weights = DEFAULT_WEIGHTS.copy()

    # --------------------------------------------------------
    # Decision threshold
    # --------------------------------------------------------

    if os.path.exists(
        DECISION_CONFIG_PATH
    ):

        decision_config = load_json(
            DECISION_CONFIG_PATH
        )

        decision_section = (
            decision_config.get(
                "decision_engine",
                {}
            )
        )

        spread_threshold = float(
            decision_section.get(
                "spread_threshold",
                0.02,
            )
        )

        probability_boundary = float(
            decision_section.get(
                "probability_boundary",
                0.50,
            )
        )

    else:

        print(
            "Warning: decision config "
            "not found. Using frozen "
            "threshold 0.02."
        )

        spread_threshold = 0.02
        probability_boundary = 0.50

    # --------------------------------------------------------
    # Normalize weights
    # --------------------------------------------------------

    weight_sum = sum(
        weights.values()
    )

    if weight_sum <= 0:
        raise ValueError(
            "Ensemble weights sum to zero."
        )

    weights = {
        name: value / weight_sum
        for name, value in weights.items()
    }

    print("\nFrozen ensemble weights:")

    for name, weight in weights.items():

        print(
            f"{name:<15}: "
            f"{weight:.2%}"
        )

    print(
        f"\nFrozen probability boundary: "
        f"{probability_boundary:.2f}"
    )

    print(
        f"Frozen spread threshold: "
        f"{spread_threshold:.2f}"
    )

    return (
        weights,
        probability_boundary,
        spread_threshold,
    )


# ============================================================
# LOAD DATA
# ============================================================

def load_data():

    print("\n" + "=" * 80)
    print("LOADING ENHANCED DATA")
    print("=" * 80)

    if not os.path.exists(
        DATA_PATH
    ):
        raise FileNotFoundError(
            f"Dataset not found:\n{DATA_PATH}"
        )

    df = pd.read_csv(
        DATA_PATH
    )

    df["Date"] = pd.to_datetime(
        df["Date"]
    )

    df = df.sort_values(
        ["Ticker", "Date"]
    ).reset_index(
        drop=True
    )

    print(
        f"Rows: {len(df):,}"
    )

    print(
        f"Tickers: "
        f"{df['Ticker'].nunique()}"
    )

    print(
        f"Date range: "
        f"{df['Date'].min().date()} "
        f"to "
        f"{df['Date'].max().date()}"
    )

    # --------------------------------------------------------
    # Verify features
    # --------------------------------------------------------

    missing_features = [
        feature
        for feature in FEATURES
        if feature not in df.columns
    ]

    if missing_features:

        raise ValueError(
            "Missing required features:\n"
            + "\n".join(
                missing_features
            )
        )

    if "Close" not in df.columns:
        raise ValueError(
            "Close column is required."
        )

    if "sentiment_score" not in df.columns:
        raise ValueError(
            "sentiment_score column is required. "
            "Run build_features_enhanced.py first."
        )

    df["sentiment_score"] = pd.to_numeric(
        df["sentiment_score"],
        errors="coerce",
    ).fillna(0.0)

    return df


# ============================================================
# PREPARE LABELS
# ============================================================

def prepare_ticker(
    ticker_df,
):

    ticker_df = ticker_df.sort_values(
        "Date"
    ).reset_index(
        drop=True
    ).copy()

    # --------------------------------------------------------
    # Future 5-day return
    # --------------------------------------------------------

    ticker_df["Future_Return"] = (
        ticker_df["Close"].shift(
            -HORIZON
        )
        / ticker_df["Close"]
        - 1.0
    )

    # Remove rows where future return
    # cannot be calculated.
    ticker_df = ticker_df.dropna(
        subset=[
            "Future_Return"
        ]
    ).reset_index(
        drop=True
    )

    n = len(ticker_df)

    if n < 50:
        return None

    # --------------------------------------------------------
    # Chronological split
    # --------------------------------------------------------

    train_end = int(
        n * TRAIN_RATIO
    )

    val_size = int(
        n * VAL_RATIO
    )

    val_start = (
        train_end
        + EMBARGO_DAYS
    )

    val_end = (
        val_start
        + val_size
    )

    test_start = (
        val_end
        + EMBARGO_DAYS
    )

    if (
        val_start >= n
        or val_end >= n
        or test_start >= n
    ):
        return None

    train_df = ticker_df.iloc[
        :train_end
    ].copy()

    val_df = ticker_df.iloc[
        val_start:val_end
    ].copy()

    test_df = ticker_df.iloc[
        test_start:
    ].copy()

    if (
        len(train_df) == 0
        or len(val_df) == 0
        or len(test_df) == 0
    ):
        return None

    # --------------------------------------------------------
    # TRAIN-ONLY label thresholds
    # --------------------------------------------------------

    sell_threshold = (
        train_df[
            "Future_Return"
        ]
        .quantile(
            SELL_QUANTILE
        )
    )

    buy_threshold = (
        train_df[
            "Future_Return"
        ]
        .quantile(
            BUY_QUANTILE
        )
    )

    # --------------------------------------------------------
    # Label function
    # --------------------------------------------------------

    def assign_labels(
        data
    ):

        labels = np.full(
            len(data),
            -1,
            dtype=int,
        )

        labels[
            data[
                "Future_Return"
            ].to_numpy()
            <= sell_threshold
        ] = 0

        labels[
            data[
                "Future_Return"
            ].to_numpy()
            >= buy_threshold
        ] = 1

        return labels

    train_df["Label"] = (
        assign_labels(
            train_df
        )
    )

    val_df["Label"] = (
        assign_labels(
            val_df
        )
    )

    test_df["Label"] = (
        assign_labels(
            test_df
        )
    )

    return {
        "train": train_df,
        "val": val_df,
        "test": test_df,
        "sell_threshold":
            sell_threshold,
        "buy_threshold":
            buy_threshold,
    }


# ============================================================
# BUILD COMPLETE SPLITS
# ============================================================

def build_splits(df):

    print("\n" + "=" * 80)
    print("BUILDING CHRONOLOGICAL SPLITS")
    print("=" * 80)

    train_parts = []
    val_parts = []
    test_parts = []

    threshold_records = []

    for ticker, ticker_df in (
        df.groupby(
            "Ticker",
            sort=False
        )
    ):

        result = prepare_ticker(
            ticker_df
        )

        if result is None:
            continue

        train_parts.append(
            result["train"]
        )

        val_parts.append(
            result["val"]
        )

        test_parts.append(
            result["test"]
        )

        threshold_records.append(
            {
                "Ticker": ticker,
                "Sell_Threshold":
                    result[
                        "sell_threshold"
                    ],
                "Buy_Threshold":
                    result[
                        "buy_threshold"
                    ],
            }
        )

    if not train_parts:
        raise RuntimeError(
            "No valid ticker splits."
        )

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

    thresholds_df = pd.DataFrame(
        threshold_records
    )

    # --------------------------------------------------------
    # Remove neutral rows
    # --------------------------------------------------------

    train_model = train_df[
        train_df["Label"] != -1
    ].copy()

    val_model = val_df[
        val_df["Label"] != -1
    ].copy()

    test_model = test_df[
        test_df["Label"] != -1
    ].copy()

    # --------------------------------------------------------
    # Print split information
    # --------------------------------------------------------

    print(
        f"\nTrain rows: "
        f"{len(train_model):,}"
    )

    print(
        f"Validation rows: "
        f"{len(val_model):,}"
    )

    print(
        f"Test rows: "
        f"{len(test_model):,}"
    )

    print("\nAll split rows including neutral:")

    print(
        f"Train: "
        f"{len(train_df):,}"
    )

    print(
        f"Validation: "
        f"{len(val_df):,}"
    )

    print(
        f"Test: "
        f"{len(test_df):,}"
    )

    print("\nDate ranges:")

    print(
        f"Train: "
        f"{train_df['Date'].min().date()} "
        f"-> "
        f"{train_df['Date'].max().date()}"
    )

    print(
        f"Validation: "
        f"{val_df['Date'].min().date()} "
        f"-> "
        f"{val_df['Date'].max().date()}"
    )

    print(
        f"Test: "
        f"{test_df['Date'].min().date()} "
        f"-> "
        f"{test_df['Date'].max().date()}"
    )

    print("\nClass distributions:")

    for name, part in [
        ("Train", train_model),
        ("Validation", val_model),
        ("Test", test_model),
    ]:

        counts = (
            part["Label"]
            .value_counts()
            .sort_index()
        )

        print(
            f"{name:<12}: "
            f"SELL={counts.get(0, 0):,} "
            f"BUY={counts.get(1, 0):,}"
        )

    return (
        train_model,
        val_model,
        test_model,
        thresholds_df,
    )


# ============================================================
# EXTRACT X / Y
# ============================================================

def xy(
    df
):

    X = (
        df[FEATURES]
        .replace(
            [np.inf, -np.inf],
            np.nan,
        )
        .fillna(0.0)
        .astype(float)
        .to_numpy()
    )

    y = (
        df["Label"]
        .astype(int)
        .to_numpy()
    )

    return X, y


# ============================================================
# LOAD TUNED PARAMETERS
# ============================================================

def load_best_parameters():

    print("\n" + "=" * 80)
    print("LOADING TUNED HYPERPARAMETERS")
    print("=" * 80)

    if not os.path.exists(
        BEST_PARAMS_PATH
    ):

        raise FileNotFoundError(
            f"Could not find:\n"
            f"{BEST_PARAMS_PATH}\n\n"
            "Run hyperparameter_tuning.py first."
        )

    data = load_json(
        BEST_PARAMS_PATH
    )

    print(
        "Loaded best_hyperparameters.json"
    )

    return data


# ============================================================
# PARAMETER EXTRACTION
# ============================================================

def extract_params(
    all_params,
    model_name,
):
    """
    Handles common JSON structures produced
    by the tuning script.
    """

    if model_name in all_params:

        params = all_params[
            model_name
        ]

        if isinstance(
            params,
            dict
        ):

            # Some tuning outputs contain:
            # {"params": {...}}
            if (
                "params" in params
                and isinstance(
                    params["params"],
                    dict
                )
            ):
                return params[
                    "params"
                ].copy()

            return params.copy()

    # Alternative naming
    alternatives = {
        "Random Forest": [
            "RandomForest",
            "random_forest",
            "RF",
        ],
        "CatBoost": [
            "catboost",
            "CatBoostClassifier",
        ],
        "LightGBM": [
            "lightgbm",
            "LightGBMClassifier",
            "LGBM",
        ],
        "XGBoost": [
            "xgboost",
            "XGB",
            "XGBClassifier",
        ],
    }

    for key in alternatives.get(
        model_name,
        [],
    ):

        if key in all_params:

            params = all_params[
                key
            ]

            if isinstance(
                params,
                dict
            ):

                if (
                    "params" in params
                    and isinstance(
                        params["params"],
                        dict
                    )
                ):
                    return params[
                        "params"
                    ].copy()

                return params.copy()

    raise KeyError(
        f"Could not find tuned "
        f"parameters for {model_name} "
        f"in {BEST_PARAMS_PATH}"
    )


# ============================================================
# CLEAN MODEL PARAMETERS
# ============================================================

def clean_params(
    params,
    model_name,
):

    params = params.copy()

    # Remove values that are metadata,
    # if present.

    metadata_keys = [
        "accuracy",
        "balanced_accuracy",
        "macro_f1",
        "logloss",
        "log_loss",
        "roc_auc",
        "roc_auc_score",
        "brier_score",
        "trial",
        "score",
    ]

    for key in metadata_keys:
        params.pop(
            key,
            None,
        )

    # --------------------------------------------------------
    # RF
    # --------------------------------------------------------

    if model_name == "Random Forest":

        # Ensure deterministic result.
        params["random_state"] = 42
        params["n_jobs"] = -1

    # --------------------------------------------------------
    # CatBoost
    # --------------------------------------------------------

    elif model_name == "CatBoost":

        params["random_seed"] = 42
        params["verbose"] = False
        params["allow_writing_files"] = False

    # --------------------------------------------------------
    # LightGBM
    # --------------------------------------------------------

    elif model_name == "LightGBM":

        params["random_state"] = 42
        params["n_jobs"] = -1
        params["verbosity"] = -1

    # --------------------------------------------------------
    # XGBoost
    # --------------------------------------------------------

    elif model_name == "XGBoost":

        params["random_state"] = 42
        params["n_jobs"] = -1
        params["eval_metric"] = "logloss"

    return params


# ============================================================
# BUILD MODELS
# ============================================================

def build_models(
    params_json
):

    models = {}

    # --------------------------------------------------------
    # Random Forest
    # --------------------------------------------------------

    rf_params = clean_params(
        extract_params(
            params_json,
            "Random Forest",
        ),
        "Random Forest",
    )

    models["Random Forest"] = (
        RandomForestClassifier(
            **rf_params
        )
    )

    # --------------------------------------------------------
    # CatBoost
    # --------------------------------------------------------

    cat_params = clean_params(
        extract_params(
            params_json,
            "CatBoost",
        ),
        "CatBoost",
    )

    models["CatBoost"] = (
        CatBoostClassifier(
            **cat_params
        )
    )

    # --------------------------------------------------------
    # LightGBM
    # --------------------------------------------------------

    lgb_params = clean_params(
        extract_params(
            params_json,
            "LightGBM",
        ),
        "LightGBM",
    )

    models["LightGBM"] = (
        LGBMClassifier(
            **lgb_params
        )
    )

    # --------------------------------------------------------
    # XGBoost
    # --------------------------------------------------------

    xgb_params = clean_params(
        extract_params(
            params_json,
            "XGBoost",
        ),
        "XGBoost",
    )

    models["XGBoost"] = (
        XGBClassifier(
            **xgb_params
        )
    )

    return models


# ============================================================
# TRAIN MODELS
# ============================================================

def train_models(
    models,
    X_train,
    y_train,
):

    print("\n" + "=" * 80)
    print("TRAINING FOUR PRODUCTION MODELS")
    print("=" * 80)

    trained = {}

    for name, model in models.items():

        print(
            f"\nTraining {name}..."
        )

        start = timer()

        model.fit(
            X_train,
            y_train,
        )

        print(
            f"{name} complete | "
            f"time={elapsed(start):.1f}s"
        )

        trained[name] = model

    return trained


# ============================================================
# RAW VALIDATION / TEST PROBABILITIES
# ============================================================

def predict_probability(
    models,
    X,
):

    probabilities = {}

    for name, model in models.items():

        probabilities[name] = (
            model.predict_proba(
                X
            )[:, 1]
        )

    return probabilities



# ============================================================
# SAVE FINAL MODELS WITHOUT CALIBRATORS
# ============================================================

def save_final_models(
    trained_models,
    weights,
    probability_boundary,
    spread_threshold,
):
    """Save production models that emit their native, uncalibrated scores."""

    print("\n" + "=" * 80)
    print("SAVING FINAL MODELS WITHOUT CALIBRATION")
    print("=" * 80)

    joblib.dump(trained_models["Random Forest"], RF_MODEL_PATH)
    trained_models["CatBoost"].save_model(CAT_MODEL_PATH)
    trained_models["LightGBM"].booster_.save_model(LGB_MODEL_PATH)
    trained_models["XGBoost"].save_model(XGB_MODEL_PATH)

    config = {
        "features": FEATURES,
        "number_of_features": len(FEATURES),
        "feature_count": len(FEATURES),
        "sentiment_enabled": True,
        "sentiment_feature": "sentiment_score",
        "sentiment_source": "daily_sentiment_finbert.csv, matched by date and ticker in the prepared dataset",
        "horizon_days": HORIZON,
        "sell_quantile": SELL_QUANTILE,
        "buy_quantile": BUY_QUANTILE,
        "train_ratio": TRAIN_RATIO,
        "validation_ratio": VAL_RATIO,
        "embargo_days": EMBARGO_DAYS,
        "ensemble_weights": weights,
        "probability_boundary": probability_boundary,
        "spread_threshold": spread_threshold,
        "calibration": "none",
        "probability_source": "native model predict_proba output",
        "models": {
            "Random Forest": os.path.basename(RF_MODEL_PATH),
            "CatBoost": os.path.basename(CAT_MODEL_PATH),
            "LightGBM": os.path.basename(LGB_MODEL_PATH),
            "XGBoost": os.path.basename(XGB_MODEL_PATH),
        },
    }

    with open(FINAL_CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4)

    print("\nSaved final model artifacts:")
    for path in [RF_MODEL_PATH, CAT_MODEL_PATH, LGB_MODEL_PATH, XGB_MODEL_PATH, FINAL_CONFIG_PATH]:
        print(f"  {path}")


# ============================================================
# BUILD ENSEMBLE
# ============================================================

def optimize_ensemble_weights(validation_probabilities, y_validation, initial_weights):
    """Fit nonnegative ensemble weights using validation data only."""
    names = list(initial_weights)
    matrix = np.column_stack([validation_probabilities[name] for name in names])
    initial = np.array([float(initial_weights[name]) for name in names], dtype=float)
    initial = initial / initial.sum()

    def objective(weights):
        combined = np.clip(matrix @ weights, 1e-7, 1.0 - 1e-7)
        validation_log_loss = log_loss(y_validation, combined, labels=[0, 1])
        # Small shrinkage term prevents unstable extreme weights on one split.
        stability_penalty = 0.01 * float(np.sum((weights - initial) ** 2))
        return validation_log_loss + stability_penalty

    result = minimize(
        objective,
        initial,
        method="SLSQP",
        bounds=[(0.0, 1.0)] * len(names),
        constraints=[{"type": "eq", "fun": lambda weights: np.sum(weights) - 1.0}],
        options={"maxiter": 500, "ftol": 1e-10},
    )

    if not result.success or not np.all(np.isfinite(result.x)):
        warnings.warn(
            f"Validation weight optimization failed ({result.message}); retaining existing weights."
        )
        return {name: float(weight) for name, weight in zip(names, initial)}

    optimized = np.clip(result.x, 0.0, 1.0)
    optimized = optimized / optimized.sum()
    return {name: float(weight) for name, weight in zip(names, optimized)}


def build_ensemble(
    probabilities,
    weights,
):

    ensemble = np.zeros(
        len(
            next(
                iter(
                    probabilities.values()
                )
            )
        )
    )

    for name, weight in (
        weights.items()
    ):

        if name not in probabilities:

            raise KeyError(
                f"Missing model probability "
                f"for {name}"
            )

        ensemble += (
            weight
            * probabilities[name]
        )

    return ensemble


# ============================================================
# DECISION ENGINE
# ============================================================

def generate_decisions(
    buy_probability,
    spread_threshold,
    probability_boundary,
):

    sell_probability = (
        1.0
        - buy_probability
    )

    spread = np.abs(
        buy_probability
        - sell_probability
    )

    decisions = np.full(
        len(buy_probability),
        "HOLD",
        dtype=object,
    )

    buy_mask = (
        (buy_probability
         >= probability_boundary)
        & (spread
           >= spread_threshold)
    )

    sell_mask = (
        (buy_probability
         < probability_boundary)
        & (spread
           >= spread_threshold)
    )

    decisions[buy_mask] = "BUY"
    decisions[sell_mask] = "SELL"

    return (
        sell_probability,
        spread,
        decisions,
    )


# ============================================================
# EVALUATE MODEL
# ============================================================

def calculate_metrics(
    y_true,
    probability,
):

    prediction = (
        probability >= 0.50
    ).astype(int)

    return {
        "Accuracy": float(
            accuracy_score(
                y_true,
                prediction,
            )
        ),
        "Balanced_Accuracy": float(
            balanced_accuracy_score(
                y_true,
                prediction,
            )
        ),
        "Macro_F1": float(
            f1_score(
                y_true,
                prediction,
                average="macro",
            )
        ),
        "LogLoss": float(
            log_loss(
                y_true,
                probability,
                labels=[0, 1],
            )
        ),
        "ROC_AUC": float(
            roc_auc_score(
                y_true,
                probability,
            )
        ),
        "Brier_Score": float(
            brier_score_loss(
                y_true,
                probability,
            )
        ),
    }


# ============================================================
# DECISION METRICS
# ============================================================

def calculate_decision_metrics(
    y_true,
    decisions,
):

    trade_mask = (
        decisions != "HOLD"
    )

    trade_count = int(
        trade_mask.sum()
    )

    coverage = (
        trade_count
        / len(decisions)
    )

    if trade_count == 0:

        return {
            "Coverage": 0.0,
            "HOLD_Rate": 1.0,
            "Trade_Count": 0,
            "Accuracy": None,
            "Balanced_Accuracy": None,
            "Macro_F1": None,
            "BUY_Count": 0,
            "SELL_Count": 0,
            "HOLD_Count": int(
                len(decisions)
            ),
        }

    trade_actual = (
        y_true[trade_mask]
    )

    trade_prediction = (
        decisions[trade_mask]
        == "BUY"
    ).astype(int)

    return {
        "Coverage": float(
            coverage
        ),
        "HOLD_Rate": float(
            1.0 - coverage
        ),
        "Trade_Count": trade_count,
        "Accuracy": float(
            accuracy_score(
                trade_actual,
                trade_prediction,
            )
        ),
        "Balanced_Accuracy": float(
            balanced_accuracy_score(
                trade_actual,
                trade_prediction,
            )
        ),
        "Macro_F1": float(
            f1_score(
                trade_actual,
                trade_prediction,
                average="macro",
            )
        ),
        "BUY_Count": int(
            (decisions == "BUY").sum()
        ),
        "SELL_Count": int(
            (decisions == "SELL").sum()
        ),
        "HOLD_Count": int(
            (decisions == "HOLD").sum()
        ),
    }


# ============================================================
# MAIN
# ============================================================

def main():

    total_start = timer()

    print("\n")
    print("=" * 80)
    print("QUANTEDGE FINAL MODEL EVALUATION + SENTIMENT (NO CALIBRATION)")
    print("=" * 80)

    print(
        "\nTHIS SCRIPT RUNS THE SENTIMENT-ENABLED FINAL TEST."
    )

    print(
        "\nIMPORTANT: This is a new 34-feature model experiment."
    )

    print(
        "The previous 33-feature test result is NOT reused as validation."
    )

    print(
        "Historical sentiment is supplied through sentiment_score."
    )

    print(
        "\nExisting frozen ensemble weights (applied to native probabilities):"
    )

    print(
        "RF       = 50%"
    )

    print(
        "CatBoost = 10%"
    )

    print(
        "LightGBM = 10%"
    )

    print(
        "XGBoost  = 30%"
    )

    # ========================================================
    # 1. LOAD FROZEN CONFIG
    # ========================================================

    (
        weights,
        probability_boundary,
        spread_threshold,
    ) = load_frozen_configuration()

    # ========================================================
    # 2. LOAD DATA
    # ========================================================

    df = load_data()

    # ========================================================
    # 3. BUILD SPLITS
    # ========================================================

    (
        train_df,
        validation_df,
        test_df,
        thresholds_df,
    ) = build_splits(
        df
    )

    # ========================================================
    # 4. EXTRACT X / Y
    # ========================================================

    X_train, y_train = xy(
        train_df
    )

    X_validation, y_validation = xy(
        validation_df
    )

    X_test, y_test = xy(
        test_df
    )

    print("\nFeature matrix shapes:")

    print(
        f"X_train      : "
        f"{X_train.shape}"
    )

    print(
        f"X_validation : "
        f"{X_validation.shape}"
    )

    print(
        f"X_test       : "
        f"{X_test.shape}"
    )

    print(
        f"\nNumber of features: "
        f"{len(FEATURES)}"
    )

    print(
        "Sentiment feature: sentiment_score"
    )

    print(
        f"Sentiment train mean: "
        f"{train_df['sentiment_score'].mean():.6f}"
    )

    print(
        f"Sentiment validation mean: "
        f"{validation_df['sentiment_score'].mean():.6f}"
    )

    print(
        f"Sentiment test mean: "
        f"{test_df['sentiment_score'].mean():.6f}"
    )

    # ========================================================
    # 5. LOAD TUNED PARAMETERS
    # ========================================================

    params_json = (
        load_best_parameters()
    )

    # ========================================================
    # 6. BUILD MODELS
    # ========================================================

    models = build_models(
        params_json
    )

    # ========================================================
    # 7. TRAIN FINAL MODELS
    # ========================================================

    trained_models = train_models(
        models,
        X_train,
        y_train,
    )

    # ========================================================
    # 8. RAW VALIDATION PROBABILITIES
    # ========================================================

    print("\n" + "=" * 80)
    print("GENERATING VALIDATION PROBABILITIES")
    print("=" * 80)

    raw_validation = (
        predict_probability(
            trained_models,
            X_validation,
        )
    )

    # ========================================================
    # 9. VALIDATE NATIVE MODEL PROBABILITIES (NO CALIBRATION)
    # ========================================================

    validation_metrics = {}
    for name, probability in raw_validation.items():
        validation_metrics[name] = calculate_metrics(y_validation, probability)
        print(
            f"Validation {name}: "
            f"accuracy={validation_metrics[name]['Accuracy']:.4f}, "
            f"balanced_accuracy={validation_metrics[name]['Balanced_Accuracy']:.4f}, "
            f"ROC-AUC={validation_metrics[name]['ROC_AUC']:.4f}"
        )

    weights = optimize_ensemble_weights(raw_validation, y_validation, weights)
    with open(WEIGHTS_PATH, "w", encoding="utf-8") as weight_file:
        json.dump(weights, weight_file, indent=4)
    print("\nValidation-optimized raw-probability ensemble weights:")
    for model_name, model_weight in weights.items():
        print(f"{model_name:<15}: {model_weight:.2%}")

    validation_ensemble = build_ensemble(raw_validation, weights)
    validation_ensemble_metrics = calculate_metrics(y_validation, validation_ensemble)
    print(
        "Validation ensemble (weights fitted on validation only): "
        f"accuracy={validation_ensemble_metrics['Accuracy']:.4f}, "
        f"balanced_accuracy={validation_ensemble_metrics['Balanced_Accuracy']:.4f}, "
        f"ROC-AUC={validation_ensemble_metrics['ROC_AUC']:.4f}"
    )

    # ========================================================
    # 11. RAW TEST PROBABILITIES
    # ========================================================

    print("\n" + "=" * 80)
    print("GENERATING FINAL TEST PROBABILITIES")
    print("=" * 80)

    raw_test = (
        predict_probability(
            trained_models,
            X_test,
        )
    )

    # ========================================================
    # 12. USE NATIVE TEST PROBABILITIES (NO CALIBRATION)
    # ========================================================

    native_test = raw_test

    # ========================================================
    # 13. INDIVIDUAL MODEL TEST RESULTS
    # ========================================================

    print("\n" + "=" * 80)
    print("INDIVIDUAL MODEL TEST RESULTS")
    print("=" * 80)

    individual_metrics = {}

    for name, probability in (
        native_test.items()
    ):

        metrics = calculate_metrics(
            y_test,
            probability,
        )

        individual_metrics[name] = (
            metrics
        )

        print(
            f"\n{name}"
        )

        print(
            f"Accuracy: "
            f"{metrics['Accuracy']:.4f}"
        )

        print(
            f"Balanced Accuracy: "
            f"{metrics['Balanced_Accuracy']:.4f}"
        )

        print(
            f"Macro F1: "
            f"{metrics['Macro_F1']:.4f}"
        )

        print(
            f"LogLoss: "
            f"{metrics['LogLoss']:.4f}"
        )

        print(
            f"ROC-AUC: "
            f"{metrics['ROC_AUC']:.4f}"
        )

        print(
            f"Brier Score: "
            f"{metrics['Brier_Score']:.4f}"
        )

    # ========================================================
    # 14. FINAL FROZEN ENSEMBLE
    # ========================================================

    print("\n" + "=" * 80)
    print("BUILDING FINAL FROZEN ENSEMBLE")
    print("=" * 80)

    ensemble_probability = (
        build_ensemble(
            native_test,
            weights,
        )
    )

    ensemble_metrics = (
        calculate_metrics(
            y_test,
            ensemble_probability,
        )
    )

    print(
        "\nFINAL ENSEMBLE TEST RESULTS"
    )

    print(
        f"Accuracy: "
        f"{ensemble_metrics['Accuracy']:.4f}"
    )

    print(
        f"Balanced Accuracy: "
        f"{ensemble_metrics['Balanced_Accuracy']:.4f}"
    )

    print(
        f"Macro F1: "
        f"{ensemble_metrics['Macro_F1']:.4f}"
    )

    print(
        f"LogLoss: "
        f"{ensemble_metrics['LogLoss']:.4f}"
    )

    print(
        f"ROC-AUC: "
        f"{ensemble_metrics['ROC_AUC']:.4f}"
    )

    print(
        f"Brier Score: "
        f"{ensemble_metrics['Brier_Score']:.4f}"
    )

    # ========================================================
    # 15. FINAL DECISION ENGINE
    # ========================================================

    print("\n" + "=" * 80)
    print("APPLYING FROZEN DECISION ENGINE")
    print("=" * 80)

    (
        ensemble_sell,
        spread,
        final_signal,
    ) = generate_decisions(
        ensemble_probability,
        spread_threshold,
        probability_boundary,
    )

    decision_metrics = (
        calculate_decision_metrics(
            y_test,
            final_signal,
        )
    )

    print(
        f"\nFrozen spread threshold: "
        f"{spread_threshold:.2f}"
    )

    print(
        f"Test coverage: "
        f"{decision_metrics['Coverage']:.2%}"
    )

    print(
        f"Test HOLD rate: "
        f"{decision_metrics['HOLD_Rate']:.2%}"
    )

    print(
        f"Test BUY decisions: "
        f"{decision_metrics['BUY_Count']:,}"
    )

    print(
        f"Test SELL decisions: "
        f"{decision_metrics['SELL_Count']:,}"
    )

    print(
        f"Test HOLD decisions: "
        f"{decision_metrics['HOLD_Count']:,}"
    )

    print(
        f"Decision Accuracy: "
        f"{decision_metrics['Accuracy']:.4f}"
    )

    print(
        f"Decision Balanced Accuracy: "
        f"{decision_metrics['Balanced_Accuracy']:.4f}"
    )

    print(
        f"Decision Macro F1: "
        f"{decision_metrics['Macro_F1']:.4f}"
    )

    # ========================================================
    # 16. BUILD TEST OUTPUT
    # ========================================================

    test_output = test_df[
        [
            "Ticker",
            "Date",
            "Close",
            "Future_Return",
            "Label",
        ]
    ].copy()

    test_output["sentiment_score"] = (
        test_df["sentiment_score"].to_numpy()
    )

    test_output[
        "Random Forest_Probability"
    ] = native_test[
        "Random Forest"
    ]

    test_output[
        "CatBoost_Probability"
    ] = native_test[
        "CatBoost"
    ]

    test_output[
        "LightGBM_Probability"
    ] = native_test[
        "LightGBM"
    ]

    test_output[
        "XGBoost_Probability"
    ] = native_test[
        "XGBoost"
    ]

    test_output[
        "Ensemble_BUY"
    ] = ensemble_probability

    test_output[
        "Ensemble_SELL"
    ] = ensemble_sell

    test_output[
        "Spread"
    ] = spread

    test_output[
        "Final_Signal"
    ] = final_signal

    # ========================================================
    # 17. SAVE PRODUCTION MODELS AFTER EVALUATION SUCCEEDS
    # ========================================================

    save_final_models(
        trained_models=trained_models,
        weights=weights,
        probability_boundary=probability_boundary,
        spread_threshold=spread_threshold,
    )

    # ========================================================
    # 18. SAVE TEST PREDICTIONS
    # ========================================================

    test_output.to_csv(
        PREDICTIONS_PATH,
        index=False,
    )

    # ========================================================
    # 19. SAVE METRICS
    # ========================================================

    final_metrics = {

        "configuration": {

            "features": FEATURES,

            "number_of_features":
                len(FEATURES),

            "horizon_days":
                HORIZON,

            "sell_quantile":
                SELL_QUANTILE,

            "buy_quantile":
                BUY_QUANTILE,

            "train_ratio":
                TRAIN_RATIO,

            "validation_ratio":
                VAL_RATIO,

            "embargo_days":
                EMBARGO_DAYS,

            "sentiment_enabled":
                True,

            "sentiment_feature":
                "sentiment_score",

            "sentiment_source":
                "daily_sentiment_finbert.csv matched by date and ticker in processed_data_enhanced.csv",

            "ensemble_weights":
                weights,

            "probability_boundary":
                probability_boundary,

            "spread_threshold":
                spread_threshold,
        },

        "dataset": {

            "train_rows":
                int(len(train_df)),

            "validation_rows":
                int(len(validation_df)),

            "test_rows":
                int(len(test_df)),

            "train_model_rows":
                int(len(train_df[train_df["Label"] != -1])),

            "test_start":
                str(
                    test_df[
                        "Date"
                    ].min().date()
                ),

            "test_end":
                str(
                    test_df[
                        "Date"
                    ].max().date()
                ),
        },

        "validation": {
            "individual_models": validation_metrics,
            "ensemble": validation_ensemble_metrics,
        },

        "individual_models":
            individual_metrics,

        "ensemble":
            ensemble_metrics,

        "decision_engine":
            decision_metrics,
    }

    with open(
        METRICS_PATH,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            final_metrics,
            f,
            indent=4,
        )

    # ========================================================
    # 20. SAVE MODEL SUMMARY
    # ========================================================

    model_summary = {

        "models": [
            "Random Forest",
            "CatBoost",
            "LightGBM",
            "XGBoost",
        ],

        "ensemble_weights":
            weights,

        "calibration":
            "none",

        "sentiment_enabled":
            True,

        "sentiment_feature":
            "sentiment_score",

        "sentiment_source":
            "daily_sentiment_finbert.csv matched by date and ticker in processed_data_enhanced.csv",

        "decision_threshold":
            spread_threshold,

        "test_used_for_tuning":
            False,

        "features":
            FEATURES,

        "horizon":
            HORIZON,

        "embargo":
            EMBARGO_DAYS,
    }

    with open(
        MODEL_SUMMARY_PATH,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            model_summary,
            f,
            indent=4,
        )

    # ========================================================
    # 21. SAMPLE TEST DECISIONS
    # ========================================================

    print("\n" + "=" * 80)
    print("SAMPLE FINAL TEST DECISIONS")
    print("=" * 80)

    print(
        test_output[
            [
                "Ticker",
                "Date",
                "Ensemble_BUY",
                "Ensemble_SELL",
                "Spread",
                "Label",
                "Final_Signal",
            ]
        ]
        .head(25)
        .to_string(
            index=False
        )
    )

    # ========================================================
    # 22. FINAL SUMMARY
    # ========================================================

    print("\n" + "=" * 80)
    print("FINAL TEST COMPLETE")
    print("=" * 80)

    print(
        "\nFINAL ENSEMBLE:"
    )

    print(
        f"Accuracy           : "
        f"{ensemble_metrics['Accuracy']:.4f}"
    )

    print(
        f"Balanced Accuracy  : "
        f"{ensemble_metrics['Balanced_Accuracy']:.4f}"
    )

    print(
        f"Macro F1           : "
        f"{ensemble_metrics['Macro_F1']:.4f}"
    )

    print(
        f"LogLoss            : "
        f"{ensemble_metrics['LogLoss']:.4f}"
    )

    print(
        f"ROC-AUC            : "
        f"{ensemble_metrics['ROC_AUC']:.4f}"
    )

    print(
        f"Brier Score        : "
        f"{ensemble_metrics['Brier_Score']:.4f}"
    )

    print(
        "\nFINAL DECISION ENGINE:"
    )

    print(
        f"Coverage           : "
        f"{decision_metrics['Coverage']:.2%}"
    )

    print(
        f"HOLD Rate          : "
        f"{decision_metrics['HOLD_Rate']:.2%}"
    )

    print(
        f"BUY                : "
        f"{decision_metrics['BUY_Count']:,}"
    )

    print(
        f"SELL               : "
        f"{decision_metrics['SELL_Count']:,}"
    )

    print(
        f"HOLD               : "
        f"{decision_metrics['HOLD_Count']:,}"
    )

    print("\nFiles saved:")

    print(
        f"1. {PREDICTIONS_PATH}"
    )

    print(
        f"2. {METRICS_PATH}"
    )

    print(
        f"3. {MODEL_SUMMARY_PATH}"
    )

    print(
        "\nTotal execution time: "
        f"{elapsed(total_start):.1f}s"
    )

    print("\n" + "=" * 80)
    print("IMPORTANT")
    print("=" * 80)

    print(
        "The test set was used ONLY for this sentiment-enabled "
        "final evaluation."
    )

    print(
        "Do NOT change model parameters, "
        "ensemble weights, or decision "
        "threshold based on these "
        "test results and rerun the test."
    )


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    main()