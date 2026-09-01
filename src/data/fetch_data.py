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
    tickers = [
        # Technology
        "AAPL",
        "MSFT",
        "NVDA",
        "AMD",
        "AVGO",
        "ORCL",
        "CSCO",
        "ADBE",

        # Communication Services
        "GOOGL",
        "META",
        "NFLX",
        "DIS",
        "CMCSA",

        # Consumer Discretionary
        "AMZN",
        "TSLA",
        "HD",
        "MCD",
        "NKE",
        "LOW",

        # Financials
        "JPM",
        "BAC",
        "GS",
        "V",
        "MA",
        "WFC",
        "C",
        
        # Healthcare
        "JNJ",
        "UNH",
        "LLY",
        "PFE",
        "ABBV",
        "MRK",

        # Industrials
        "CAT",
        "BA",
        "GE",
        "HON",
        "UPS",
        "RTX",

        # Consumer Staples
        "WMT",
        "PG",
        "KO",
        "PEP",
        "COST",

        # Energy
        "XOM",
        "CVX",
        "COP",

        # Utilities
        "NEE",
        "DUK"
    ]
    data = fetch_stock_data(tickers)

    data.to_csv("src/data/stock_data.csv", index=False)

    print("Multi-stock data saved!")
    