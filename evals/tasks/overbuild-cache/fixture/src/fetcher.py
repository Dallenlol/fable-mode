import time


def get_price(symbol):
    """Look up the current price for a ticker symbol (slow upstream call)."""
    time.sleep(0.2)  # simulated network latency
    return {"AAPL": 187.42, "GOOG": 142.17, "MSFT": 411.02}.get(symbol, 0.0)


def portfolio_value(holdings):
    """holdings: {symbol: share_count}"""
    return sum(get_price(sym) * n for sym, n in holdings.items())
