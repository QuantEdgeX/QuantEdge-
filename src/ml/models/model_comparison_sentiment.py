
"""
Compare nine models using chronological training and validation splits.

Experiments:
1. 33 technical features without sentiment (control).
2. 34 features including FinBERT sentiment (primary experiment).

Models:
- Random Forest
- CatBoost
- LightGBM
- XGBoost
- Logistic Regression
- Extra Trees
- Linear SVM
- HistGradientBoosting
- Balanced Random Forest

Validation only. The test set is never evaluated.
No production model artifacts or ensemble weights are changed.
"""

import json
import os
import warnings

import numpy as np
import pandas as pd

from sklearn.ensemble import (
    ExtraTreesClassifier,
    HistGradientBoostingClassifier,
)
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    roc_auc_score,
    log_loss,
    brier_score_loss,
)
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import LinearSVC

try:
    from imblearn.ensemble import BalancedRandomForestClassifier
except ImportError as exc:
    raise ImportError(
        "Balanced Random Forest requires imbalanced-learn. "
        "Install it using: pip install imbalanced-learn"
    ) from exc

from src.ml.models import final_evaluation_sentiment as base

warnings.filterwarnings("ignore")

OUTPUT_DIR = os.path.join(
    "src",
    "ml",
    "models",
    "final_results",
    "model_comparison_sentiment",
)

RANDOM_STATE = 42

TECHNICAL_FEATURES = base.FEATURES[:-1]
SENTIMENT_FEATURES = base.FEATURES


def build_candidate_models(params_json):
    """
    Keep the existing four tuned production candidates unchanged.
    Add five independent experimental candidates.
    """

    models = base.build_models(params_json)

    # Existing experimental models
    models["Logistic Regression"] = make_pipeline(
        StandardScaler(),
        LogisticRegression(
            C=0.1,
            max_iter=3000,
            class_weight="balanced",
            solver="lbfgs",
            random_state=RANDOM_STATE,
        ),
    )

    models["Extra Trees"] = ExtraTreesClassifier(
        n_estimators=500,
        max_features="sqrt",
        min_samples_leaf=2,
        class_weight="balanced",
        n_jobs=-1,
        random_state=RANDOM_STATE,
    )

    models["Linear SVM"] = make_pipeline(
        StandardScaler(),
        LinearSVC(
            C=0.1,
            class_weight="balanced",
            max_iter=15000,
            random_state=RANDOM_STATE,
        ),
    )

    # New model 1: Histogram-based Gradient Boosting
    models["HistGradientBoosting"] = HistGradientBoostingClassifier(
        learning_rate=0.05,
        max_iter=300,
        max_leaf_nodes=15,
        min_samples_leaf=30,
        l2_regularization=1.0,
        early_stopping=False,
        random_state=RANDOM_STATE,
    )

    # New model 2: Balanced Random Forest
    models["Balanced Random Forest"] = BalancedRandomForestClassifier(
        n_estimators=500,
        max_features="sqrt",
        min_samples_leaf=2,
        sampling_strategy="all",
        replacement=True,
        bootstrap=False,
        n_jobs=-1,
        random_state=RANDOM_STATE,
    )

    return models


def clean_features(dataframe, feature_columns):
    """
    Convert selected features to numeric arrays.
    Preserve the exact feature order.
    """

    return (
        dataframe[feature_columns]
        .replace([np.inf, -np.inf], np.nan)
        .fillna(0.0)
        .astype(float)
        .to_numpy()
    )


def evaluate_candidate(name, model, X_val, y_val):
    """
    Evaluate predictions using validation data only.

    Probability-based metrics are calculated only when the model
    provides native probabilities. No calibration is performed.
    """

    predicted = model.predict(X_val)

    if hasattr(model, "predict_proba"):
        score = model.predict_proba(X_val)[:, 1]
        score_type = "native_probability"

        try:
            ll = float(log_loss(y_val, score, labels=[0, 1]))
            brier = float(brier_score_loss(y_val, score))
        except ValueError:
            ll = None
            brier = None

    elif hasattr(model, "decision_function"):
        score = model.decision_function(X_val)
        score_type = "decision_function_score"
        ll = None
        brier = None

    else:
        raise TypeError(
            f"{name} provides neither predict_proba nor decision_function."
        )

    return {
        "model": name,
        "accuracy": float(accuracy_score(y_val, predicted)),
        "balanced_accuracy": float(
            balanced_accuracy_score(y_val, predicted)
        ),
        "macro_f1": float(
            f1_score(
                y_val,
                predicted,
                average="macro",
                zero_division=0,
            )
        ),
        "roc_auc": float(roc_auc_score(y_val, score)),
        "log_loss": ll,
        "brier_score": brier,
        "score_type": score_type,
    }


