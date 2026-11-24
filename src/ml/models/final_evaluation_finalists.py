
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from catboost import CatBoostClassifier
from lightgbm import LGBMClassifier

from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    roc_auc_score,
    confusion_matrix,
)


# =========================================================
# PROJECT IMPORTS
# =========================================================

PROJECT_ROOT = Path(__file__).resolve().parents[3]

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.ml.models import final_evaluation_sentiment as base


# =========================================================
# CONFIGURATION
# =========================================================

RANDOM_STATE = 42

MODEL_NAMES = [
    "CatBoost",
    "LightGBM",
]

FEATURE_COLUMNS = list(base.FEATURES)

OUTPUT_DIR = (
    Path(__file__).resolve().parent
    / "final_results"
    / "finalist_test_evaluation"
)

OUTPUT_DIR.mkdir(
    parents=True,
    exist_ok=True,
)

PARAMETERS_PATH = (
    Path(__file__).resolve().parent
    / "final_results"
    / "hyperparameter_optimization"
    / "best_parameters.json"
)


# =========================================================
# LOAD FROZEN PARAMETERS
# =========================================================

def load_parameters():

    if not PARAMETERS_PATH.exists():
        raise FileNotFoundError(
            f"Parameter file not found: {PARAMETERS_PATH}"
        )

    with open(
        PARAMETERS_PATH,
        "r",
        encoding="utf-8",
    ) as file:

        parameters = json.load(file)

    for model_name in MODEL_NAMES:

        if model_name not in parameters:
            raise KeyError(
                f"Missing parameters for {model_name}"
            )

    return parameters


# =========================================================
# BUILD FINALIST MODELS
# =========================================================

def build_finalists(parameters):

    models = {}

    # -----------------------------------------------------
    # CatBoost
    # -----------------------------------------------------

    cat_params = parameters["CatBoost"].copy()

    models["CatBoost"] = CatBoostClassifier(
        **cat_params,
        loss_function="Logloss",
        eval_metric="AUC",
        random_seed=RANDOM_STATE,
        verbose=False,
        allow_writing_files=False,
        thread_count=-1,
    )

    # -----------------------------------------------------
    # LightGBM
    # -----------------------------------------------------

    lgb_params = parameters["LightGBM"].copy()

    models["LightGBM"] = LGBMClassifier(
        **lgb_params,
        objective="binary",
        random_state=RANDOM_STATE,
        n_jobs=-1,
        verbosity=-1,
        subsample_freq=1,
    )

    return models


# =========================================================
# CALCULATE METRICS
# =========================================================

def calculate_metrics(y_true, predictions, probabilities):

    y_true = np.asarray(y_true)
    predictions = np.asarray(predictions).reshape(-1)
    probabilities = np.asarray(probabilities).reshape(-1)

    has_both_classes = len(np.unique(y_true)) == 2

    return {
        "rows": len(y_true),

        "accuracy": accuracy_score(
            y_true,
            predictions,
        ),

        "balanced_accuracy": (
            balanced_accuracy_score(
                y_true,
                predictions,
            )
            if has_both_classes
            else np.nan
        ),

        "macro_precision": precision_score(
            y_true,
            predictions,
            labels=[0, 1],
            average="macro",
            zero_division=0,
        ),

        "macro_recall": recall_score(
            y_true,
            predictions,
            labels=[0, 1],
            average="macro",
            zero_division=0,
        ),

        "macro_f1": f1_score(
            y_true,
            predictions,
            labels=[0, 1],
            average="macro",
            zero_division=0,
        ),

        "roc_auc": (
            roc_auc_score(
                y_true,
                probabilities,
            )
            if has_both_classes
            else np.nan
        ),
    }


# =========================================================
# EVALUATE ONE MODEL
# =========================================================

