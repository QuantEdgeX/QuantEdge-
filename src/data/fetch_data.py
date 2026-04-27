import yfinance as yf
import pandas as pd

def fetch_stock_data(ticker="AAPL", start="2020-01-01", end="2024-01-01"):
    df = yf.download(ticker, start=start, end=end)

    # Remove multi-index columns if present
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)

    df.reset_index(inplace=True)
    return df

if __name__ == "__main__":
    data = fetch_stock_data("AAPL")
    data.to_csv("data/stock_data.csv", index=False)
    print("Clean data saved!")