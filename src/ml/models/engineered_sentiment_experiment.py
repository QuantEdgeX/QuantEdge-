
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    f1_score,
    roc_auc_score,
)

# ---------------------------------------------------------
# PROJECT IMPORTS
# ---------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parents[3]

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from src.ml.models import final_evaluation_sentiment as base


# ---------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------

RANDOM_STATE = 42

OUTPUT_DIR = (
    Path(__file__).resolve().parent
    / "final_results"
    / "engineered_sentiment_experiment"
)

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

NEW_SENTIMENT_FEATURES = [
    "sentiment_ma_3",
    "sentiment_ma_5",
    "sentiment_change_1d",
    "sentiment_change_5d",
    "sentiment_volatility_5d",
]

MODELS_TO_COMPARE = [
    "CatBoost",
    "LightGBM",
    "XGBoost",
]


# ---------------------------------------------------------
# IDENTIFY DATA COLUMNS
# ---------------------------------------------------------

def find_column(df, candidates, description):
    for candidate in candidates:
        if candidate in df.columns:
            return candidate

    raise ValueError(
        f"Could not identify {description} column. "
        f"Available columns: {list(df.columns)}"
    )


# ---------------------------------------------------------
# CREATE ENGINEERED SENTIMENT FEATURES
# ---------------------------------------------------------

def add_sentiment_features(df):
    df = df.copy()

    date_col = find_column(
        df,
        ["Date", "date"],
        "date",
    )

    ticker_col = find_column(
        df,
        ["Ticker", "ticker", "Symbol", "symbol"],
        "ticker",
    )

    if "sentiment_score" not in df.columns:
        raise ValueError(
            "sentiment_score is missing from the dataset."
        )

    df[date_col] = pd.to_datetime(
        df[date_col],
        errors="coerce",
    )

    df["sentiment_score"] = pd.to_numeric(
        df["sentiment_score"],
        errors="coerce",
    )

    df = df.sort_values(
        [ticker_col, date_col]
    ).reset_index(drop=True)

    grouped = df.groupby(
        ticker_col,
        sort=False,
    )["sentiment_score"]

    # Rolling averages, including the current observation.
    df["sentiment_ma_3"] = grouped.transform(
        lambda s: s.rolling(
            window=3,
            min_periods=1,
        ).mean()
    )

    df["sentiment_ma_5"] = grouped.transform(
        lambda s: s.rolling(
            window=5,
            min_periods=1,
        ).mean()
    )

    # Sentiment momentum.
    df["sentiment_change_1d"] = grouped.diff(1)

    df["sentiment_change_5d"] = grouped.diff(5)

    # Rolling sentiment volatility.
    df["sentiment_volatility_5d"] = grouped.transform(
        lambda s: s.rolling(
            window=5,
            min_periods=2,
        ).std()
    )

    # Preserve the original chronological ordering.
    return df.sort_values(
        [date_col, ticker_col]
    ).reset_index(drop=True)


# ---------------------------------------------------------
# VALIDATION WINDOWS
# ---------------------------------------------------------

def create_validation_windows(validation_df):
    date_col = find_column(
        validation_df,
        ["Date", "date"],
        "date",
    )

    validation_df = validation_df.sort_values(
        date_col
    ).reset_index(drop=True)

    windows = np.array_split(
        np.arange(len(validation_df)),
        3,
    )

    results = []

    for index, window_indices in enumerate(windows, start=1):
        if len(window_indices) == 0:
            continue

        window = validation_df.iloc[
            window_indices
        ].copy()

        results.append(
            (f"Window_{index}", window)
        )

    return results


# ---------------------------------------------------------
# MODEL EVALUATION
# ---------------------------------------------------------

def evaluate_predictions(y_true, predictions, probabilities):
    return {
        "accuracy": accuracy_score(
            y_true,
            predictions,
        ),
        "balanced_accuracy": balanced_accuracy_score(
            y_true,
            predictions,
        ),
        "macro_f1": f1_score(
            y_true,
            predictions,
            average="macro",
        ),
        "roc_auc": roc_auc_score(
            y_true,
            probabilities,
        ),
    }


# ---------------------------------------------------------
# TRAIN AND EVALUATE
# ---------------------------------------------------------

