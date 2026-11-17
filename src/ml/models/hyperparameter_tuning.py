import time
import json

import numpy as np
import pandas as pd

from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    log_loss,
    roc_auc_score,
)

from sklearn.ensemble import RandomForestClassifier
from lightgbm import LGBMClassifier
from catboost import CatBoostClassifier
from xgboost import XGBClassifier


# ============================================================
# CONFIG
# ============================================================

DATA_PATH = "src/data/processed_data_enhanced.csv"

OUTPUT_DIR = "src/ml/models"

BEST_PARAMS_PATH = (
    f"{OUTPUT_DIR}/best_hyperparameters.json"
)

TUNING_RESULTS_PATH = (
    f"{OUTPUT_DIR}/hyperparameter_tuning_results.csv"
)

RANDOM_STATE = 42

# Same configuration as final_evaluation.py
TRAIN_RATIO = 0.70
VAL_RATIO = 0.15
EMBARGO_DAYS = 5

HORIZON = 5

SELL_QUANTILE = 0.30
BUY_QUANTILE = 0.70

# Number of random configurations per model
N_TRIALS = 20


# ============================================================
# FINAL 34 FEATURES
# MUST MATCH final_evaluation.py EXACTLY
# ============================================================

FEATURES = [

    # -------------------------------
    # Returns / Momentum
    # -------------------------------

    "Return",
    "Return_3D",
    "Return_5D",
    "Return_10D",
    "ROC_20",

    # -------------------------------
    # Moving Average Ratios
    # -------------------------------

    "Price_MA5_Ratio",
    "Price_MA10_Ratio",
    "Price_EMA20_Ratio",
    "Price_EMA50_Ratio",

    "EMA5_EMA20_Ratio",
    "EMA20_EMA50_Ratio",

    # -------------------------------
    # RSI / Oscillators
    # -------------------------------

    "RSI",
    "RSI_Lag1",

    "Stochastic_K_14",
    "Stochastic_D_3",

    "Williams_R_14",

    "ADX14",

    # -------------------------------
    # Volatility
    # -------------------------------

    "ATR14_Ratio",

    "Volatility",
    "Volatility_10",
    "Volatility_20",

    # -------------------------------
    # Bollinger Bands
    # -------------------------------

    "Bollinger_Position",
    "Bollinger_Width",

    # -------------------------------
    # Price Structure
    # -------------------------------

    "High_Low_Range",
    "Candle_Body",
    "Gap_Return",

    # -------------------------------
    # Volume
    # -------------------------------

    "Volume_Change",
    "Volume_Ratio",
    "Volume_Ratio_20",
    "Volume_ROC_10",

    # -------------------------------
    # Lagged Information
    # -------------------------------

    "Return_Lag1",
    "Return_Lag5",

    "MACD_Hist_Lag1",

    # -------------------------------
    # SENTIMENT
    # -------------------------------

    "sentiment_score",
]


# ============================================================
# VERIFY FEATURE COUNT
# ============================================================

if len(FEATURES) != 34:

    raise ValueError(
        f"Expected 34 features, "
        f"but found {len(FEATURES)}."
    )


# ============================================================
# CREATE FUTURE RETURN
# ============================================================

def create_future_return(df):

    df = df.copy()

    df = (
        df
        .sort_values(
            ["Ticker", "Date"]
        )
        .reset_index(drop=True)
    )

    df["Future_Return"] = (
        df.groupby("Ticker")["Close"]
        .shift(-HORIZON)
        / df["Close"]
        - 1.0
    )

    return df


# ============================================================
# CREATE LABELS
#
# 0 = SELL
# 1 = BUY
#
# Neutral observations are removed.
# ============================================================

def create_labels(
    future_returns,
    sell_threshold,
    buy_threshold,
):

    labels = np.full(
        len(future_returns),
        -1,
        dtype=int,
    )

    labels[
        future_returns <= sell_threshold
    ] = 0

    labels[
        future_returns >= buy_threshold
    ] = 1

    return labels


