import os
import json
import numpy as np
import pandas as pd

from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    precision_score,
    recall_score,
    f1_score,
)


# ============================================================
# PATHS
# ============================================================

VALIDATION_PATH = (
    "src/ml/saved_models/ensemble/"
    "validation_results.csv"
)

TEST_PATH = (
    "src/ml/saved_models/ensemble/"
    "test_results.csv"
)

OUTPUT_DIR = "src/ml/decision"

os.makedirs(
    OUTPUT_DIR,
    exist_ok=True,
)

THRESHOLD_RESULTS_PATH = os.path.join(
    OUTPUT_DIR,
    "threshold_analysis.csv",
)

CONFIG_PATH = os.path.join(
    OUTPUT_DIR,
    "decision_config.json",
)

TEST_DECISIONS_PATH = os.path.join(
    OUTPUT_DIR,
    "test_decisions.csv",
)


# ============================================================
# DECISION FUNCTION
# ============================================================

def generate_decisions(
    buy_probability,
    spread,
    spread_threshold,
):

    decisions = np.full(
        len(buy_probability),
        "HOLD",
        dtype=object,
    )

    buy_mask = (
        (buy_probability >= 0.50)
        & (spread >= spread_threshold)
    )

    sell_mask = (
        (buy_probability < 0.50)
        & (spread >= spread_threshold)
    )

    decisions[buy_mask] = "BUY"
    decisions[sell_mask] = "SELL"

    return decisions


# ============================================================
# EVALUATE THRESHOLD
# ============================================================

def evaluate_threshold(
    df,
    threshold,
):

    decisions = generate_decisions(
        df["Ensemble_BUY"].to_numpy(),
        df["Spread"].to_numpy(),
        threshold,
    )

    actual = df["Actual_Label"].to_numpy()

    trade_mask = decisions != "HOLD"

    coverage = trade_mask.mean()

    if trade_mask.sum() == 0:

        return {
            "threshold": threshold,
            "coverage": 0.0,
            "hold_rate": 1.0,
            "trade_count": 0,
            "accuracy": np.nan,
            "balanced_accuracy": np.nan,
            "macro_f1": np.nan,
            "buy_count": 0,
            "sell_count": 0,
        }

    trade_actual = actual[trade_mask]
    trade_predictions = (
        decisions[trade_mask] == "BUY"
    ).astype(int)

    accuracy = accuracy_score(
        trade_actual,
        trade_predictions,
    )

    balanced_accuracy = balanced_accuracy_score(
        trade_actual,
        trade_predictions,
    )

    macro_f1 = f1_score(
        trade_actual,
        trade_predictions,
        average="macro",
    )

    return {
        "threshold": threshold,
        "coverage": float(coverage),
        "hold_rate": float(1.0 - coverage),
        "trade_count": int(trade_mask.sum()),
        "accuracy": float(accuracy),
        "balanced_accuracy": float(
            balanced_accuracy
        ),
        "macro_f1": float(macro_f1),
        "buy_count": int(
            (decisions == "BUY").sum()
        ),
        "sell_count": int(
            (decisions == "SELL").sum()
        ),
    }


# ============================================================
# SEARCH VALIDATION THRESHOLDS
# ============================================================

def find_best_threshold(validation_df):

    print("\n" + "=" * 60)
    print("SEARCHING DECISION THRESHOLDS")
    print("=" * 60)

    thresholds = np.arange(
        0.00,
        0.51,
        0.02,
    )

    records = []

    for threshold in thresholds:

        result = evaluate_threshold(
            validation_df,
            threshold,
        )

        records.append(result)

    results = pd.DataFrame(records)

    # We require at least 20% of samples
    # to receive BUY/SELL decisions.
    eligible = results[
        results["coverage"] >= 0.20
    ].copy()

    if eligible.empty:

        raise RuntimeError(
            "No threshold satisfies the minimum "
            "coverage requirement."
        )

    # Select based on validation balanced accuracy.
    best_row = eligible.loc[
        eligible["balanced_accuracy"].idxmax()
    ]

    best_threshold = float(
        best_row["threshold"]
    )

    print("\nThreshold analysis:")

    print(
        results.to_string(
            index=False,
            float_format=lambda x: f"{x:.4f}",
        )
    )

    print("\n" + "=" * 60)
    print("SELECTED DECISION THRESHOLD")
    print("=" * 60)

    print(
        f"Spread threshold: "
        f"{best_threshold:.2f}"
    )

    print(
        f"Validation coverage: "
        f"{best_row['coverage']:.2%}"
    )

    print(
        f"Validation HOLD rate: "
        f"{best_row['hold_rate']:.2%}"
    )

    print(
        f"Validation balanced accuracy: "
        f"{best_row['balanced_accuracy']:.4f}"
    )

    print(
        f"Validation Macro F1: "
        f"{best_row['macro_f1']:.4f}"
    )

    print(
        f"BUY decisions: "
        f"{int(best_row['buy_count'])}"
    )

    print(
        f"SELL decisions: "
        f"{int(best_row['sell_count'])}"
    )

    return (
        best_threshold,
        results,
    )


# ============================================================
# APPLY TO TEST
# ============================================================