def run_experiment(
    train_df,
    validation_df,
    feature_columns,
    feature_set_name,
    params_json,
):
    print("\n" + "=" * 75)
    print(f"FEATURE SET: {feature_set_name}")
    print(f"NUMBER OF FEATURES: {len(feature_columns)}")
    print("=" * 75)

    X_train = train_df[feature_columns]
    y_train = train_df["Label"]

    validation_windows = create_validation_windows(
        validation_df
    )

    models = base.build_models(params_json)

    all_results = []

    for model_name in MODELS_TO_COMPARE:
        if model_name not in models:
            print(
                f"Skipping {model_name}: "
                "not returned by build_models()."
            )
            continue

        print(f"\nTraining {model_name}...")

        model = models[model_name]

        model.fit(
            X_train,
            y_train,
        )

        for window_name, window_df in validation_windows:
            X_val = window_df[feature_columns]
            y_val = window_df["Label"]

            predictions = model.predict(X_val)

            if hasattr(model, "predict_proba"):
                probabilities = model.predict_proba(
                    X_val
                )[:, 1]
            else:
                raise ValueError(
                    f"{model_name} does not support predict_proba."
                )

            metrics = evaluate_predictions(
                y_val,
                predictions,
                probabilities,
            )

            result = {
                "feature_set": feature_set_name,
                "model": model_name,
                "window": window_name,
                "rows": len(window_df),
                **metrics,
            }

            all_results.append(result)

            print(
                f"{window_name}: "
                f"BA={metrics['balanced_accuracy']:.4f}, "
                f"F1={metrics['macro_f1']:.4f}, "
                f"AUC={metrics['roc_auc']:.4f}"
            )

    return all_results


# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------

def main():
    print("=" * 75)
    print("QUANTEDGE: ENGINEERED SENTIMENT EXPERIMENT")
    print("=" * 75)

    # Load the original dataset.
    df = base.load_data()

    # Add the five engineered sentiment features.
    df = add_sentiment_features(df)

    # Use the existing chronological split logic.
    train_df, validation_df, test_df = base.build_splits(df)

    print("\nDataset split:")
    print(f"Training rows:   {len(train_df):,}")
    print(f"Validation rows: {len(validation_df):,}")
    print(f"Test rows:       {len(test_df):,}")

    # Verify that all engineered features exist.
    missing_features = [
        feature
        for feature in NEW_SENTIMENT_FEATURES
        if feature not in df.columns
    ]

    if missing_features:
        raise ValueError(
            f"Missing engineered features: {missing_features}"
        )

    # Existing 34-feature configuration.
    original_features = list(base.FEATURES)

    # New 39-feature configuration.
    engineered_features = (
        original_features + NEW_SENTIMENT_FEATURES
    )

    if len(original_features) != 34:
        raise ValueError(
            f"Expected 34 original features, "
            f"but found {len(original_features)}."
        )

    if len(engineered_features) != 39:
        raise ValueError(
            f"Expected 39 engineered features, "
            f"but found {len(engineered_features)}."
        )

    # Check that all feature columns exist.
    for feature in engineered_features:
        if feature not in train_df.columns:
            raise ValueError(
                f"Feature {feature} missing from training data."
            )

    params_json = base.load_best_parameters()

    # Experiment A: Existing 34 features.
    results_34 = run_experiment(
        train_df=train_df,
        validation_df=validation_df,
        feature_columns=original_features,
        feature_set_name="Original_34",
        params_json=params_json,
    )

    # Experiment B: 34 original + 5 engineered features.
    results_39 = run_experiment(
        train_df=train_df,
        validation_df=validation_df,
        feature_columns=engineered_features,
        feature_set_name="Engineered_39",
        params_json=params_json,
    )

    all_results = results_34 + results_39

    results_df = pd.DataFrame(all_results)

    # Save individual validation-window results.
    results_df.to_csv(
        OUTPUT_DIR / "validation_results.csv",
        index=False,
    )

    # Calculate average validation performance.
    summary_df = (
        results_df
        .groupby(
            ["feature_set", "model"],
            as_index=False,
        )
        .agg(
            balanced_accuracy_mean=(
                "balanced_accuracy",
                "mean",
            ),
            balanced_accuracy_std=(
                "balanced_accuracy",
                "std",
            ),
            macro_f1_mean=(
                "macro_f1",
                "mean",
            ),
            roc_auc_mean=(
                "roc_auc",
                "mean",
            ),
        )
    )

    summary_df.to_csv(
        OUTPUT_DIR / "validation_summary.csv",
        index=False,
    )

    print("\n" + "=" * 75)
    print("FINAL VALIDATION SUMMARY")
    print("=" * 75)

    print(
        summary_df.to_string(
            index=False,
            float_format=lambda x: f"{x:.5f}",
        )
    )

    print("\nFiles saved to:")
    print(OUTPUT_DIR)

    print("\nTest set was not evaluated.")
    print("No production models or ensemble weights were modified.")


if __name__ == "__main__":
    main()
