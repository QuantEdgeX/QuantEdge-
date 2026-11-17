
"""
QuantEdge: Permutation Feature Importance

Models:
- CatBoost
- LightGBM
- XGBoost

Uses:
- 34 features, including sentiment_score
- Chronological training and validation splits
- Validation-only permutation importance

Does not:
- Evaluate the test set
- Perform calibration
- Modify production artifacts, ensemble weights, or thresholds
"""

import json
import os
import warnings

import numpy as np
import pandas as pd

from sklearn.inspection import permutation_importance
from sklearn.metrics import balanced_accuracy_score

from src.ml.models import final_evaluation_sentiment as base

warnings.filterwarnings("ignore")

RANDOM_STATE = 42
N_REPEATS = 10

OUTPUT_DIR = os.path.join(
    "src",
    "ml",
    "models",
    "final_results",
    "feature_importance_sentiment",
)


def clean_features(dataframe, feature_columns):
    """Preserve feature order and clean numeric values."""

    return (
        dataframe[feature_columns]
        .replace([np.inf, -np.inf], np.nan)
        .fillna(0.0)
        .astype(float)
        .to_numpy()
    )


def main():

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 75)
    print("QUANTEDGE: PERMUTATION FEATURE IMPORTANCE")
    print("=" * 75)

    # Load data and chronological splits.
    print("\nLoading dataset and chronological splits...")

    df = base.load_data()

    train_df, val_df, _test_df, _thresholds = base.build_splits(df)

    features = base.FEATURES

    if len(features) != 34:
        raise ValueError(
            f"Expected 34 features, but found {len(features)}."
        )

    if "sentiment_score" not in features:
        raise ValueError(
            "sentiment_score is missing from the feature set."
        )

    print(f"Training rows: {len(train_df):,}")
    print(f"Validation rows: {len(val_df):,}")
    print(f"Feature count: {len(features)}")

    print(
        f"Training dates: {train_df['Date'].min().date()} "
        f"to {train_df['Date'].max().date()}"
    )

    print(
        f"Validation dates: {val_df['Date'].min().date()} "
        f"to {val_df['Date'].max().date()}"
    )

    # Prepare training and validation data.
    X_train = clean_features(train_df, features)
    X_val = clean_features(val_df, features)

    y_train = train_df["Label"].astype(int).to_numpy()
    y_val = val_df["Label"].astype(int).to_numpy()

    if len(np.unique(y_train)) != 2:
        raise ValueError("Training data must contain both classes.")

    if len(np.unique(y_val)) != 2:
        raise ValueError("Validation data must contain both classes.")

    # Load the existing tuned model configurations.
    params_json = base.load_best_parameters()
    all_models = base.build_models(params_json)

    selected_names = [
        "CatBoost",
        "LightGBM",
        "XGBoost",
    ]

    missing = [
        name for name in selected_names
        if name not in all_models
    ]

    if missing:
        raise KeyError(
            f"Expected models not found: {missing}. "
            f"Available models: {list(all_models.keys())}"
        )

    results = []

    for model_name in selected_names:

        print("\n" + "=" * 75)
        print(f"MODEL: {model_name}")
        print("=" * 75)

        model = all_models[model_name]

        print("Training model...")

        model.fit(X_train, y_train)

        baseline_predictions = model.predict(X_val)

        baseline_score = balanced_accuracy_score(
            y_val,
            baseline_predictions,
        )

        print(
            f"Baseline validation balanced accuracy: "
            f"{baseline_score:.6f}"
        )

        print("Calculating permutation importance...")

        importance = permutation_importance(
            estimator=model,
            X=X_val,
            y=y_val,
            scoring="balanced_accuracy",
            n_repeats=N_REPEATS,
            random_state=RANDOM_STATE,
            n_jobs=1,
        )

        model_results = pd.DataFrame({
            "model": model_name,
            "feature": features,
            "importance_mean": importance.importances_mean,
            "importance_std": importance.importances_std,
        })

        model_results["baseline_balanced_accuracy"] = baseline_score

        # A larger positive value means shuffling the feature
        # caused a greater reduction in validation performance.
        model_results = model_results.sort_values(
            "importance_mean",
            ascending=False,
        ).reset_index(drop=True)

        model_results["importance_rank"] = (
            np.arange(1, len(model_results) + 1)
        )

        results.append(model_results)

        print("\nTop 10 features:")

        print(
            model_results[
                [
                    "importance_rank",
                    "feature",
                    "importance_mean",
                    "importance_std",
                ]
            ].head(10).to_string(index=False)
        )

        sentiment_result = model_results[
            model_results["feature"] == "sentiment_score"
        ]

        print("\nSentiment feature result:")

        print(sentiment_result.to_string(index=False))

    # Combine all model results.
    final_results = pd.concat(results, ignore_index=True)

    csv_path = os.path.join(
        OUTPUT_DIR,
        "permutation_feature_importance.csv",
    )

    json_path = os.path.join(
        OUTPUT_DIR,
        "permutation_feature_importance.json",
    )

    final_results.to_csv(csv_path, index=False)

    metadata = {
        "experiment": "Permutation feature importance",
        "feature_count": len(features),
        "features": features,
        "models": selected_names,
        "scoring": "balanced_accuracy",
        "repeats": N_REPEATS,
        "random_state": RANDOM_STATE,
        "feature_set": "34_features_with_sentiment",
        "sentiment_feature": "sentiment_score",
        "test_set_used": False,
        "production_artifacts_modified": False,
        "ensemble_weights_changed": False,
        "decision_thresholds_changed": False,
        "train_rows": len(train_df),
        "validation_rows": len(val_df),
        "results": final_results.to_dict(orient="records"),
    }

    with open(json_path, "w", encoding="utf-8") as file:
        json.dump(metadata, file, indent=2, default=str)

    print("\n" + "=" * 75)
    print("FEATURE IMPORTANCE ANALYSIS COMPLETED")
    print("=" * 75)

    print("\nSaved files:")
    print(csv_path)
    print(json_path)

    print("\nTest set was not evaluated.")
    print("Production artifacts were not modified.")
    print("Ensemble weights and thresholds were not changed.")


if __name__ == "__main__":
    main()
