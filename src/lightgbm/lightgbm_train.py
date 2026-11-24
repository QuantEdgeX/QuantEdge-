import os
import numpy as np
import pandas as pd

from lightgbm import LGBMClassifier
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    classification_report,
    confusion_matrix
)

from src.lightgbm.prepare_data import prepare_data


# ============================================================
# CONFIGURATION
# ============================================================

MODEL_PATH = "src/lightgbm/lightgbm_final.txt"
THRESHOLD_PATH = "src/lightgbm/best_thresholds.csv"


# ============================================================
# LIGHTGBM PARAMETERS
# ============================================================

PARAMS = {
    "n_estimators": 300,
    "learning_rate": 0.03,
    "num_leaves": 15,
    "max_depth": -1,
    "min_child_samples": 20,
    "subsample": 0.8,
    "colsample_bytree": 0.8,
    "reg_alpha": 0.0,
    "reg_lambda": 1.0,
    "random_state": 42,
    "verbosity": -1
}


# ============================================================
# THRESHOLD PREDICTION
# ============================================================

def apply_thresholds(
    probabilities,
    buy_threshold,
    sell_threshold
):

    # Default = HOLD
    predictions = np.full(
        len(probabilities),
        1,
        dtype=int
    )

    # BUY probability
    buy_mask = (
        probabilities[:, 0]
        >= buy_threshold
    )

    # SELL probability
    sell_mask = (
        probabilities[:, 2]
        >= sell_threshold
    )

    # BUY
    predictions[buy_mask] = 0

    # SELL
    predictions[sell_mask] = 2

    # --------------------------------------------------------
    # If both BUY and SELL cross their thresholds,
    # choose the class with the stronger probability.
    # --------------------------------------------------------

    both_mask = buy_mask & sell_mask

    predictions[both_mask] = np.where(
        probabilities[both_mask, 0]
        >= probabilities[both_mask, 2],
        0,
        2
    )

    return predictions


# ============================================================
# MAIN
# ============================================================

