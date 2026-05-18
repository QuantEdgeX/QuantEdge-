import yfinance as yf
import pandas as pd

def fetch_stock_data(tickers, start="2020-01-01", end="2024-01-01"):
    all_data = []

    for ticker in tickers:
        df = yf.download(ticker, start=start, end=end)

        # Remove multi-index columns if present
        if isinstance(df.columns, pd.MultiIndex):
            df.columns = df.columns.get_level_values(0)

        df.reset_index(inplace=True)

        # Add ticker column
        df["Ticker"] = ticker

        all_data.append(df)

    final_df = pd.concat(all_data, ignore_index=True)

    return final_df

if __name__ == "__main__":
    tickers = ["AAPL", "MSFT", "GOOGL", "TSLA", "AMZN", "META", "NVDA", "NFLX", "AMD", "JPM"]

    data = fetch_stock_data(tickers)

    data.to_csv("src/data/stock_data.csv", index=False)

    print("Multi-stock data saved!")