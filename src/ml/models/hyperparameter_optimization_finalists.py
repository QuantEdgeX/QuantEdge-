
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

from catboost import CatBoostClassifier
from lightgbm import LGBMClassifier


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

N_TRIALS = 20

OUTPUT_DIR = (
    Path(__file__).resolve().parent
    / "final_results"
    / "hyperparameter_optimization"
)

OUTPUT_DIR.mkdir(
    parents=True,
    exist_ok=True,
)

MODELS = ["CatBoost", "LightGBM"]


# ---------------------------------------------------------
# VALIDATION WINDOWS
# ---------------------------------------------------------

def create_validation_windows(validation_df):

    validation_df = validation_df.sort_values(
        "Date"
    ).reset_index(drop=True)

    indices = np.array_split(
        np.arange(len(validation_df)),
        3,
    )

    windows = []

    for i, window_indices in enumerate(indices, start=1):

        if len(window_indices) == 0:
            continue

        window = validation_df.iloc[
            window_indices
        ].copy()

        windows.append(
            (f"Window_{i}", window)
        )

    return windows


# ---------------------------------------------------------
# PARAMETER GENERATION
# ---------------------------------------------------------

def generate_catboost_params(rng):

    return {
        "iterations": int(
            rng.choice([400, 500, 600, 700, 800, 900])
        ),
        "depth": int(
            rng.choice([4, 5, 6, 7, 8])
        ),
        "learning_rate": float(
            np.exp(
                rng.uniform(
                    np.log(0.015),
                    np.log(0.12),
                )
            )
        ),
        "l2_leaf_reg": float(
            np.exp(
                rng.uniform(
                    np.log(1.0),
                    np.log(12.0),
                )
            )
        ),
        "random_strength": float(
            rng.uniform(0.0, 1.5)
        ),
        "bagging_temperature": float(
            rng.uniform(0.0, 1.5)
        ),
        "border_count": int(
            rng.choice([64, 128, 254])
        ),
    }


def generate_lightgbm_params(rng):

    max_depth = int(
        rng.choice([-1, 5, 6, 7, 8, 9, 10])
    )

    num_leaves = int(
        rng.choice([15, 20, 25, 31, 40, 50, 63])
    )

    if max_depth > 0:
        num_leaves = min(
            num_leaves,
            2 ** max_depth,
        )

    return {
        "n_estimators": int(
            rng.choice([300, 400, 500, 600, 700, 800, 900])
        ),
        "learning_rate": float(
            np.exp(
                rng.uniform(
                    np.log(0.015),
                    np.log(0.10),
                )
            )
        ),
        "num_leaves": num_leaves,
        "max_depth": max_depth,
        "min_child_samples": int(
            rng.choice([20, 30, 40, 50, 60, 80])
        ),
        "subsample": float(
            rng.uniform(0.7, 1.0)
        ),
        "colsample_bytree": float(
            rng.uniform(0.7, 1.0)
        ),
        "reg_alpha": float(
            np.exp(
                rng.uniform(
                    np.log(0.0001),
                    np.log(5.0),
                )
            )
        ),
        "reg_lambda": float(
            np.exp(
                rng.uniform(
                    np.log(0.1),
                    np.log(10.0),
                )
            )
        ),
    }


# ---------------------------------------------------------
# MODEL CONSTRUCTION
# ---------------------------------------------------------

def build_model(model_name, params):

    if model_name == "CatBoost":

        model = CatBoostClassifier(
            **params,
            loss_function="Logloss",
            eval_metric="AUC",
            random_seed=RANDOM_STATE,
            verbose=False,
            allow_writing_files=False,
            thread_count=-1,
        )

    elif model_name == "LightGBM":

        model = LGBMClassifier(
            **params,
            objective="binary",
            random_state=RANDOM_STATE,
            n_jobs=-1,
            verbosity=-1,
            subsample_freq=1,
        )

    else:
        raise ValueError(
            f"Unknown model: {model_name}"
        )

    return model


# ---------------------------------------------------------
# EVALUATION
# ---------------------------------------------------------