# ============================================================
# BUILD TRAIN / VALIDATION SPLIT
#
# SAME STRUCTURE AS FINAL_EVALUATION.PY
#
# 70% TRAIN
# 5-DAY EMBARGO
# 15% VALIDATION
# 5-DAY EMBARGO
# Remaining = TEST
#
# IMPORTANT:
# TEST IS NOT RETURNED OR USED.
# ============================================================

def build_train_validation_split(df):

    train_parts = []
    val_parts = []

    threshold_records = []

    for ticker, ticker_df in df.groupby(
        "Ticker",
        sort=False,
    ):

        ticker_df = (
            ticker_df
            .sort_values("Date")
            .reset_index(drop=True)
            .copy()
        )

        n = len(ticker_df)

        if n < 50:
            continue

        # ----------------------------------------------------
        # SAME SPLIT AS FINAL EVALUATION
        # ----------------------------------------------------

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

        # ----------------------------------------------------
        # We need a valid validation region.
        # ----------------------------------------------------

        if (
            val_start >= n
            or val_end >= n
        ):
            continue

        train_df = ticker_df.iloc[
            :train_end
        ].copy()

        val_df = ticker_df.iloc[
            val_start:val_end
        ].copy()

        if (
            len(train_df) == 0
            or len(val_df) == 0
        ):
            continue

        # ----------------------------------------------------
        # TRAIN-ONLY LABEL THRESHOLDS
        # ----------------------------------------------------

        sell_threshold = (
            train_df["Future_Return"]
            .quantile(
                SELL_QUANTILE
            )
        )

        buy_threshold = (
            train_df["Future_Return"]
            .quantile(
                BUY_QUANTILE
            )
        )

        # ----------------------------------------------------
        # LABEL TRAIN
        # ----------------------------------------------------

        train_df["Label"] = create_labels(
            train_df["Future_Return"].values,
            sell_threshold,
            buy_threshold,
        )

        # ----------------------------------------------------
        # LABEL VALIDATION
        #
        # Uses thresholds calculated ONLY
        # from training data.
        # ----------------------------------------------------

        val_df["Label"] = create_labels(
            val_df["Future_Return"].values,
            sell_threshold,
            buy_threshold,
        )

        # ----------------------------------------------------
        # REMOVE HOLD / NEUTRAL OBSERVATIONS
        # ----------------------------------------------------

        train_df = train_df[
            train_df["Label"] != -1
        ].copy()

        val_df = val_df[
            val_df["Label"] != -1
        ].copy()

        if (
            len(train_df) == 0
            or len(val_df) == 0
        ):
            continue

        train_parts.append(train_df)
        val_parts.append(val_df)

        threshold_records.append(
            {
                "Ticker": ticker,
                "Sell_Threshold": sell_threshold,
                "Buy_Threshold": buy_threshold,
            }
        )

    if not train_parts:
        raise RuntimeError(
            "No valid training splits were created."
        )

    if not val_parts:
        raise RuntimeError(
            "No valid validation splits were created."
        )

    train_df = pd.concat(
        train_parts,
        ignore_index=True,
    )

    val_df = pd.concat(
        val_parts,
        ignore_index=True,
    )

    # --------------------------------------------------------
    # CLEAN
    # --------------------------------------------------------

    train_df = train_df.replace(
        [np.inf, -np.inf],
        np.nan,
    )

    val_df = val_df.replace(
        [np.inf, -np.inf],
        np.nan,
    )

    # --------------------------------------------------------
    # Make sure sentiment is numeric
    # --------------------------------------------------------

    train_df["sentiment_score"] = (
        pd.to_numeric(
            train_df["sentiment_score"],
            errors="coerce",
        )
    )

    val_df["sentiment_score"] = (
        pd.to_numeric(
            val_df["sentiment_score"],
            errors="coerce",
        )
    )

    # Missing sentiment = neutral
    train_df["sentiment_score"] = (
        train_df["sentiment_score"]
        .fillna(0.0)
    )

    val_df["sentiment_score"] = (
        val_df["sentiment_score"]
        .fillna(0.0)
    )

    # --------------------------------------------------------
    # Drop rows with invalid feature values
    # --------------------------------------------------------

    train_df.dropna(
        subset=FEATURES + ["Label"],
        inplace=True,
    )

    val_df.dropna(
        subset=FEATURES + ["Label"],
        inplace=True,
    )

    train_df = train_df.reset_index(
        drop=True
    )

    val_df = val_df.reset_index(
        drop=True
    )

    return (
        train_df,
        val_df,
        pd.DataFrame(threshold_records),
    )


