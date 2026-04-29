from src.data.fetch_data import fetch_stock_data
from src.decision_engine.create_dataset import prepare_dataset
from src.decision_engine.decision import get_decision
from src.sentimentanalysis.main import get_sentiment_data

def run():
    # 1. Stock data
    df = fetch_stock_data("AAPL")

    # 2. Sentiment
    sentiment_df = get_sentiment_data()

    # 3. Merge + features
    df = prepare_dataset(df, sentiment_df)

    # 4. Latest row
    latest = df.iloc[-1]

    returns = latest['returns']
    moving_avg = latest['moving_avg']
    sentiment_score = latest['sentiment_score']

    # 5. Decision
    decision = get_decision(returns, moving_avg, sentiment_score)

    print("📊 Final Decision:", decision)


if __name__ == "__main__":
    run()