def evaluate_model(
    model,
    X_train,
    y_train,
    validation_windows,
    feature_columns,
):

    model.fit(
        X_train,
        y_train,
    )

    window_results = []

    for window_name, window_df in validation_windows:

        X_val = window_df[
            feature_columns
        ]

        y_val = window_df[
            "Label"
        ]

        predictions = model.predict(
            X_val
        )

        predictions = np.asarray(
            predictions
        ).reshape(-1)

        probabilities = model.predict_proba(
            X_val
        )[:, 1]

        metrics = {
            "window": window_name,
            "rows": len(window_df),
            "accuracy": accuracy_score(
                y_val,
                predictions,
            ),
            "balanced_accuracy": balanced_accuracy_score(
                y_val,
                predictions,
            ),
            "macro_f1": f1_score(
                y_val,
                predictions,
                average="macro",
            ),
            "roc_auc": roc_auc_score(
                y_val,
                probabilities,
            ),
        }

        window_results.append(
            metrics
        )

    return window_results


# ---------------------------------------------------------
# RUN RANDOMIZED SEARCH
# ---------------------------------------------------------

def optimize_model(
    model_name,
    train_df,
    validation_windows,
    feature_columns,
):

    print("\n" + "=" * 80)
    print(f"OPTIMIZING {model_name.upper()}")
    print("=" * 80)

    X_train = train_df[
        feature_columns
    ]

    y_train = train_df[
        "Label"
    ]

    rng = np.random.default_rng(
        RANDOM_STATE
    )

    trial_results = []
    best_result = None

    for trial in range(1, N_TRIALS + 1):

        if model_name == "CatBoost":
            params = generate_catboost_params(
                rng
            )

        else:
            params = generate_lightgbm_params(
                rng
            )

        print(
            f"\n{model_name} Trial "
            f"{trial}/{N_TRIALS}"
        )

        print(
            "Parameters:",
            json.dumps(
                params,
                indent=2,
            ),
        )

        try:

            model = build_model(
                model_name,
                params,
            )

            window_results = evaluate_model(
                model=model,
                X_train=X_train,
                y_train=y_train,
                validation_windows=validation_windows,
                feature_columns=feature_columns,
            )

            scores = [
                result["balanced_accuracy"]
                for result in window_results
            ]

            mean_ba = float(
                np.mean(scores)
            )

            std_ba = float(
                np.std(scores, ddof=1)
            ) if len(scores) > 1 else 0.0

            mean_f1 = float(
                np.mean([
                    result["macro_f1"]
                    for result in window_results
                ])
            )

            mean_auc = float(
                np.mean([
                    result["roc_auc"]
                    for result in window_results
                ])
            )

            result = {
                "model": model_name,
                "trial": trial,
                "mean_balanced_accuracy": mean_ba,
                "std_balanced_accuracy": std_ba,
                "mean_macro_f1": mean_f1,
                "mean_roc_auc": mean_auc,
                "parameters": params,
                "window_results": window_results,
            }

            trial_results.append(
                result
            )

            print(
                f"Mean BA: {mean_ba:.5f} | "
                f"BA Std: {std_ba:.5f} | "
                f"Mean F1: {mean_f1:.5f} | "
                f"Mean AUC: {mean_auc:.5f}"
            )

            if (
                best_result is None
                or mean_ba >
                best_result["mean_balanced_accuracy"]
            ):

                best_result = result

                print(
                    "NEW BEST CONFIGURATION"
                )

        except Exception as error:

            print(
                f"Trial {trial} failed: {error}"
            )

            continue

    if best_result is None:

        raise RuntimeError(
            f"All optimization trials failed for {model_name}."
        )

    return trial_results, best_result


# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------

