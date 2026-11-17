
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

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
from src.ml.models.final_evaluation_finalists import (
    load_parameters,
    build_finalists,
)


# =========================================================
# CONFIGURATION
# =========================================================

RANDOM_STATE = 42

MODEL_NAMES = [
    "CatBoost",
    "LightGBM",
]

FEATURE_COLUMNS = list(base.FEATURES)

THRESHOLDS = np.round(
    np.arange(0.35, 0.651, 0.01),
    3,
)

NUMBER_OF_WINDOWS = 3

OUTPUT_DIR = (
    Path(__file__).resolve().parent
    / "final_results"
    / "final_threshold_selection"
)

CANDIDATE_DIR = OUTPUT_DIR / "candidates"

OUTPUT_DIR.mkdir(
    parents=True,
    exist_ok=True,
)

CANDIDATE_DIR.mkdir(
    parents=True,
    exist_ok=True,
)


# =========================================================
# METRIC CALCULATION
# =========================================================

def calculate_metrics(
    y_true,
    probabilities,
    threshold,
):

    y_true = np.asarray(y_true)

    probabilities = np.asarray(
        probabilities
    ).reshape(-1)

    predictions = (
        probabilities >= threshold
    ).astype(int)

    has_both_classes = (
        len(np.unique(y_true)) == 2
    )

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

        "sell_recall": recall_score(
            y_true,
            predictions,
            pos_label=0,
            zero_division=0,
        ),

        "buy_recall": recall_score(
            y_true,
            predictions,
            pos_label=1,
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
# CREATE CHRONOLOGICAL VALIDATION WINDOWS
# =========================================================

def create_validation_windows(validation_df):

    validation_df = validation_df.copy()

    validation_df = validation_df.sort_values(
        ["Date", "Ticker"]
    ).reset_index(drop=True)

    unique_dates = np.array(
        sorted(validation_df["Date"].unique())
    )

    if len(unique_dates) < NUMBER_OF_WINDOWS:
        raise ValueError(
            "Not enough validation dates to create "
            "three chronological windows."
        )

    date_groups = np.array_split(
        unique_dates,
        NUMBER_OF_WINDOWS,
    )

    windows = {}

    for index, dates in enumerate(
        date_groups,
        start=1,
    ):

        window_df = validation_df[
            validation_df["Date"].isin(dates)
        ].copy()

        if window_df.empty:
            raise ValueError(
                f"Validation window {index} is empty."
            )

        if window_df["Label"].nunique() != 2:
            raise ValueError(
                f"Validation window {index} "
                "does not contain both classes."
            )

        windows[f"W{index}"] = window_df

        print(
            f"W{index}: "
            f"{window_df['Date'].min().date()} to "
            f"{window_df['Date'].max().date()} | "
            f"{len(window_df):,} rows"
        )

    return windows


# =========================================================
# EVALUATE ALL THRESHOLDS ON VALIDATION
# =========================================================

def evaluate_validation_thresholds(
    model_name,
    model,
    validation_windows,
):

    all_results = []
    all_predictions = []

    print("\n" + "=" * 75)
    print(f"VALIDATION THRESHOLD SEARCH: {model_name}")
    print("=" * 75)

    for window_name, window_df in (
        validation_windows.items()
    ):

        X = window_df[
            FEATURE_COLUMNS
        ]

        y = window_df["Label"].to_numpy()

        probabilities = model.predict_proba(
            X
        )[:, 1]

        prediction_records = window_df[
            ["Date", "Ticker", "Label"]
        ].copy()

        prediction_records[
            "BUY_Probability"
        ] = probabilities

        prediction_records[
            "Model"
        ] = model_name

        prediction_records[
            "Window"
        ] = window_name

        all_predictions.append(
            prediction_records
        )

        for threshold in THRESHOLDS:

            metrics = calculate_metrics(
                y_true=y,
                probabilities=probabilities,
                threshold=threshold,
            )

            metrics["model"] = model_name
            metrics["window"] = window_name
            metrics["threshold"] = float(threshold)

            all_results.append(metrics)

    results_df = pd.DataFrame(
        all_results
    )

    predictions_df = pd.concat(
        all_predictions,
        ignore_index=True,
    )

    return results_df, predictions_df


# =========================================================
# SELECT ONE GLOBAL THRESHOLD PER MODEL
# =========================================================

def select_best_threshold(results_df):

    summary = (
        results_df
        .groupby(
            ["model", "threshold"],
            as_index=False,
        )
        .agg(
            mean_balanced_accuracy=(
                "balanced_accuracy",
                "mean",
            ),

            std_balanced_accuracy=(
                "balanced_accuracy",
                "std",
            ),

            minimum_balanced_accuracy=(
                "balanced_accuracy",
                "min",
            ),

            mean_macro_f1=(
                "macro_f1",
                "mean",
            ),

            mean_buy_recall=(
                "buy_recall",
                "mean",
            ),

            mean_sell_recall=(
                "sell_recall",
                "mean",
            ),

            mean_roc_auc=(
                "roc_auc",
                "mean",
            ),
        )
    )

    # Population standard deviation across the
    # three validation windows.

    summary["std_balanced_accuracy"] = (
        summary["std_balanced_accuracy"]
        .fillna(0)
    )

    summary["distance_from_050"] = (
        summary["threshold"] - 0.50
    ).abs()

    selected_rows = []

    for model_name in MODEL_NAMES:

        model_summary = summary[
            summary["model"] == model_name
        ].copy()

        # Primary criterion:
        # Highest mean balanced accuracy.
        #
        # Tie-breakers:
        # Lower variation across windows.
        # Threshold closest to 0.50.

        model_summary = model_summary.sort_values(
            [
                "mean_balanced_accuracy",
                "std_balanced_accuracy",
                "distance_from_050",
            ],
            ascending=[
                False,
                True,
                True,
            ],
        )

        best_row = model_summary.iloc[0]

        selected_rows.append(
            best_row
        )

    selected_df = pd.DataFrame(
        selected_rows
    ).reset_index(drop=True)

    return summary, selected_df


# =========================================================
# FINAL TEST EVALUATION
# =========================================================

def evaluate_final_test(
    model_name,
    model,
    test_df,
    threshold,
):

    X_test = test_df[
        FEATURE_COLUMNS
    ]

    y_test = test_df[
        "Label"
    ].to_numpy()

    probabilities = model.predict_proba(
        X_test
    )[:, 1]

    metrics = calculate_metrics(
        y_true=y_test,
        probabilities=probabilities,
        threshold=threshold,
    )

    metrics["model"] = model_name
    metrics["threshold"] = threshold

    predictions = (
        probabilities >= threshold
    ).astype(int)

    confusion = confusion_matrix(
        y_test,
        predictions,
        labels=[0, 1],
    )

    confusion_df = pd.DataFrame(
        confusion,
        index=[
            "Actual_SELL",
            "Actual_BUY",
        ],
        columns=[
            "Predicted_SELL",
            "Predicted_BUY",
        ],
    )

    confusion_df.to_csv(
        OUTPUT_DIR
        / f"{model_name.lower()}_final_confusion_matrix.csv"
    )

    prediction_df = test_df[
        ["Date", "Ticker", "Label"]
    ].copy()

    prediction_df[
        "Prediction"
    ] = predictions

    prediction_df[
        "BUY_Probability"
    ] = probabilities

    prediction_df[
        "Threshold"
    ] = threshold

    prediction_df[
        "Model"
    ] = model_name

    return metrics, prediction_df


# =========================================================
# SAVE FINAL CANDIDATE MODEL
# =========================================================

def save_candidate_model(
    model_name,
    model,
    parameters,
    threshold,
):

    model_directory = (
        CANDIDATE_DIR / model_name.lower()
    )

    model_directory.mkdir(
        parents=True,
        exist_ok=True,
    )

    if model_name == "CatBoost":

        model_path = (
            model_directory / "model.cbm"
        )

        model.save_model(
            str(model_path)
        )

    elif model_name == "LightGBM":

        model_path = (
            model_directory / "model.txt"
        )

        model.booster_.save_model(
            str(model_path)
        )

    configuration = {
        "model": model_name,

        "decision_threshold": float(
            threshold
        ),

        "features": FEATURE_COLUMNS,

        "number_of_features": len(
            FEATURE_COLUMNS
        ),

        "sentiment_included": (
            "sentiment_score" in FEATURE_COLUMNS
        ),

        "parameters": parameters[model_name],

        "random_state": RANDOM_STATE,

        "training_data": (
            "Combined training and validation data"
        ),

        "calibration": False,
    }

    config_path = (
        model_directory / "model_config.json"
    )

    with open(
        config_path,
        "w",
        encoding="utf-8",
    ) as file:

        json.dump(
            configuration,
            file,
            indent=4,
        )

    print(
        f"\nSaved {model_name} candidate:"
    )

    print(model_path)
    print(config_path)


# =========================================================
# MAIN
# =========================================================

def main():

    print("=" * 80)
    print("QUANTEDGE: FINAL THRESHOLD SELECTION")
    print("=" * 80)

    # -----------------------------------------------------
    # Verify features
    # -----------------------------------------------------

    if len(FEATURE_COLUMNS) != 34:
        raise ValueError(
            f"Expected 34 features, found "
            f"{len(FEATURE_COLUMNS)}."
        )

    if "sentiment_score" not in FEATURE_COLUMNS:
        raise ValueError(
            "sentiment_score is missing."
        )

    if "Future_Return" in FEATURE_COLUMNS:
        raise ValueError(
            "Future_Return cannot be a model feature."
        )

    print("\nFeatures:", len(FEATURE_COLUMNS))
    print("Sentiment: INCLUDED")
    print("Models:", MODEL_NAMES)

    # -----------------------------------------------------
    # Load frozen hyperparameters
    # -----------------------------------------------------

    parameters = load_parameters()

    print("\nFrozen hyperparameters loaded.")

    # -----------------------------------------------------
    # Load data and recreate original splits
    # -----------------------------------------------------

    df = base.load_data()

    (
        train_df,
        validation_df,
        test_df,
        thresholds_df,
    ) = base.build_splits(df)

    train_df = train_df.copy()
    validation_df = validation_df.copy()
    test_df = test_df.copy()

    # -----------------------------------------------------
    # Basic data checks
    # -----------------------------------------------------

    for name, part in [
        ("Training", train_df),
        ("Validation", validation_df),
        ("Test", test_df),
    ]:

        if part.empty:
            raise ValueError(
                f"{name} split is empty."
            )

        if not set(
            part["Label"].unique()
        ).issubset({0, 1}):

            raise ValueError(
                f"{name} split contains invalid labels."
            )

        if part[FEATURE_COLUMNS].isna().any().any():
            raise ValueError(
                f"{name} split contains missing feature values."
            )

        if part[FEATURE_COLUMNS].isin(
            [np.inf, -np.inf]
        ).any().any():

            raise ValueError(
                f"{name} split contains infinite feature values."
            )

    print("\nDATA SPLITS")

    print(
        f"Training: {len(train_df):,}"
    )

    print(
        f"Validation: {len(validation_df):,}"
    )

    print(
        f"Test: {len(test_df):,}"
    )

    # -----------------------------------------------------
    # Create chronological validation windows
    # -----------------------------------------------------

    print("\nVALIDATION WINDOWS")

    validation_windows = (
        create_validation_windows(
            validation_df
        )
    )

    # -----------------------------------------------------
    # Train models on training data only
    # -----------------------------------------------------

    models = build_finalists(
        parameters
    )

    all_validation_results = []
    all_validation_predictions = []

    for model_name in MODEL_NAMES:

        model = models[model_name]

        print("\n" + "=" * 75)
        print(f"TRAINING: {model_name}")
        print("=" * 75)

        model.fit(
            train_df[FEATURE_COLUMNS],
            train_df["Label"],
        )

        print("Training completed.")

        # ---------------------------------------------
        # Validation threshold evaluation
        # ---------------------------------------------

        results_df, predictions_df = (
            evaluate_validation_thresholds(
                model_name,
                model,
                validation_windows,
            )
        )

        all_validation_results.append(
            results_df
        )

        all_validation_predictions.append(
            predictions_df
        )

    # -----------------------------------------------------
    # Combine validation results
    # -----------------------------------------------------

    validation_results = pd.concat(
        all_validation_results,
        ignore_index=True,
    )

    validation_predictions = pd.concat(
        all_validation_predictions,
        ignore_index=True,
    )

    validation_results.to_csv(
        OUTPUT_DIR
        / "validation_window_metrics.csv",
        index=False,
    )

    validation_predictions.to_csv(
        OUTPUT_DIR
        / "validation_predictions.csv",
        index=False,
    )

    # -----------------------------------------------------
    # Select best threshold
    # -----------------------------------------------------

    summary_df, selected_df = (
        select_best_threshold(
            validation_results
        )
    )

    summary_df.to_csv(
        OUTPUT_DIR
        / "all_threshold_comparison.csv",
        index=False,
    )

    selected_df.to_csv(
        OUTPUT_DIR
        / "selected_thresholds.csv",
        index=False,
    )

    selected_thresholds = {}

    print("\n" + "=" * 80)
    print("SELECTED VALIDATION THRESHOLDS")
    print("=" * 80)

    for _, row in selected_df.iterrows():

        model_name = row["model"]

        threshold = float(
            row["threshold"]
        )

        selected_thresholds[
            model_name
        ] = threshold

        print(f"\n{model_name}")

        print(
            f"Selected threshold: {threshold:.3f}"
        )

        print(
            "Mean balanced accuracy: "
            f"{row['mean_balanced_accuracy']:.5f}"
        )

        print(
            "Variation across windows: "
            f"{row['std_balanced_accuracy']:.5f}"
        )

        print(
            "Minimum window balanced accuracy: "
            f"{row['minimum_balanced_accuracy']:.5f}"
        )

        print(
            "Mean BUY recall: "
            f"{row['mean_buy_recall']:.5f}"
        )

        print(
            "Mean SELL recall: "
            f"{row['mean_sell_recall']:.5f}"
        )

        print(
            "Mean macro F1: "
            f"{row['mean_macro_f1']:.5f}"
        )

    # -----------------------------------------------------
    # Save selected threshold configuration
    # -----------------------------------------------------

    with open(
        OUTPUT_DIR / "selected_thresholds.json",
        "w",
        encoding="utf-8",
    ) as file:

        json.dump(
            selected_thresholds,
            file,
            indent=4,
        )

    # -----------------------------------------------------
    # Refit candidates on training + validation
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

    print("\n" + "=" * 80)
    print("FINAL CANDIDATE TRAINING")
    print("=" * 80)

    print(
        f"Combined training rows: {len(train_final):,}"
    )

    print(
        f"Test rows: {len(test_df):,}"
    )

    final_test_results = []
    final_test_predictions = []

    # -----------------------------------------------------
    # Rebuild and save both final candidates
    # -----------------------------------------------------

    for model_name in MODEL_NAMES:

        print("\n" + "=" * 75)
        print(f"FINAL REFIT: {model_name}")
        print("=" * 75)

        final_model = build_finalists(
            parameters
        )[model_name]

        final_model.fit(
            train_final[FEATURE_COLUMNS],
            train_final["Label"],
        )

        print("Final refit completed.")

        threshold = selected_thresholds[
            model_name
        ]

        # ---------------------------------------------
        # Save candidate model
        # ---------------------------------------------

        save_candidate_model(
            model_name=model_name,
            model=final_model,
            parameters=parameters,
            threshold=threshold,
        )

        # ---------------------------------------------
        # Final test diagnostic
        # ---------------------------------------------

        metrics, predictions = (
            evaluate_final_test(
                model_name=model_name,
                model=final_model,
                test_df=test_df,
                threshold=threshold,
            )
        )

        final_test_results.append(
            metrics
        )

        final_test_predictions.append(
            predictions
        )

    # -----------------------------------------------------
    # Save final test diagnostic results
    # -----------------------------------------------------

    final_results_df = pd.DataFrame(
        final_test_results
    )

    final_results_df.to_csv(
        OUTPUT_DIR
        / "final_test_diagnostic.csv",
        index=False,
    )

    final_predictions_df = pd.concat(
        final_test_predictions,
        ignore_index=True,
    )

    final_predictions_df.to_csv(
        OUTPUT_DIR
        / "final_test_predictions.csv",
        index=False,
    )

    # -----------------------------------------------------
    # Display final comparison
    # -----------------------------------------------------

    print("\n" + "=" * 80)
    print("FINAL TEST DIAGNOSTIC COMPARISON")
    print("=" * 80)

    display_columns = [
        "model",
        "threshold",
        "accuracy",
        "balanced_accuracy",
        "macro_precision",
        "macro_recall",
        "macro_f1",
        "buy_recall",
        "sell_recall",
        "roc_auc",
    ]

    print(
        final_results_df[
            display_columns
        ].to_string(
            index=False,
            float_format=lambda x: f"{x:.5f}",
        )
    )

    print("\n" + "=" * 80)
    print("EXPERIMENT COMPLETED")
    print("=" * 80)

    print("\nResults saved to:")
    print(OUTPUT_DIR)

    print("\nCandidate models saved to:")
    print(CANDIDATE_DIR)

    print(
        "\nNo existing production model was modified."
    )

    print(
        "Test results are diagnostic only. "
        "Thresholds were selected using validation data."
    )


if __name__ == "__main__":
    main()