def evaluate_model(
    model_name,
    model,
    train_df,
    test_df,
):

    print("\n" + "=" * 80)
    print(f"FINAL TEST EVALUATION: {model_name.upper()}")
    print("=" * 80)

    X_train = train_df[FEATURE_COLUMNS]
    y_train = train_df["Label"]

    X_test = test_df[FEATURE_COLUMNS]
    y_test = test_df["Label"]

    print(f"Training rows: {len(X_train):,}")
    print(f"Test rows: {len(X_test):,}")

    # -----------------------------------------------------
    # Train on combined training and validation data
    # -----------------------------------------------------

    print("\nTraining model...")

    model.fit(
        X_train,
        y_train,
    )

    print("Training completed.")

    # -----------------------------------------------------
    # Predict untouched test data
    # -----------------------------------------------------

    print("\nGenerating test predictions...")

    predictions = np.asarray(
        model.predict(X_test)
    ).reshape(-1)

    probabilities = model.predict_proba(
        X_test
    )[:, 1]

    # -----------------------------------------------------
    # Overall metrics
    # -----------------------------------------------------

    overall_metrics = calculate_metrics(
        y_test,
        predictions,
        probabilities,
    )

    overall_metrics["model"] = model_name

    # -----------------------------------------------------
    # Confusion matrix
    # -----------------------------------------------------

    cm = confusion_matrix(
        y_test,
        predictions,
        labels=[0, 1],
    )

    confusion_df = pd.DataFrame(
        cm,
        index=["Actual_SELL", "Actual_BUY"],
        columns=["Predicted_SELL", "Predicted_BUY"],
    )

    confusion_df.to_csv(
        OUTPUT_DIR / f"{model_name.lower()}_confusion_matrix.csv"
    )

    # -----------------------------------------------------
    # Prediction records
    # -----------------------------------------------------

    prediction_df = test_df[
        ["Date", "Ticker", "Label"]
    ].copy()

    prediction_df["Prediction"] = predictions

    prediction_df["BUY_Probability"] = probabilities

    prediction_df["Model"] = model_name

    # -----------------------------------------------------
    # Ticker-wise metrics
    # -----------------------------------------------------

    ticker_results = []

    for ticker, ticker_df in prediction_df.groupby("Ticker"):

        ticker_metrics = calculate_metrics(
            ticker_df["Label"],
            ticker_df["Prediction"],
            ticker_df["BUY_Probability"],
        )

        ticker_metrics["ticker"] = ticker
        ticker_metrics["model"] = model_name

        ticker_results.append(
            ticker_metrics
        )

    ticker_results_df = pd.DataFrame(
        ticker_results
    )

    # -----------------------------------------------------
    # Display results
    # -----------------------------------------------------

    print("\nOVERALL TEST RESULTS")

    for metric, value in overall_metrics.items():

        if metric in ["model", "rows"]:
            print(f"{metric}: {value}")
        elif pd.notna(value):
            print(f"{metric}: {value:.5f}")
        else:
            print(f"{metric}: N/A")

    print("\nCONFUSION MATRIX")

    print(confusion_df)

    print("\nTICKER-WISE RESULTS")

    print(
        ticker_results_df[
            [
                "ticker",
                "rows",
                "balanced_accuracy",
                "macro_f1",
                "roc_auc",
            ]
        ].to_string(
            index=False,
            float_format=lambda x: f"{x:.5f}",
        )
    )

    return (
        overall_metrics,
        ticker_results_df,
        prediction_df,
    )


# =========================================================
# MAIN
# =========================================================