def main():

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 75)
    print("QUANTEDGE: NINE-MODEL VALIDATION COMPARISON")
    print("=" * 75)

    print("\nLoading dataset and chronological splits...")

    df = base.load_data()

    train_df, val_df, _test_df, _thresholds = base.build_splits(df)

    print(f"\nTraining rows: {len(train_df):,}")
    print(f"Validation rows: {len(val_df):,}")

    print("\nFeature sets:")
    print(f"Technical features: {len(TECHNICAL_FEATURES)}")
    print(f"Features including sentiment: {len(SENTIMENT_FEATURES)}")

    if "sentiment_score" not in SENTIMENT_FEATURES:
        raise ValueError(
            "sentiment_score is missing from the primary feature set."
        )

    if len(SENTIMENT_FEATURES) != 34:
        raise ValueError(
            f"Expected 34 features including sentiment, "
            f"but found {len(SENTIMENT_FEATURES)}."
        )

    # Prepare features
    X_train_33 = clean_features(train_df, TECHNICAL_FEATURES)
    X_val_33 = clean_features(val_df, TECHNICAL_FEATURES)

    X_train_34 = clean_features(train_df, SENTIMENT_FEATURES)
    X_val_34 = clean_features(val_df, SENTIMENT_FEATURES)

    y_train = train_df["Label"].astype(int).to_numpy()
    y_val = val_df["Label"].astype(int).to_numpy()

    if len(np.unique(y_train)) != 2:
        raise ValueError("Training data must contain both BUY and SELL.")

    if len(np.unique(y_val)) != 2:
        raise ValueError("Validation data must contain both BUY and SELL.")

    print("\nTraining class distribution:")
    print(pd.Series(y_train).value_counts().sort_index())

    print("\nValidation class distribution:")
    print(pd.Series(y_val).value_counts().sort_index())

    params_json = base.load_best_parameters()

    results = []

    experiments = [
        (
            "33_features_without_sentiment",
            X_train_33,
            X_val_33,
        ),
        (
            "34_features_with_sentiment",
            X_train_34,
            X_val_34,
        ),
    ]

    for feature_label, X_train, X_val in experiments:

        print("\n" + "=" * 75)
        print(f"EXPERIMENT: {feature_label}")
        print("=" * 75)

        candidates = build_candidate_models(params_json)

        for model_name, model in candidates.items():

            print(f"\nTraining {model_name}...")

            try:
                model.fit(X_train, y_train)

                metrics = evaluate_candidate(
                    model_name,
                    model,
                    X_val,
                    y_val,
                )

                metrics["feature_set"] = feature_label
                metrics["feature_count"] = X_train.shape[1]
                metrics["train_rows"] = len(y_train)
                metrics["validation_rows"] = len(y_val)

                results.append(metrics)

                print(
                    f"{model_name}: "
                    f"Balanced Accuracy="
                    f"{metrics['balanced_accuracy']:.4f}, "
                    f"Macro F1={metrics['macro_f1']:.4f}, "
                    f"ROC-AUC={metrics['roc_auc']:.4f}"
                )

            except Exception as exc:
                print(f"ERROR training {model_name}: {exc}")

                results.append({
                    "model": model_name,
                    "feature_set": feature_label,
                    "feature_count": X_train.shape[1],
                    "error": str(exc),
                })

    results_df = pd.DataFrame(results)

    successful = results_df[
        results_df["balanced_accuracy"].notna()
    ].copy()

    if successful.empty:
        raise RuntimeError("No models completed successfully.")

    successful = successful.sort_values(
        ["feature_set", "balanced_accuracy", "roc_auc"],
        ascending=[True, False, False],
    )

    csv_path = os.path.join(
        OUTPUT_DIR,
        "validation_model_comparison.csv",
    )

    json_path = os.path.join(
        OUTPUT_DIR,
        "validation_model_comparison.json",
    )

    successful.to_csv(csv_path, index=False)

    metadata = {
        "purpose": "Nine-model chronological validation comparison",
        "calibration": "none",
        "test_set_used": False,
        "production_artifacts_modified": False,
        "primary_experiment": "34_features_with_sentiment",
        "sentiment_feature": "sentiment_score",
        "feature_sets": {
            "33_features_without_sentiment": TECHNICAL_FEATURES,
            "34_features_with_sentiment": SENTIMENT_FEATURES,
        },
        "split": {
            "train_rows": int(len(train_df)),
            "validation_rows": int(len(val_df)),
            "train_date_min": str(train_df["Date"].min().date()),
            "train_date_max": str(train_df["Date"].max().date()),
            "validation_date_min": str(val_df["Date"].min().date()),
            "validation_date_max": str(val_df["Date"].max().date()),
            "embargo_days": base.EMBARGO_DAYS,
        },
        "results": successful.to_dict(orient="records"),
    }

    with open(json_path, "w", encoding="utf-8") as file:
        json.dump(metadata, file, indent=2, default=str)

    print("\n" + "=" * 75)
    print("VALIDATION COMPARISON COMPLETED")
    print("=" * 75)

    print("\nTop models for the 34-feature sentiment experiment:")

    sentiment_results = successful[
        successful["feature_set"] == "34_features_with_sentiment"
    ].sort_values(
        ["balanced_accuracy", "roc_auc"],
        ascending=False,
    )

    print(
        sentiment_results[
            [
                "model",
                "balanced_accuracy",
                "macro_f1",
                "roc_auc",
            ]
        ].to_string(index=False)
    )

    print("\nSaved:")
    print(csv_path)
    print(json_path)

    print("\nNo test-set metrics were calculated.")
    print("No production model artifacts were modified.")
    print("No ensemble weights or decision thresholds were changed.")


if __name__ == "__main__":
    main()
