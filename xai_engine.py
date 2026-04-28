# This allows your XAI engine to potentially pull data from the other modules later
import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), 'src')))

class QuantExplainer:
    def __init__(self):
        pass

    def explain(self, prediction, sentiment_score, user_level):
        """
        Provides multi-level explanations based on the user's expertise level.
        user_level: int from 1 (Beginner) to 5 (Expert)
        """
        # Determine overall polarity
        is_bullish = prediction == 1 or sentiment_score > 0
        
        if user_level == 1:
            if is_bullish:
                return "The mood is good and the stock is expected to go up!"
            else:
                return "The mood is bad and the stock might go down."
                
        elif user_level == 2:
            if is_bullish:
                return "Positive news is driving optimism, suggesting an upward trend."
            else:
                return "Negative news is causing concern, suggesting a downward trend."
                
        elif user_level == 3:
            if is_bullish:
                return f"The model predicts an uptrend with a positive sentiment score of {sentiment_score:.2f}."
            else:
                return f"The model predicts a downtrend with a negative sentiment score of {sentiment_score:.2f}."
                
        elif user_level == 4:
            if is_bullish:
                return f"Bullish indicators detected. Model output: {prediction}, FinBERT Sentiment: {sentiment_score:.2f}."
            else:
                return f"Bearish indicators detected. Model output: {prediction}, FinBERT Sentiment: {sentiment_score:.2f}."
                
        elif user_level >= 5:
            if is_bullish:
                return f"Bullish sentiment polarity. The classification model yielded class {prediction} with a composite FinBERT logit-derived score of {sentiment_score:.4f}."
            else:
                return f"Bearish sentiment polarity. The classification model yielded class {prediction} with a composite FinBERT logit-derived score of {sentiment_score:.4f}."
        
        else:
            return "Invalid user level."