def main():

    print("\n========== LOADING DATA ==========")

    (
        X_train,
        y_train,
        X_val,
        y_val,
        X_test,
        y_test,
        test_ids
    ) = prepare_data()


    # ========================================================
    # DATA INFORMATION
    # ========================================================

    print("\n========== DATA ==========")

    print("X_train:", X_train.shape)
    print("X_val  :", X_val.shape)
    print("X_test :", X_test.shape)

    print(
        "\nTraining class distribution:",
        np.bincount(y_train, minlength=3)
    )

    print(
        "Validation class distribution:",
        np.bincount(y_val, minlength=3)
    )

    print(
        "Test class distribution:",
        np.bincount(y_test, minlength=3)
    )


    # ========================================================
    # TRAIN LIGHTGBM
    # ========================================================

    print("\n========== TRAINING LIGHTGBM ==========")

    model = LGBMClassifier(**PARAMS)

    model.fit(
        X_train,
        y_train
    )


    # ========================================================
    # GENERATE PROBABILITIES
    # ========================================================

    print(
        "\n========== GENERATING PROBABILITIES =========="
    )

    val_probabilities = model.predict_proba(
        X_val
    )

    test_probabilities = model.predict_proba(
        X_test
    )

    print(
        "Validation probabilities:",
        val_probabilities.shape
    )

    print(
        "Test probabilities:",
        test_probabilities.shape
    )


    # ========================================================
    # NORMAL BASELINE
    # ========================================================

    val_normal = np.argmax(
        val_probabilities,
        axis=1
    )

    test_normal = np.argmax(
        test_probabilities,
        axis=1
    )

    print(
        "\n========== NORMAL BASELINE =========="
    )

    baseline_val_accuracy = accuracy_score(
        y_val,
        val_normal
    )

    baseline_val_f1 = f1_score(
        y_val,
        val_normal,
        average="macro"
    )

    baseline_test_accuracy = accuracy_score(
        y_test,
        test_normal
    )

    baseline_test_f1 = f1_score(
        y_test,
        test_normal,
        average="macro"
    )

    print(
        "Validation Accuracy:",
        f"{baseline_val_accuracy:.4f}"
    )

    print(
        "Validation Macro-F1:",
        f"{baseline_val_f1:.4f}"
    )

    print(
        "Test Accuracy:",
        f"{baseline_test_accuracy:.4f}"
    )

    print(
        "Test Macro-F1:",
        f"{baseline_test_f1:.4f}"
    )


    # ========================================================
    # ROBUST THRESHOLD SEARCH
    # ========================================================

    print(
        "\n========== ROBUST THRESHOLD SEARCH =========="
    )

    buy_thresholds = np.arange(
        0.20,
        0.351,
        0.0125
    )

    sell_thresholds = np.arange(
        0.35,
        0.501,
        0.0125
    )

    results = []


    for buy_threshold in buy_thresholds:

        for sell_threshold in sell_thresholds:

            predictions = apply_thresholds(
                val_probabilities,
                buy_threshold,
                sell_threshold
            )

            accuracy = accuracy_score(
                y_val,
                predictions
            )

            macro_f1 = f1_score(
                y_val,
                predictions,
                average="macro"
            )

            buy_count = np.sum(
                predictions == 0
            )

            hold_count = np.sum(
                predictions == 1
            )

            sell_count = np.sum(
                predictions == 2
            )

            results.append({

                "buy_threshold":
                    round(
                        buy_threshold,
                        4
                    ),

                "sell_threshold":
                    round(
                        sell_threshold,
                        4
                    ),

                "accuracy":
                    accuracy,

                "macro_f1":
                    macro_f1,

                "buy_percent":
                    buy_count / len(predictions),

                "hold_percent":
                    hold_count / len(predictions),

                "sell_percent":
                    sell_count / len(predictions)

            })


    # ========================================================
    # SORT RESULTS
    # ========================================================

    results_df = pd.DataFrame(
        results
    )

    results_df = results_df.sort_values(
        "macro_f1",
        ascending=False
    ).reset_index(drop=True)


    # ========================================================
    # TOP RESULTS
    # ========================================================

    print(
        "\n========== TOP 20 THRESHOLDS =========="
    )

    print(
        results_df.head(20).to_string(
            index=False
        )
    )


    # ========================================================
    # BEST THRESHOLD
    # ========================================================

    best = results_df.iloc[0]

    print(
        "\n========== BEST THRESHOLD =========="
    )

    print(
        f"BUY threshold  : "
        f"{best['buy_threshold']}"
    )

    print(
        f"SELL threshold : "
        f"{best['sell_threshold']}"
    )

    print(
        f"Accuracy       : "
        f"{best['accuracy']:.4f}"
    )

    print(
        f"Macro-F1       : "
        f"{best['macro_f1']:.4f}"
    )


    # ========================================================
    # NEAR-BEST REGION
    # ========================================================

    print(
        "\n========== NEAR-BEST REGION =========="
    )

    best_f1 = best["macro_f1"]

    near_best = results_df[
        results_df["macro_f1"]
        >= best_f1 - 0.01
    ]

    print(
        f"Threshold combinations within "
        f"0.01 Macro-F1 of best: "
        f"{len(near_best)}"
    )

    print(
        near_best.head(20).to_string(
            index=False
        )
    )


    # ========================================================
    # FINAL THRESHOLDS
    # ========================================================

    best_buy = float(
        best["buy_threshold"]
    )

    best_sell = float(
        best["sell_threshold"]
    )


    # ========================================================
    # FINAL VALIDATION
    # ========================================================

    val_predictions = apply_thresholds(
        val_probabilities,
        best_buy,
        best_sell
    )

    final_val_accuracy = accuracy_score(
        y_val,
        val_predictions
    )

    final_val_f1 = f1_score(
        y_val,
        val_predictions,
        average="macro"
    )

    print(
        "\n========== FINAL VALIDATION =========="
    )

    print(
        "Accuracy:",
        f"{final_val_accuracy:.4f}"
    )

    print(
        "Macro-F1:",
        f"{final_val_f1:.4f}"
    )

    print(
        "\nValidation distribution:"
    )

    print(
        "BUY :",
        np.sum(val_predictions == 0),
        f"({np.mean(val_predictions == 0) * 100:.2f}%)"
    )

    print(
        "HOLD:",
        np.sum(val_predictions == 1),
        f"({np.mean(val_predictions == 1) * 100:.2f}%)"
    )

    print(
        "SELL:",
        np.sum(val_predictions == 2),
        f"({np.mean(val_predictions == 2) * 100:.2f}%)"
    )


    # ========================================================
    # FINAL TEST
    # ========================================================

    print(
        "\n========== FINAL TEST =========="
    )

    test_predictions = apply_thresholds(
        test_probabilities,
        best_buy,
        best_sell
    )

    test_accuracy = accuracy_score(
        y_test,
        test_predictions
    )

    test_macro_f1 = f1_score(
        y_test,
        test_predictions,
        average="macro"
    )

    print(
        "Test Accuracy:",
        f"{test_accuracy:.4f}"
    )

    print(
        "Test Macro-F1:",
        f"{test_macro_f1:.4f}"
    )


    # ========================================================
    # IMPROVEMENT
    # ========================================================

    print(
        "\n========== IMPROVEMENT =========="
    )

    print(
        "Accuracy change:",
        f"{test_accuracy - baseline_test_accuracy:+.4f}"
    )

    print(
        "Macro-F1 change:",
        f"{test_macro_f1 - baseline_test_f1:+.4f}"
    )


    # ========================================================
    # CLASSIFICATION REPORT
    # ========================================================

    print(
        "\n========== CLASSIFICATION REPORT =========="
    )

    print(
        classification_report(
            y_test,
            test_predictions,
            target_names=[
                "BUY",
                "HOLD",
                "SELL"
            ]
        )
    )


    # ========================================================
    # CONFUSION MATRIX
    # ========================================================

    print(
        "========== CONFUSION MATRIX =========="
    )

    print(
        confusion_matrix(
            y_test,
            test_predictions
        )
    )


    # ========================================================
    # TEST DISTRIBUTION
    # ========================================================

    print(
        "\n========== TEST PREDICTED DISTRIBUTION =========="
    )

    print(
        "BUY :",
        np.sum(test_predictions == 0),
        f"({np.mean(test_predictions == 0) * 100:.2f}%)"
    )

    print(
        "HOLD:",
        np.sum(test_predictions == 1),
        f"({np.mean(test_predictions == 1) * 100:.2f}%)"
    )

    print(
        "SELL:",
        np.sum(test_predictions == 2),
        f"({np.mean(test_predictions == 2) * 100:.2f}%)"
    )


    # ========================================================
    # TEST ID CHECK
    # ========================================================

    print(
        "\n========== TEST ID CHECK =========="
    )

    print(
        test_ids.head()
    )

    print(
        "Total test IDs:",
        len(test_ids)
    )

    print(
        "Total predictions:",
        len(test_predictions)
    )

    print(
        "Total probabilities:",
        len(test_probabilities)
    )


    # ========================================================
    # SAVE FINAL MODEL
    # ========================================================

    print(
        "\n========== SAVING FINAL MODEL =========="
    )

    # Save trained LightGBM model
    model.booster_.save_model(
        MODEL_PATH
    )

    # Save selected thresholds and final metrics
    pd.DataFrame([{

        "buy_threshold":
            best_buy,

        "sell_threshold":
            best_sell,

        "validation_accuracy":
            final_val_accuracy,

        "validation_macro_f1":
            final_val_f1,

        "test_accuracy":
            test_accuracy,

        "test_macro_f1":
            test_macro_f1

    }]).to_csv(
        THRESHOLD_PATH,
        index=False
    )


    # ========================================================
    # FINAL SUMMARY
    # ========================================================

    print(
        "\n========== FINAL SUMMARY =========="
    )

    print(
        "Model       : LightGBM"
    )

    print(
        "Features    : 15"
    )

    print(
        f"BUY threshold  : {best_buy}"
    )

    print(
        f"SELL threshold : {best_sell}"
    )

    print(
        f"Test Accuracy  : {test_accuracy:.4f}"
    )

    print(
        f"Test Macro-F1  : {test_macro_f1:.4f}"
    )

    print(
        "\n========== SAVED =========="
    )

    print(
        f"Model     : {MODEL_PATH}"
    )

    print(
        f"Thresholds: {THRESHOLD_PATH}"
    )


# ============================================================
# RUN
# ============================================================

if __name__ == "__main__":
    main()