def evaluate_test(
    test_df,
    threshold,
):

    print("\n" + "=" * 60)
    print("APPLYING FROZEN THRESHOLD TO TEST")
    print("=" * 60)

    test_df = test_df.copy()

    test_df["Final_Signal"] = generate_decisions(
        test_df["Ensemble_BUY"].to_numpy(),
        test_df["Spread"].to_numpy(),
        threshold,
    )

    actual = test_df["Actual_Label"].to_numpy()

    trade_mask = (
        test_df["Final_Signal"] != "HOLD"
    )

    trade_count = trade_mask.sum()

    if trade_count > 0:

        trade_actual = actual[trade_mask]

        trade_predictions = (
            test_df.loc[
                trade_mask,
                "Final_Signal",
            ]
            == "BUY"
        ).astype(int)

        accuracy = accuracy_score(
            trade_actual,
            trade_predictions,
        )

        balanced_accuracy = (
            balanced_accuracy_score(
                trade_actual,
                trade_predictions,
            )
        )

        macro_f1 = f1_score(
            trade_actual,
            trade_predictions,
            average="macro",
        )

    else:

        accuracy = np.nan
        balanced_accuracy = np.nan
        macro_f1 = np.nan

    coverage = (
        trade_count / len(test_df)
    )

    print(
        f"Test coverage: "
        f"{coverage:.2%}"
    )

    print(
        f"Test HOLD rate: "
        f"{1.0 - coverage:.2%}"
    )

    print(
        f"Test trade decisions: "
        f"{trade_count}"
    )

    print(
        f"Test BUY decisions: "
        f"{(test_df['Final_Signal'] == 'BUY').sum()}"
    )

    print(
        f"Test SELL decisions: "
        f"{(test_df['Final_Signal'] == 'SELL').sum()}"
    )

    print(
        f"Test balanced accuracy: "
        f"{balanced_accuracy:.4f}"
    )

    print(
        f"Test Macro F1: "
        f"{macro_f1:.4f}"
    )

    return test_df


# ============================================================
# MAIN
# ============================================================

def main():

    # --------------------------------------------------------
    # LOAD VALIDATION DATA
    # --------------------------------------------------------

    print("\n" + "=" * 60)
    print("LOADING VALIDATION RESULTS")
    print("=" * 60)

    validation_df = pd.read_csv(
        VALIDATION_PATH
    )

    print(
        f"Validation rows: "
        f"{len(validation_df)}"
    )

    # --------------------------------------------------------
    # FIND THRESHOLD USING VALIDATION ONLY
    # --------------------------------------------------------

    (
        best_threshold,
        threshold_results,
    ) = find_best_threshold(
        validation_df
    )

    threshold_results.to_csv(
        THRESHOLD_RESULTS_PATH,
        index=False,
    )

    # --------------------------------------------------------
    # LOAD TEST DATA
    # --------------------------------------------------------

    print("\n" + "=" * 60)
    print("LOADING TEST RESULTS")
    print("=" * 60)

    test_df = pd.read_csv(
        TEST_PATH
    )

    print(
        f"Test rows: "
        f"{len(test_df)}"
    )

    # --------------------------------------------------------
    # APPLY FROZEN THRESHOLD
    # --------------------------------------------------------

    test_decisions = evaluate_test(
        test_df,
        best_threshold,
    )

    # --------------------------------------------------------
    # SAVE TEST DECISIONS
    # --------------------------------------------------------

    test_decisions.to_csv(
        TEST_DECISIONS_PATH,
        index=False,
    )

    # --------------------------------------------------------
    # SAVE CONFIG
    # --------------------------------------------------------

    config = {
        "spread_threshold": best_threshold,
        "probability_boundary": 0.50,
        "minimum_validation_coverage": 0.20,
        "ensemble_method": "equal_weight_average",
        "decision_rule": {
            "BUY": (
                "Ensemble_BUY >= 0.50 "
                "and Spread >= threshold"
            ),
            "SELL": (
                "Ensemble_BUY < 0.50 "
                "and Spread >= threshold"
            ),
            "HOLD": (
                "Spread < threshold"
            ),
        },
    }

    with open(
        CONFIG_PATH,
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(
            config,
            f,
            indent=4,
        )

    # --------------------------------------------------------
    # SAMPLE
    # --------------------------------------------------------

    print("\n" + "=" * 60)
    print("SAMPLE FINAL DECISIONS")
    print("=" * 60)

    print(
        test_decisions[
            [
                "Date",
                "Ticker",
                "Ensemble_BUY",
                "Ensemble_SELL",
                "Spread",
                "Final_Signal",
            ]
        ]
        .head(20)
        .to_string(index=False)
    )

    # --------------------------------------------------------
    # COMPLETE
    # --------------------------------------------------------

    print("\n" + "=" * 60)
    print("DECISION ENGINE COMPLETE")
    print("=" * 60)

    print(
        f"Threshold analysis: "
        f"{THRESHOLD_RESULTS_PATH}"
    )

    print(
        f"Decision config: "
        f"{CONFIG_PATH}"
    )

    print(
        f"Test decisions: "
        f"{TEST_DECISIONS_PATH}"
    )


if __name__ == "__main__":
    main()