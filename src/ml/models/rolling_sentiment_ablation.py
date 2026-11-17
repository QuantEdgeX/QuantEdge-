
"""
QuantEdge: Chronological Sentiment Ablation

Compares:
- 33 technical features
- 34 features including sentiment_score

Models:
- CatBoost
- LightGBM
- XGBoost

Uses the existing training split and divides the existing validation
period into three consecutive chronological windows.

The test set is never evaluated.
No production artifacts, weights, or thresholds are modified.
"""

import json
import os
import warnings

import numpy as np
import pandas as pd

from sklearn.metrics import (
    balanced_accuracy_score,
    f1_score,
    roc_auc_score,
)

from src.ml.models import final_evaluation_sentiment as base

warnings.filterwarnings("ignore")

RANDOM_STATE = 42
N_VALIDATION_WINDOWS = 3

OUTPUT_DIR = os.path.join(
    "src",
    "ml",
    "models",
    "final_results",
    "rolling_sentiment_ablation",
)

MODELS_TO_COMPARE = [
    "CatBoost",
    "LightGBM",
    "XGBoost",
]


def clean_features(dataframe, feature_columns):
    """Clean features while preserving their original order."""

    return (
        dataframe[feature_columns]
        .replace([np.inf, -np.inf], np.nan)
        .fillna(0.0)
        .astype(float)
        .to_numpy()
    )


def create_validation_windows(validation_df):
    """Divide validation dates into chronological windows."""

    validation_df = validation_df.copy()
    validation_df["Date"] = pd.to_datetime(validation_df["Date"])

    unique_dates = np.array(
        sorted(validation_df["Date"].dropna().unique())
    )

    if len(unique_dates) < N_VALIDATION_WINDOWS:
        raise ValueError(
            "Not enough validation dates to create three windows."
        )

    date_groups = np.array_split(
        unique_dates,
        N_VALIDATION_WINDOWS,
    )

    windows = []

    for index, dates in enumerate(date_groups, start=1):

        window_df = validation_df[
            validation_df["Date"].isin(dates)
        ].copy()

        if window_df.empty:
            raise ValueError(
                f"Validation window {index} is empty."
            )

        windows.append({
            "window": index,
            "data": window_df,
            "start_date": str(pd.Timestamp(dates[0]).date()),
            "end_date": str(pd.Timestamp(dates[-1]).date()),
        })

    return windows


def evaluate_model(model, X_val, y_val):

    predictions = model.predict(X_val)

    if not hasattr(model, "predict_proba"):
        raise TypeError(
            "Expected model to provide predict_proba."
        )

    probabilities = model.predict_proba(X_val)[:, 1]

    return {
        "balanced_accuracy": float(
            balanced_accuracy_score(y_val, predictions)
        ),
        "macro_f1": float(
            f1_score(
                y_val,
                predictions,
                average="macro",
                zero_division=0,
            )
        ),
        "roc_auc": float(
            roc_auc_score(y_val, probabilities)
        ),
    }


