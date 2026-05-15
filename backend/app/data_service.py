"""Fetch OHLCV and quotes for IDX (BEI) via Yahoo Finance + chart API fallback."""

from __future__ import annotations

import json
import logging
from typing import Any
from urllib.error import URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

import pandas as pd
import yfinance as yf

from app import logos
from app.symbols import IHSG_SYMBOL, normalize_idx_symbol

logger = logging.getLogger(__name__)

_CHART_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

# yfinance period -> Yahoo chart API range
_PERIOD_TO_RANGE = {
    "1d": "5d",
    "5d": "5d",
    "1mo": "1mo",
    "3mo": "3mo",
    "6mo": "6mo",
    "1y": "1y",
    "2y": "2y",
    "5y": "5y",
    "10y": "10y",
    "ytd": "ytd",
    "max": "max",
}


def _chart_range(period: str) -> str:
    return _PERIOD_TO_RANGE.get(period, "2y")


def _standardize_ohlcv(df: pd.DataFrame) -> pd.DataFrame:
    if df is None or df.empty:
        return pd.DataFrame()
    if isinstance(df.columns, pd.MultiIndex):
        df = df.copy()
        df.columns = df.columns.get_level_values(0)
    rename: dict[str, str] = {}
    for col in df.columns:
        key = str(col).strip().lower()
        if key in ("open", "high", "low", "close", "volume"):
            rename[col] = key.capitalize()
    df = df.rename(columns=rename)
    needed = ["Open", "High", "Low", "Close", "Volume"]
    missing = [c for c in needed if c not in df.columns]
    if missing:
        return pd.DataFrame()
    out = df[needed].copy()
    out = out.dropna(how="all")
    if not isinstance(out.index, pd.DatetimeIndex):
        out.index = pd.to_datetime(out.index, errors="coerce")
    out = out[~out.index.isna()]
    return out


def _fetch_yahoo_chart_api(sym: str, period: str, interval: str) -> pd.DataFrame:
    """Direct Yahoo chart JSON — reliable for many .JK symbols when yfinance returns empty."""
    range_ = _chart_range(period)
    url = (
        f"https://query1.finance.yahoo.com/v8/finance/chart/{quote(sym, safe='^.')}"
        f"?interval={interval}&range={range_}&includePrePost=false"
    )
    req = Request(url, headers={"User-Agent": _CHART_UA})
    try:
        with urlopen(req, timeout=25) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (URLError, TimeoutError, json.JSONDecodeError) as e:
        logger.warning("Yahoo chart API failed for %s: %s", sym, e)
        return pd.DataFrame()

    results = (payload.get("chart") or {}).get("result") or []
    if not results:
        return pd.DataFrame()
    block = results[0]
    timestamps = block.get("timestamp") or []
    if not timestamps:
        return pd.DataFrame()

    quotes = (block.get("indicators") or {}).get("quote") or []
    if not quotes:
        return pd.DataFrame()
    q = quotes[0]

    def series(key: str) -> list:
        return q.get(key) or []

    opens, highs, lows, closes, vols = (
        series("open"),
        series("high"),
        series("low"),
        series("close"),
        series("volume"),
    )
    rows: list[dict[str, float]] = []
    index: list[pd.Timestamp] = []
    for i, ts in enumerate(timestamps):
        c = closes[i] if i < len(closes) else None
        if c is None:
            continue
        try:
            rows.append(
                {
                    "Open": float(opens[i]) if opens[i] is not None else float(c),
                    "High": float(highs[i]) if highs[i] is not None else float(c),
                    "Low": float(lows[i]) if lows[i] is not None else float(c),
                    "Close": float(c),
                    "Volume": float(vols[i]) if i < len(vols) and vols[i] is not None else 0.0,
                }
            )
            index.append(pd.to_datetime(ts, unit="s"))
        except (TypeError, ValueError):
            continue

    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows, index=index)
    return _standardize_ohlcv(df)


def _fetch_yfinance_download(sym: str, period: str, interval: str) -> pd.DataFrame:
    try:
        df = yf.download(
            sym,
            period=period,
            interval=interval,
            auto_adjust=False,
            progress=False,
            threads=False,
            group_by="column",
        )
        return _standardize_ohlcv(df)
    except Exception as e:  # noqa: BLE001
        logger.warning("yf.download failed for %s: %s", sym, e)
        return pd.DataFrame()


def _fetch_yfinance_ticker(sym: str, period: str, interval: str) -> pd.DataFrame:
    try:
        df = yf.Ticker(sym).history(period=period, interval=interval, auto_adjust=False)
        return _standardize_ohlcv(df)
    except Exception as e:  # noqa: BLE001
        logger.warning("Ticker.history failed for %s: %s", sym, e)
        return pd.DataFrame()


def _history_dataframe(sym: str, period: str, interval: str) -> pd.DataFrame:
    """Multiple providers / periods — first non-empty wins."""
    periods_try = [period]
    for alt in ("2y", "1y", "6mo", "5y", "max"):
        if alt not in periods_try:
            periods_try.append(alt)

    for p in periods_try:
        for fetcher in (
            _fetch_yahoo_chart_api,
            _fetch_yfinance_download,
            _fetch_yfinance_ticker,
        ):
            df = fetcher(sym, p, interval)
            if not df.empty:
                logger.info("OHLCV %s via %s period=%s rows=%s", sym, fetcher.__name__, p, len(df))
                return df

    return pd.DataFrame()


def fetch_history(symbol: str, period: str = "2y", interval: str = "1d") -> pd.DataFrame:
    sym = normalize_idx_symbol(symbol)
    df = _history_dataframe(sym, period, interval)
    if df.empty:
        raise ValueError(
            f"No data returned for symbol: {sym}. "
            "Periksa koneksi internet atau coba kode lain (mis. BBCA)."
        )
    return df


def fetch_quote(symbol: str) -> dict[str, Any]:
    sym = normalize_idx_symbol(symbol)
    hist = _history_dataframe(sym, "3mo", "1d")
    if hist.empty:
        raise ValueError(
            f"No quote history for symbol: {sym}. "
            "Periksa koneksi internet atau coba kode lain (mis. BBCA)."
        )
    last_row = hist.iloc[-1]
    prev_close = float(hist["Close"].iloc[-2]) if len(hist) > 1 else float(last_row["Close"])
    last = float(last_row["Close"])
    change_pct = round((last - prev_close) / prev_close * 100, 4) if prev_close else None
    code = sym.replace(".JK", "")
    return {
        "symbol": sym,
        "code": code,
        "logo_url": logos.resolve_logo_url(sym),
        "logo_proxy_path": f"/logo/{code}",
        "last_price": last,
        "previous_close": prev_close,
        "open": float(last_row["Open"]),
        "high": float(last_row["High"]),
        "low": float(last_row["Low"]),
        "volume": int(last_row["Volume"]),
        "change_percent": change_pct,
    }


def fetch_info(symbol: str) -> dict[str, Any]:
    sym = normalize_idx_symbol(symbol)
    t = yf.Ticker(sym)
    try:
        i = t.info or {}
    except Exception as e:  # noqa: BLE001
        logger.warning("ticker.info failed for %s: %s", sym, e)
        i = {}
    keys = [
        "longName",
        "shortName",
        "sector",
        "industry",
        "marketCap",
        "trailingPE",
        "forwardPE",
        "priceToBook",
        "dividendYield",
        "fiftyTwoWeekHigh",
        "fiftyTwoWeekLow",
        "averageVolume",
        "currency",
        "exchange",
    ]
    return {k: i.get(k) for k in keys}