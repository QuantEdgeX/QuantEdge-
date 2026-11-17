import os
import json
import joblib
import numpy as np
import pandas as pd

from lightgbm import Booster
from catboost import CatBoostClassifier

from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    log_loss,
    roc_auc_score,
    classification_report,
    confusion_matrix,
)

from src.ml.common.prepare_data import prepare_data


# ============================================================
# PATHS
# ============================================================

LIGHTGBM_PATH = "src/ml/saved_models/lightgbm/lightgbm_model.txt"
CATBOOST_PATH = "src/ml/saved_models/catboost/catboost_model.cbm"
RANDOM_FOREST_PATH = (
    "src/ml/saved_models/random_forest/random_forest_model.pkl"
)

OUTPUT_DIR = "src/ml/saved_models/ensemble"

os.makedirs(OUTPUT_DIR, exist_ok=True)

VALIDATION_RESULTS_PATH = os.path.join(
    OUTPUT_DIR,
    "validation_results.csv",
)

TEST_RESULTS_PATH = os.path.join(
    OUTPUT_DIR,
    "test_results.csv",
)

METRICS_PATH = os.path.join(
    OUTPUT_DIR,
    "metrics.json",
)


# ============================================================
# LOAD MODELS
# ============================================================

def load_models():

    print("\n" + "=" * 60)
    print("LOADING TRAINED MODELS")
    print("=" * 60)

    print("Loading LightGBM...")
    lightgbm_model = Booster(
        model_file=LIGHTGBM_PATH
    )

    print("Loading CatBoost...")
    catboost_model = CatBoostClassifier()
    catboost_model.load_model(
        CATBOOST_PATH
    )

    print("Loading Random Forest...")
    random_forest_model = joblib.load(
        RANDOM_FOREST_PATH
    )

    print("All models loaded successfully.")

    return (
        lightgbm_model,
        catboost_model,
        random_forest_model,
    )


# ============================================================
# GET MODEL PROBABILITIES
# ============================================================

def get_model_probabilities(
    X,
    lightgbm_model,
    catboost_model,
    random_forest_model,
):

    # LightGBM
    lgbm_buy = lightgbm_model.predict(X)

    # CatBoost
    catboost_buy = (
        catboost_model.predict_proba(X)[:, 1]
    )

    # Random Forest
    rf_buy = (
        random_forest_model.predict_proba(X)[:, 1]
    )

    return (
        lgbm_buy,
        catboost_buy,
        rf_buy,
    )


# ============================================================
# CALCULATE ENSEMBLE
# ============================================================

def calculate_ensemble(
    lgbm_buy,
    catboost_buy,
    rf_buy,
):

    # Equal-weight ensemble
    ensemble_buy = (
        lgbm_buy
        + catboost_buy
        + rf_buy
    ) / 3.0

    ensemble_sell = 1.0 - ensemble_buy

    # Distance from 50/50
    spread = np.abs(
        ensemble_buy - ensemble_sell
    )

    return (
        ensemble_buy,
        ensemble_sell,
        spread,
    )


# ============================================================
# EVALUATE ENSEMBLE
# ============================================================

def evaluate_ensemble(
    y_true,
    ensemble_buy,
    dataset_name,
):

    predictions = (
        ensemble_buy >= 0.50
    ).astype(int)

    metrics = {
        "accuracy": float(
            accuracy_score(
                y_true,
                predictions,
            )
        ),
        "balanced_accuracy": float(
            balanced_accuracy_score(
                y_true,
                predictions,
            )
        ),
        "macro_f1": float(
            f1_score(
                y_true,
                predictions,
                average="macro",
            )
        ),
        "log_loss": float(
            log_loss(
                y_true,
                ensemble_buy,
            )
        ),
        "roc_auc": float(
            roc_auc_score(
                y_true,
                ensemble_buy,
            )
        ),
    }

    print("\n" + "=" * 60)
    print(
        f"{dataset_name.upper()} ENSEMBLE EVALUATION"
    )
    print("=" * 60)

    print(
        f"Accuracy:           "
        f"{metrics['accuracy']:.4f}"
    )

    print(
        f"Balanced Accuracy:  "
        f"{metrics['balanced_accuracy']:.4f}"
    )

    print(
        f"Macro F1:           "
        f"{metrics['macro_f1']:.4f}"
    )

    print(
        f"Log Loss:           "
        f"{metrics['log_loss']:.4f}"
    )

    print(
        f"ROC-AUC:            "
        f"{metrics['roc_auc']:.4f}"
    )

    print("\nClassification Report:")

    print(
        classification_report(
            y_true,
            predictions,
            target_names=[
                "SELL",
                "BUY",
            ],
        )
    )

    print("Confusion Matrix:")

    print(
        confusion_matrix(
            y_true,
            predictions,
        )
    )

    return metrics


# ============================================================
# BUILD RESULT DATAFRAME
# ============================================================