def main():

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 75)
    print("QUANTEDGE: ROLLING SENTIMENT ABLATION")
    print("=" * 75)

    # Load the same chronological splits used in previous experiments.
    print("\nLoading dataset and chronological splits...")

    df = base.load_data()

    train_df, val_df, _test_df, _thresholds = base.build_splits(df)

    train_df = train_df.copy()
    val_df = val_df.copy()

    train_df["Date"] = pd.to_datetime(train_df["Date"])
    val_df["Date"] = pd.to_datetime(val_df["Date"])

    # Define feature sets.
    features_33 = base.FEATURES[:-1]
    features_34 = base.FEATURES

    if len(features_33) != 33:
        raise ValueError(
            f"Expected 33 technical features, got {len(features_33)}."
        )

    if len(features_34) != 34:
        raise ValueError(
            f"Expected 34 total features, got {len(features_34)}."
        )

    if "sentiment_score" not in features_34:
        raise ValueError(
            "sentiment_score is missing from the 34-feature set."
        )

    print(f"\nTraining rows: {len(train_df):,}")
    print(f"Validation rows: {len(val_df):,}")

    print(
        f"Training dates: {train_df['Date'].min().date()} "
        f"to {train_df['Date'].max().date()}"
    )

    # Create three consecutive validation windows.
    windows = create_validation_windows(val_df)

    print("\nValidation windows:")

    for window in windows:
        print(
            f"Window {window['window']}: "
            f"{window['start_date']} to {window['end_date']} "
            f"({len(window['data']):,} rows)"
        )

    # Prepare training arrays.
    y_train = train_df["Label"].astype(int).to_numpy()

    X_train_33 = clean_features(train_df, features_33)
    X_train_34 = clean_features(train_df, features_34)

    if len(np.unique(y_train)) != 2:
        raise ValueError(
            "Training data must contain both BUY and SELL."
        )

    # Load existing tuned parameters.
    params_json = base.load_best_parameters()

    results = []

    feature_experiments = [
        {
            "feature_set": "33_features_without_sentiment",
            "features": features_33,
            "X_train": X_train_33,
        },
        {
            "feature_set": "34_features_with_sentiment",
            "features": features_34,
            "X_train": X_train_34,
        },
    ]

    # Train independently for each feature set and validation window.
    for window in windows:

        window_number = window["window"]
        window_df = window["data"]

        print("\n" + "=" * 75)
        print(f"VALIDATION WINDOW {window_number}")
        print("=" * 75)

        y_val = window_df["Label"].astype(int).to_numpy()

        if len(np.unique(y_val)) != 2:
            print(
                "Skipping window because it does not contain "
                "both BUY and SELL classes."
            )
            continue

        for experiment in feature_experiments:

            feature_set = experiment["feature_set"]
            features = experiment["features"]
            X_train = experiment["X_train"]

            X_val = clean_features(window_df, features)

            print(f"\nFeature set: {feature_set}")

            # Fresh model instances for this experiment.
            available_models = base.build_models(params_json)

            for model_name in MODELS_TO_COMPARE:

                if model_name not in available_models:
                    raise KeyError(
                        f"{model_name} not found. "
                        f"Available models: {list(available_models.keys())}"
                    )

                model = available_models[model_name]

                print(f"\nTraining {model_name}...")

                model.fit(X_train, y_train)

                metrics = evaluate_model(
                    model,
                    X_val,
                    y_val,
                )

                result = {
                    "window": window_number,
                    "window_start": window["start_date"],
                    "window_end": window["end_date"],
                    "model": model_name,
                    "feature_set": feature_set,
                    "feature_count": len(features),
                    "train_rows": len(y_train),
                    "validation_rows": len(y_val),
                    **metrics,
                }

                results.append(result)

                print(
                    f"Balanced Accuracy: "
                    f"{metrics['balanced_accuracy']:.4f} | "
                    f"Macro F1: {metrics['macro_f1']:.4f} | "
                    f"ROC-AUC: {metrics['roc_auc']:.4f}"
                )

    if not results:
        raise RuntimeError(
            "No validation experiments completed successfully."
        )

    results_df = pd.DataFrame(results)

    # Save individual validation-window results.
    results_path = os.path.join(
        OUTPUT_DIR,
        "rolling_sentiment_results.csv",
    )

    results_df.to_csv(results_path, index=False)

    # Calculate average and standard deviation across windows.
    summary = (
        results_df
        .groupby(["model", "feature_set"])
        .agg(
            mean_balanced_accuracy=(
                "balanced_accuracy", "mean"
            ),
            std_balanced_accuracy=(
                "balanced_accuracy", "std"
            ),
            mean_macro_f1=("macro_f1", "mean"),
            mean_roc_auc=("roc_auc", "mean"),
            windows_completed=("window", "nunique"),
        )
        .reset_index()
    )

    summary_path = os.path.join(
        OUTPUT_DIR,
        "rolling_sentiment_summary.csv",
    )

    summary.to_csv(summary_path, index=False)

    # Compare sentiment versus no sentiment for each model.
    comparison = summary.pivot(
        index="model",
        columns="feature_set",
        values="mean_balanced_accuracy",
    )

    no_sentiment = "33_features_without_sentiment"
    with_sentiment = "34_features_with_sentiment"

    if no_sentiment in comparison.columns and (
        with_sentiment in comparison.columns
    ):
        comparison["sentiment_balanced_accuracy_change"] = (
            comparison[with_sentiment]
            - comparison[no_sentiment]
        )

    comparison_path = os.path.join(
        OUTPUT_DIR,
        "sentiment_impact_comparison.csv",
    )

    comparison.to_csv(comparison_path)

    metadata = {
        "experiment": "Chronological sentiment ablation",
        "training_period": {
            "start": str(train_df["Date"].min().date()),
            "end": str(train_df["Date"].max().date()),
        },
        "validation_windows": [
            {
                "window": w["window"],
                "start": w["start_date"],
                "end": w["end_date"],
                "rows": len(w["data"]),
            }
            for w in windows
        ],
        "models": MODELS_TO_COMPARE,
        "feature_sets": {
            "33_features_without_sentiment": features_33,
            "34_features_with_sentiment": features_34,
        },
        "sentiment_feature": "sentiment_score",
        "test_set_used": False,
        "production_artifacts_modified": False,
        "ensemble_weights_changed": False,
        "decision_thresholds_changed": False,
        "results": results,
    }

    json_path = os.path.join(
        OUTPUT_DIR,
        "rolling_sentiment_metadata.json",
    )

    with open(json_path, "w", encoding="utf-8") as file:
        json.dump(metadata, file, indent=2, default=str)

    print("\n" + "=" * 75)
    print("ROLLING SENTIMENT ABLATION COMPLETED")
    print("=" * 75)

    print("\nAverage performance across validation windows:")

    print(
        summary.sort_values(
            ["model", "feature_set"]
        ).to_string(index=False)
    )

    print("\nSentiment impact on balanced accuracy:")

    print(comparison.to_string())

    print("\nSaved:")
    print(results_path)
    print(summary_path)
    print(comparison_path)
    print(json_path)

    print("\nTest set was not evaluated.")
    print("Production artifacts were not modified.")
    print("Ensemble weights and thresholds were not changed.")


if __name__ == "__main__":
    main()
