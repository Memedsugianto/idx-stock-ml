"""Fundamental (from yfinance info) and technical indicators from OHLCV."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd


def _sma(series: pd.Series, window: int) -> pd.Series:
    return series.rolling(window=window, min_periods=1).mean()


def _ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()


def rsi(close: pd.Series, period: int = 14) -> pd.Series:
    delta = close.diff()
    gain = delta.where(delta > 0, 0.0)
    loss = (-delta).where(delta < 0, 0.0)
    avg_gain = gain.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / period, min_periods=period, adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0, np.nan)
    return 100 - (100 / (1 + rs))


def macd(close: pd.Series, fast: int = 12, slow: int = 26, signal: int = 9) -> tuple[pd.Series, pd.Series, pd.Series]:
    ema_fast = _ema(close, fast)
    ema_slow = _ema(close, slow)
    line = ema_fast - ema_slow
    sig = _ema(line, signal)
    hist = line - sig
    return line, sig, hist


def technical_summary(df: pd.DataFrame) -> dict[str, Any]:
    close = df["Close"].astype(float)
    high = df["High"].astype(float)
    low = df["Low"].astype(float)
    vol = df["Volume"].astype(float)

    r = rsi(close)
    macd_line, macd_signal, macd_hist = macd(close)
    sma20 = _sma(close, 20)
    sma50 = _sma(close, 50)

    last = close.iloc[-1]
    last_rsi = float(r.iloc[-1]) if pd.notna(r.iloc[-1]) else None
    last_macd = float(macd_line.iloc[-1]) if pd.notna(macd_line.iloc[-1]) else None
    last_sig = float(macd_signal.iloc[-1]) if pd.notna(macd_signal.iloc[-1]) else None

    trend = "neutral"
    if len(sma20) and len(sma50) and pd.notna(sma20.iloc[-1]) and pd.notna(sma50.iloc[-1]):
        if sma20.iloc[-1] > sma50.iloc[-1]:
            trend = "bullish_ma"
        elif sma20.iloc[-1] < sma50.iloc[-1]:
            trend = "bearish_ma"

    rsi_signal = "neutral"
    if last_rsi is not None:
        if last_rsi >= 70:
            rsi_signal = "overbought"
        elif last_rsi <= 30:
            rsi_signal = "oversold"

    recent = [
        {
            "date": str(idx.date()) if hasattr(idx, "date") else str(idx),
            "open": float(row["Open"]),
            "high": float(row["High"]),
            "low": float(row["Low"]),
            "close": float(row["Close"]),
            "volume": float(row["Volume"]),
            "rsi14": float(r.loc[idx]) if pd.notna(r.loc[idx]) else None,
            "sma20": float(sma20.loc[idx]) if pd.notna(sma20.loc[idx]) else None,
            "sma50": float(sma50.loc[idx]) if pd.notna(sma50.loc[idx]) else None,
        }
        for idx, row in df.tail(60).iterrows()
    ]

    return {
        "last_close": float(last),
        "rsi14": last_rsi,
        "rsi_signal": rsi_signal,
        "macd": last_macd,
        "macd_signal": last_sig,
        "macd_histogram": float(macd_hist.iloc[-1]) if pd.notna(macd_hist.iloc[-1]) else None,
        "sma20": float(sma20.iloc[-1]) if pd.notna(sma20.iloc[-1]) else None,
        "sma50": float(sma50.iloc[-1]) if pd.notna(sma50.iloc[-1]) else None,
        "ma_cross_trend": trend,
        "recent_ohlcv_indicators": recent,
    }


def fundamental_summary(info: dict[str, Any]) -> dict[str, Any]:
    """Map yfinance info keys to a compact fundamental view."""

    def num(v: Any) -> float | None:
        if v is None or (isinstance(v, float) and np.isnan(v)):
            return None
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    pe = num(info.get("trailingPE"))
    pb = num(info.get("priceToBook"))
    mcap = num(info.get("marketCap"))
    dy = num(info.get("dividendYield"))
    if dy is not None and dy <= 1.0:
        dy = dy * 100.0

    score_notes: list[str] = []
    if pe is not None:
        if pe < 12:
            score_notes.append("Trailing P/E below 12 (value-leaning; verify quality).")
        elif pe > 35:
            score_notes.append("High trailing P/E (growth expectations or stretched valuation).")
    if pb is not None and pb < 1.5:
        score_notes.append("Moderate/low price-to-book vs many financials; context-dependent.")

    return {
        "name": info.get("longName") or info.get("shortName"),
        "sector": info.get("sector"),
        "industry": info.get("industry"),
        "market_cap": mcap,
        "trailing_pe": pe,
        "forward_pe": num(info.get("forwardPE")),
        "price_to_book": pb,
        "dividend_yield_percent": dy,
        "fifty_two_week_high": num(info.get("fiftyTwoWeekHigh")),
        "fifty_two_week_low": num(info.get("fiftyTwoWeekLow")),
        "currency": info.get("currency"),
        "exchange": info.get("exchange"),
        "interpretation_notes": score_notes,
    }