def main():

    print("=" * 80)
    print(
        "QUANTEDGE: CATBOOST VS LIGHTGBM "
        "HYPERPARAMETER OPTIMIZATION"
    )
    print("=" * 80)

    # Load the original dataset.
    df = base.load_data()

    # Use the existing chronological split logic.
    (
        train_df,
        validation_df,
        test_df,
        thresholds_df,
    ) = base.build_splits(df)

    print("\nFeature configuration:")

    feature_columns = list(
        base.FEATURES
    )

    print(
        f"Number of features: {len(feature_columns)}"
    )

    if len(feature_columns) != 34:
        raise ValueError(
            "Expected 34 features, including sentiment_score. "
            f"Found {len(feature_columns)}."
        )

    if "sentiment_score" not in feature_columns:
        raise ValueError(
            "sentiment_score is missing from base.FEATURES."
        )

    print(
        "Sentiment feature: INCLUDED"
    )

    for feature in feature_columns:

        if feature not in train_df.columns:
            raise ValueError(
                f"Missing feature: {feature}"
            )

    validation_windows = create_validation_windows(
        validation_df
    )

    print("\nValidation windows:")

    for name, window in validation_windows:

        print(
            f"{name}: {len(window):,} rows, "
            f"{window['Date'].min().date()} to "
            f"{window['Date'].max().date()}"
        )

    all_trial_results = []
    final_results = []

    for model_name in MODELS:

        trial_results, best_result = optimize_model(
            model_name=model_name,
            train_df=train_df,
            validation_windows=validation_windows,
            feature_columns=feature_columns,
        )

        all_trial_results.extend(
            trial_results
        )

        final_results.append(
            best_result
        )

    # -----------------------------------------------------
    # SAVE ALL TRIAL RESULTS
    # -----------------------------------------------------

    trial_rows = []

    for result in all_trial_results:

        for window_result in result["window_results"]:

            trial_rows.append({
                "model": result["model"],
                "trial": result["trial"],
                "mean_balanced_accuracy":
                    result["mean_balanced_accuracy"],
                "std_balanced_accuracy":
                    result["std_balanced_accuracy"],
                "mean_macro_f1":
                    result["mean_macro_f1"],
                "mean_roc_auc":
                    result["mean_roc_auc"],
                **window_result,
                "parameters": json.dumps(
                    result["parameters"]
                ),
            })

    pd.DataFrame(
        trial_rows
    ).to_csv(
        OUTPUT_DIR / "all_trial_results.csv",
        index=False,
    )

    # -----------------------------------------------------
    # SAVE BEST CONFIGURATIONS
    # -----------------------------------------------------

    best_parameters = {}

    summary_rows = []

    for result in final_results:

        model_name = result["model"]

        best_parameters[model_name] = (
            result["parameters"]
        )

        summary_rows.append({
            "model": model_name,
            "best_trial": result["trial"],
            "mean_balanced_accuracy":
                result["mean_balanced_accuracy"],
            "std_balanced_accuracy":
                result["std_balanced_accuracy"],
            "mean_macro_f1":
                result["mean_macro_f1"],
            "mean_roc_auc":
                result["mean_roc_auc"],
        })

    with open(
        OUTPUT_DIR / "best_parameters.json",
        "w",
        encoding="utf-8",
    ) as file:

        json.dump(
            best_parameters,
            file,
            indent=4,
        )

    summary_df = pd.DataFrame(
        summary_rows
    ).sort_values(
        "mean_balanced_accuracy",
        ascending=False,
    )

    summary_df.to_csv(
        OUTPUT_DIR / "best_model_summary.csv",
        index=False,
    )

    # -----------------------------------------------------
    # DISPLAY RESULTS
    # -----------------------------------------------------

    print("\n" + "=" * 80)
    print("FINAL OPTIMIZATION RESULTS")
    print("=" * 80)

    print(
        summary_df.to_string(
            index=False,
            float_format=lambda x: f"{x:.5f}",
        )
    )

    print("\nBest parameters saved to:")
    print(
        OUTPUT_DIR / "best_parameters.json"
    )

    print("\nAll trial results saved to:")
    print(
        OUTPUT_DIR / "all_trial_results.csv"
    )

    print("\nTest set was not evaluated.")
    print("Existing production models were not modified.")

    print("\nOptimization completed.")


if __name__ == "__main__":
    main()
