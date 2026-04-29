import joblib
import numpy as np

# Load trained model
model = joblib.load("src/decision_engine/decision_model.pkl")


def get_decision(returns, moving_avg, sentiment_score):
    input_data = np.array([[returns, moving_avg, sentiment_score]])

    pred = model.predict(input_data)[0]

    if pred == 1:
        return "BUY"
    elif pred == -1:
        return "SELL"
    else:
        return "HOLD"