# ============================================================
# METRICS
# ============================================================

def calculate_metrics(
    y_true,
    probabilities,
):

    predictions = (
        probabilities >= 0.50
    ).astype(int)

    return {

        "Accuracy": accuracy_score(
            y_true,
            predictions,
        ),

        "Balanced_Accuracy": (
            balanced_accuracy_score(
                y_true,
                predictions,
            )
        ),

        "Macro_F1": f1_score(
            y_true,
            predictions,
            average="macro",
        ),

        "LogLoss": log_loss(
            y_true,
            probabilities,
        ),

        "ROC_AUC": roc_auc_score(
            y_true,
            probabilities,
        ),
    }


# ============================================================
# PARAMETER SEARCH SPACES
# ============================================================

PARAM_SPACES = {

    # ========================================================
    # RANDOM FOREST
    # ========================================================

    "Random Forest": {

        "n_estimators": [
            300,
            500,
            700,
        ],

        "max_depth": [
            6,
            8,
            10,
            12,
            16,
            None,
        ],

        "min_samples_split": [
            2,
            5,
            10,
            20,
        ],

        "min_samples_leaf": [
            1,
            2,
            5,
            10,
        ],

        "max_features": [
            "sqrt",
            "log2",
            0.5,
            0.8,
        ],

        "class_weight": [
            None,
            "balanced",
        ],
    },


    # ========================================================
    # LIGHTGBM
    # ========================================================

    "LightGBM": {

        "n_estimators": [
            200,
            300,
            500,
            700,
        ],

        "learning_rate": [
            0.01,
            0.02,
            0.03,
            0.05,
        ],

        "num_leaves": [
            7,
            15,
            20,
            31,
            50,
        ],

        "max_depth": [
            -1,
            4,
            6,
            8,
            10,
        ],

        "min_child_samples": [
            10,
            20,
            30,
            50,
        ],

        "subsample": [
            0.7,
            0.8,
            0.9,
            1.0,
        ],

        "colsample_bytree": [
            0.7,
            0.8,
            0.9,
            1.0,
        ],

        "reg_alpha": [
            0,
            0.01,
            0.1,
            1,
        ],

        "reg_lambda": [
            0,
            0.1,
            1,
            5,
        ],
    },


    # ========================================================
    # CATBOOST
    # ========================================================

    "CatBoost": {

        "iterations": [
            200,
            300,
            500,
            700,
        ],

        "learning_rate": [
            0.01,
            0.02,
            0.03,
            0.05,
        ],

        "depth": [
            4,
            5,
            6,
            7,
            8,
        ],

        "l2_leaf_reg": [
            1,
            3,
            5,
            10,
        ],

        "random_strength": [
            0,
            0.5,
            1,
            2,
        ],

        "bagging_temperature": [
            0,
            1,
            2,
            5,
        ],
    },


    # ========================================================
    # XGBOOST
    # ========================================================

    "XGBoost": {

        "n_estimators": [
            200,
            300,
            500,
            700,
        ],

        "learning_rate": [
            0.01,
            0.02,
            0.03,
            0.05,
        ],

        "max_depth": [
            3,
            4,
            5,
            6,
            8,
        ],

        "min_child_weight": [
            1,
            3,
            5,
            10,
        ],

        "subsample": [
            0.7,
            0.8,
            0.9,
            1.0,
        ],

        "colsample_bytree": [
            0.7,
            0.8,
            0.9,
            1.0,
        ],

        "gamma": [
            0,
            0.1,
            0.5,
            1,
        ],

        "reg_alpha": [
            0,
            0.01,
            0.1,
            1,
        ],

        "reg_lambda": [
            0.1,
            1,
            5,
            10,
        ],
    },
}