def build_results(
    df,
    y_true,
    lgbm_buy,
    catboost_buy,
    rf_buy,
    ensemble_buy,
    ensemble_sell,
    spread,
):

    results = df[
        [
            "Date",
            "Ticker",
            "Future_Return",
        ]
    ].copy()

    results["Actual_Label"] = y_true

    results["LightGBM_BUY"] = lgbm_buy

    results["CatBoost_BUY"] = catboost_buy

    results["RandomForest_BUY"] = rf_buy

    results["Ensemble_BUY"] = ensemble_buy

    results["Ensemble_SELL"] = ensemble_sell

    results["Spread"] = spread

    results["Predicted_Label"] = (
        ensemble_buy >= 0.50
    ).astype(int)

    return results


# ============================================================
# MAIN
# ============================================================

def main():

    # --------------------------------------------------------
    # LOAD DATA
    # --------------------------------------------------------

    print("\n" + "=" * 60)
    print("LOADING PREPARED DATA")
    print("=" * 60)

    data = prepare_data()

    X_val = data["X_val"]
    y_val = data["y_val"]

    X_test = data["X_test"]
    y_test = data["y_test"]

    val_df = data["val_df"]
    test_df = data["test_df"]

    print(
        f"\nValidation samples: {len(X_val)}"
    )

    print(
        f"Test samples:       {len(X_test)}"
    )

    # --------------------------------------------------------
    # LOAD MODELS
    # --------------------------------------------------------

    (
        lightgbm_model,
        catboost_model,
        random_forest_model,
    ) = load_models()

    # ========================================================
    # VALIDATION
    # ========================================================

    print("\n" + "=" * 60)
    print("GENERATING VALIDATION PREDICTIONS")
    print("=" * 60)

    (
        lgbm_val,
        catboost_val,
        rf_val,
    ) = get_model_probabilities(
        X_val,
        lightgbm_model,
        catboost_model,
        random_forest_model,
    )

    (
        ensemble_val_buy,
        ensemble_val_sell,
        ensemble_val_spread,
    ) = calculate_ensemble(
        lgbm_val,
        catboost_val,
        rf_val,
    )

    val_metrics = evaluate_ensemble(
        y_val,
        ensemble_val_buy,
        "validation",
    )

    # Save validation results
    validation_results = build_results(
        val_df,
        y_val,
        lgbm_val,
        catboost_val,
        rf_val,
        ensemble_val_buy,
        ensemble_val_sell,
        ensemble_val_spread,
    )

    validation_results.to_csv(
        VALIDATION_RESULTS_PATH,
        index=False,
    )

    # ========================================================
    # TEST
    # ========================================================

    print("\n" + "=" * 60)
    print("GENERATING TEST PREDICTIONS")
    print("=" * 60)

    (
        lgbm_test,
        catboost_test,
        rf_test,
    ) = get_model_probabilities(
        X_test,
        lightgbm_model,
        catboost_model,
        random_forest_model,
    )

    (
        ensemble_test_buy,
        ensemble_test_sell,
        ensemble_test_spread,
    ) = calculate_ensemble(
        lgbm_test,
        catboost_test,
        rf_test,
    )

    test_metrics = evaluate_ensemble(
        y_test,
        ensemble_test_buy,
        "test",
    )

    # Save test results
    test_results = build_results(
        test_df,
        y_test,
        lgbm_test,
        catboost_test,
        rf_test,
        ensemble_test_buy,
        ensemble_test_sell,
        ensemble_test_spread,
    )

    test_results.to_csv(
        TEST_RESULTS_PATH,
        index=False,
    )

    # ========================================================
    # SAVE METRICS
    # ========================================================

    all_metrics = {
        "validation": val_metrics,
        "test": test_metrics,
        "ensemble_method": "equal_weight_average",
        "models": [
            "LightGBM",
            "CatBoost",
            "RandomForest",
        ],
    }

    with open(
        METRICS_PATH,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            all_metrics,
            f,
            indent=4,
        )

    # ========================================================
    # SAMPLE VALIDATION RESULTS
    # ========================================================

    print("\n" + "=" * 60)
    print("SAMPLE VALIDATION PREDICTIONS")
    print("=" * 60)

    print(
        validation_results[
            [
                "Ticker",
                "LightGBM_BUY",
                "CatBoost_BUY",
                "RandomForest_BUY",
                "Ensemble_BUY",
                "Ensemble_SELL",
                "Spread",
            ]
        ]
        .head(10)
        .to_string(index=False)
    )

    # ========================================================
    # SAMPLE TEST RESULTS
    # ========================================================

    print("\n" + "=" * 60)
    print("SAMPLE TEST PREDICTIONS")
    print("=" * 60)

    print(
        test_results[
            [
                "Ticker",
                "LightGBM_BUY",
                "CatBoost_BUY",
                "RandomForest_BUY",
                "Ensemble_BUY",
                "Ensemble_SELL",
                "Spread",
            ]
        ]
        .head(10)
        .to_string(index=False)
    )

    # ========================================================
    # SAVE COMPLETE
    # ========================================================

    print("\n" + "=" * 60)
    print("ENSEMBLE OUTPUTS SAVED")
    print("=" * 60)

    print(
        f"Validation: {VALIDATION_RESULTS_PATH}"
    )

    print(
        f"Test:       {TEST_RESULTS_PATH}"
    )

    print(
        f"Metrics:    {METRICS_PATH}"
    )


if __name__ == "__main__":
    main()