def main():

    print("=" * 80)
    print("QUANTEDGE: FINAL CATBOOST VS LIGHTGBM EVALUATION")
    print("=" * 80)

    # -----------------------------------------------------
    # Verify features
    # -----------------------------------------------------

    if len(FEATURE_COLUMNS) != 34:
        raise ValueError(
            f"Expected 34 features, found {len(FEATURE_COLUMNS)}."
        )

    if "sentiment_score" not in FEATURE_COLUMNS:
        raise ValueError(
            "sentiment_score is missing."
        )

    if "Future_Return" in FEATURE_COLUMNS:
        raise ValueError(
            "Future_Return must never be used as a model feature."
        )

    print("\nFeatures:", len(FEATURE_COLUMNS))
    print("Sentiment: INCLUDED")
    print("Models: CatBoost and LightGBM only")

    # -----------------------------------------------------
    # Load parameters
    # -----------------------------------------------------

    parameters = load_parameters()

    print("\nFrozen parameters loaded successfully.")

    # -----------------------------------------------------
    # Load dataset
    # -----------------------------------------------------

    df = base.load_data()

    # -----------------------------------------------------
    # Recreate original chronological splits
    # -----------------------------------------------------

    (
        train_df,
        validation_df,
        test_df,
        thresholds_df,
    ) = base.build_splits(df)

    # -----------------------------------------------------
    # Combine training and validation data
    # -----------------------------------------------------

    train_final = pd.concat(
        [
            train_df,
            validation_df,
        ],
        ignore_index=True,
    )

    train_final = train_final.sort_values(
        ["Ticker", "Date"]
    ).reset_index(drop=True)

    print("\nFINAL TRAINING CONFIGURATION")

    print(f"Original training rows: {len(train_df):,}")
    print(f"Validation rows: {len(validation_df):,}")
    print(f"Combined training rows: {len(train_final):,}")
    print(f"Untouched test rows: {len(test_df):,}")

    print(
        f"\nTest date range: "
        f"{test_df['Date'].min().date()} "
        f"to "
        f"{test_df['Date'].max().date()}"
    )

    # -----------------------------------------------------
    # Validate labels and features
    # -----------------------------------------------------

    for name, part in [
        ("Training", train_final),
        ("Test", test_df),
    ]:

        if part[FEATURE_COLUMNS].select_dtypes(
            exclude=[np.number]
        ).shape[1] > 0:

            raise ValueError(
                f"{name} data contains non-numeric features."
            )

        if part[FEATURE_COLUMNS].isin(
            [np.inf, -np.inf]
        ).any().any():

            raise ValueError(
                f"{name} data contains infinite feature values."
            )

        if not set(part["Label"].unique()).issubset({0, 1}):
            raise ValueError(
                f"{name} data contains unexpected labels."
            )

    # -----------------------------------------------------
    # Save thresholds for reproducibility
    # -----------------------------------------------------

    thresholds_df.to_csv(
        OUTPUT_DIR / "ticker_thresholds.csv",
        index=False,
    )

    # -----------------------------------------------------
    # Build finalist models
    # -----------------------------------------------------

    models = build_finalists(
        parameters
    )

    all_overall_results = []
    all_ticker_results = []
    all_predictions = []

    # -----------------------------------------------------
    # Evaluate CatBoost and LightGBM
    # -----------------------------------------------------

    for model_name in MODEL_NAMES:

        (
            overall_metrics,
            ticker_metrics,
            predictions,
        ) = evaluate_model(
            model_name=model_name,
            model=models[model_name],
            train_df=train_final,
            test_df=test_df,
        )

        all_overall_results.append(
            overall_metrics
        )

        all_ticker_results.append(
            ticker_metrics
        )

        all_predictions.append(
            predictions
        )

    # -----------------------------------------------------
    # Save final results
    # -----------------------------------------------------

    overall_df = pd.DataFrame(
        all_overall_results
    )

    overall_df.to_csv(
        OUTPUT_DIR / "overall_test_results.csv",
        index=False,
    )

    ticker_df = pd.concat(
        all_ticker_results,
        ignore_index=True,
    )

    ticker_df.to_csv(
        OUTPUT_DIR / "ticker_wise_test_results.csv",
        index=False,
    )

    predictions_df = pd.concat(
        all_predictions,
        ignore_index=True,
    )

    predictions_df.to_csv(
        OUTPUT_DIR / "test_predictions.csv",
        index=False,
    )

    # -----------------------------------------------------
    # Final comparison
    # -----------------------------------------------------

    print("\n" + "=" * 80)
    print("FINAL TEST COMPARISON")
    print("=" * 80)

    print(
        overall_df[
            [
                "model",
                "accuracy",
                "balanced_accuracy",
                "macro_precision",
                "macro_recall",
                "macro_f1",
                "roc_auc",
            ]
        ].to_string(
            index=False,
            float_format=lambda x: f"{x:.5f}",
        )
    )

    print("\nRESULTS SAVED TO:")
    print(OUTPUT_DIR)

    print("\nTest evaluation completed.")
    print("No production models were modified.")


if __name__ == "__main__":
    main()