# ============================================================
# RANDOM PARAMETER SAMPLING
# ============================================================

def generate_trials(
    model_name,
    n_trials,
):

    rng = np.random.default_rng(
        RANDOM_STATE
    )

    space = PARAM_SPACES[
        model_name
    ]

    keys = list(
        space.keys()
    )

    trials = []

    seen = set()

    while len(trials) < n_trials:

        params = {}

        for key in keys:

            values = space[key]

            index = rng.integers(
                0,
                len(values),
            )

            params[key] = values[index]

        signature = json.dumps(
            params,
            sort_keys=True,
            default=str,
        )

        if signature in seen:
            continue

        seen.add(signature)

        trials.append(params)

    return trials


# ============================================================
# BUILD MODEL
# ============================================================

def build_model(
    model_name,
    params,
):

    if model_name == "Random Forest":

        return RandomForestClassifier(
            **params,
            random_state=RANDOM_STATE,
            n_jobs=-1,
        )

    if model_name == "LightGBM":

        return LGBMClassifier(
            **params,
            objective="binary",
            random_state=RANDOM_STATE,
            verbosity=-1,
        )

    if model_name == "CatBoost":

        return CatBoostClassifier(
            **params,
            loss_function="Logloss",
            random_seed=RANDOM_STATE,
            verbose=False,
            allow_writing_files=False,
        )

    if model_name == "XGBoost":

        return XGBClassifier(
            **params,
            objective="binary:logistic",
            eval_metric="logloss",
            random_state=RANDOM_STATE,
            n_jobs=-1,
            tree_method="hist",
        )

    raise ValueError(
        f"Unknown model: {model_name}"
    )


# ============================================================
# EVALUATE ONE PARAMETER CONFIGURATION
# ============================================================

def evaluate_model(
    model_name,
    params,
    train_df,
    val_df,
):

    X_train = train_df[
        FEATURES
    ].values

    y_train = train_df[
        "Label"
    ].values

    X_val = val_df[
        FEATURES
    ].values

    y_val = val_df[
        "Label"
    ].values

    model = build_model(
        model_name,
        params,
    )

    model.fit(
        X_train,
        y_train,
    )

    probabilities = (
        model
        .predict_proba(X_val)[:, 1]
    )

    metrics = calculate_metrics(
        y_val,
        probabilities,
    )

    return metrics


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    total_start = time.time()

    print()
    print("=" * 80)
    print("QUANTEDGE FINAL 34-FEATURE HYPERPARAMETER TUNING")
    print("=" * 80)

    print()
    print(f"Dataset: {DATA_PATH}")
    print(f"Features: {len(FEATURES)}")
    print(f"Horizon: {HORIZON} days")
    print(f"Train ratio: {TRAIN_RATIO:.0%}")
    print(f"Validation ratio: {VAL_RATIO:.0%}")
    print(f"Embargo: {EMBARGO_DAYS} days")
    print(
        f"Label thresholds: "
        f"{SELL_QUANTILE:.0%} / "
        f"{BUY_QUANTILE:.0%}"
    )
    print(f"Trials per model: {N_TRIALS}")

    # ========================================================
    # CREATE OUTPUT DIRECTORY
    # ========================================================

    import os

    os.makedirs(
        OUTPUT_DIR,
        exist_ok=True,
    )

    # ========================================================
    # LOAD DATA
    # ========================================================

    print()
    print("=" * 80)
    print("LOADING DATA")
    print("=" * 80)

    df = pd.read_csv(
        DATA_PATH
    )

    df["Date"] = pd.to_datetime(
        df["Date"]
    )

    df = (
        df
        .sort_values(
            ["Ticker", "Date"]
        )
        .reset_index(drop=True)
    )

    print(
        f"Rows loaded: {len(df):,}"
    )

    print(
        f"Tickers: {df['Ticker'].nunique()}"
    )

    # ========================================================
    # VERIFY ALL 34 FEATURES
    # ========================================================

    print()
    print("=" * 80)
    print("VERIFYING 34 FEATURES")
    print("=" * 80)

    missing_features = [
        feature
        for feature in FEATURES
        if feature not in df.columns
    ]

    if missing_features:

        print(
            "Missing features:"
        )

        for feature in missing_features:
            print(
                f"  - {feature}"
            )

        raise ValueError(
            "The enhanced dataset does not "
            "contain all 34 final features."
        )

    print(
        "All 34 final features are present."
    )

    print(
        "sentiment_score is included."
    )

    # ========================================================
    # VERIFY SENTIMENT
    # ========================================================

    if "sentiment_score" not in df.columns:

        raise ValueError(
            "sentiment_score is missing. "
            "Run build_features_enhanced.py first."
        )

    df["sentiment_score"] = (
        pd.to_numeric(
            df["sentiment_score"],
            errors="coerce",
        )
        .fillna(0.0)
    )

    # ========================================================
    # FUTURE RETURN
    # ========================================================

    print()
    print(
        "Creating 5-day Future_Return..."
    )

    df = create_future_return(
        df
    )

    df = df.dropna(
        subset=["Future_Return"]
    ).copy()

    # ========================================================
    # BUILD TRAIN / VALIDATION
    # ========================================================

    print()
    print("=" * 80)
    print("BUILDING TRAIN / VALIDATION SPLIT")
    print("=" * 80)

    (
        train_df,
        val_df,
        threshold_df,
    ) = build_train_validation_split(
        df
    )

    print()
    print(
        f"Training rows: "
        f"{len(train_df):,}"
    )

    print(
        f"Validation rows: "
        f"{len(val_df):,}"
    )

    print(
        f"Training BUY: "
        f"{(train_df['Label'] == 1).sum():,}"
    )

    print(
        f"Training SELL: "
        f"{(train_df['Label'] == 0).sum():,}"
    )

    print(
        f"Validation BUY: "
        f"{(val_df['Label'] == 1).sum():,}"
    )

    print(
        f"Validation SELL: "
        f"{(val_df['Label'] == 0).sum():,}"
    )

    # ========================================================
    # SAVE SPLIT INFORMATION
    # ========================================================

    threshold_df.to_csv(
        f"{OUTPUT_DIR}/"
        f"tuning_label_thresholds.csv",
        index=False,
    )

    # ========================================================
    # TUNE MODELS
    # ========================================================

    model_names = [

        "Random Forest",

        "CatBoost",

        "LightGBM",

        "XGBoost",
    ]

    all_results = []

    best_models = {}

    # --------------------------------------------------------
    # IMPORTANT:
    # Test set is NEVER loaded here.
    # --------------------------------------------------------

    for model_name in model_names:

        print()
        print()
        print("#" * 80)
        print(
            f"TUNING {model_name.upper()}"
        )
        print("#" * 80)

        model_start = time.time()

        trials = generate_trials(
            model_name,
            N_TRIALS,
        )

        model_results = []

        for trial_number, params in enumerate(
            trials,
            start=1,
        ):

            trial_start = time.time()

            print()
            print(
                f"[{model_name}] "
                f"Trial "
                f"{trial_number}/{N_TRIALS}"
            )

            try:

                metrics = evaluate_model(
                    model_name,
                    params,
                    train_df,
                    val_df,
                )

                result = {

                    "Model": model_name,

                    "Trial": trial_number,

                    "Accuracy":
                        metrics["Accuracy"],

                    "Balanced_Accuracy":
                        metrics[
                            "Balanced_Accuracy"
                        ],

                    "Macro_F1":
                        metrics["Macro_F1"],

                    "LogLoss":
                        metrics["LogLoss"],

                    "ROC_AUC":
                        metrics["ROC_AUC"],

                    "Parameters":
                        json.dumps(
                            params,
                            default=str,
                        ),
                }

                model_results.append(
                    result
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

            except Exception as e:

                print(
                    f"TRIAL FAILED: {e}"
                )

            print(
                f"Trial time: "
                f"{time.time() - trial_start:.1f}s"
            )

        # ====================================================
        # MODEL RESULTS
        # ====================================================

        if not model_results:

            print(
                f"No successful trials "
                f"for {model_name}."
            )

            continue

        model_results_df = pd.DataFrame(
            model_results
        )

        # ----------------------------------------------------
        # Rank by validation ROC-AUC
        # ----------------------------------------------------

        model_results_df = (
            model_results_df
            .sort_values(
                [
                    "ROC_AUC",
                    "Balanced_Accuracy",
                ],
                ascending=False,
            )
            .reset_index(drop=True)
        )

        # ----------------------------------------------------
        # Best configuration
        # ----------------------------------------------------

        best_row = (
            model_results_df.iloc[0]
        )

        best_params = json.loads(
            best_row["Parameters"]
        )

        best_models[
            model_name
        ] = best_params

        print()
        print("=" * 80)
        print(
            f"BEST {model_name.upper()}"
        )
        print("=" * 80)

        print()
        print(
            json.dumps(
                best_params,
                indent=4,
            )
        )

        print()
        print(
            f"Validation ROC-AUC: "
            f"{best_row['ROC_AUC']:.4f}"
        )

        print(
            f"Validation Balanced Accuracy: "
            f"{best_row['Balanced_Accuracy']:.4f}"
        )

        print(
            f"Validation Macro F1: "
            f"{best_row['Macro_F1']:.4f}"
        )

        print(
            f"Validation LogLoss: "
            f"{best_row['LogLoss']:.4f}"
        )

        # ----------------------------------------------------
        # Save model-specific tuning results
        # ----------------------------------------------------

        safe_name = (
            model_name
            .lower()
            .replace(" ", "_")
        )

        model_results_df.to_csv(
            f"{OUTPUT_DIR}/"
            f"tuning_{safe_name}.csv",
            index=False,
        )

        all_results.append(
            model_results_df
        )

        print()
        print(
            f"{model_name} tuning time: "
            f"{time.time() - model_start:.1f}s"
        )

    # ========================================================
    # COMBINE RESULTS
    # ========================================================

    if all_results:

        all_results_df = pd.concat(
            all_results,
            ignore_index=True,
        )

        all_results_df = (
            all_results_df
            .sort_values(
                [
                    "ROC_AUC",
                    "Balanced_Accuracy",
                ],
                ascending=False,
            )
            .reset_index(drop=True)
        )

        all_results_df.to_csv(
            TUNING_RESULTS_PATH,
            index=False,
        )

    else:

        all_results_df = pd.DataFrame()

    # ========================================================
    # SAVE BEST HYPERPARAMETERS
    # ========================================================

    with open(
        BEST_PARAMS_PATH,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            best_models,
            f,
            indent=4,
        )

    # ========================================================
    # FINAL SUMMARY
    # ========================================================

    print()
    print("=" * 80)
    print("HYPERPARAMETER TUNING COMPLETE")
    print("=" * 80)

    print()
    print(
        f"Features used: {len(FEATURES)}"
    )

    print(
        "Sentiment enabled: YES"
    )

    print(
        "Test set used during tuning: NO"
    )

    print(
        "Split: 70% train / 15% validation"
    )

    print(
        f"Embargo: {EMBARGO_DAYS} days"
    )

    print()
    print(
        "Best hyperparameters:"
    )

    print(
        json.dumps(
            best_models,
            indent=4,
        )
    )

    print()
    print(
        f"Saved: {BEST_PARAMS_PATH}"
    )

    print(
        f"Saved: {TUNING_RESULTS_PATH}"
    )

    print()
    print(
        f"Total tuning time: "
        f"{time.time() - total_start:.1f}s"
    )