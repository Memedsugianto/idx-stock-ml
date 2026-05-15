"""Resolve company logo URLs for IDX listings (Yahoo + TradingView symbol CDN)."""

from __future__ import annotations

import logging
from typing import Any

import yfinance as yf

from app.symbols import IHSG_SYMBOL, normalize_idx_symbol

logger = logging.getLogger(__name__)

_FETCH_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


def ticker_code(symbol: str) -> str:
    sym = normalize_idx_symbol(symbol)
    if sym == IHSG_SYMBOL:
        return "IHSG"
    return sym.replace(".JK", "").upper()


def _yahoo_logo_url(yf_symbol: str) -> str | None:
    try:
        info: dict[str, Any] = yf.Ticker(yf_symbol).info or {}
    except Exception as e:  # noqa: BLE001
        logger.debug("yahoo logo info %s: %s", yf_symbol, e)
        return None
    for key in ("logo_url", "companyLogoUrl"):
        val = info.get(key)
        if isinstance(val, str) and val.startswith("http"):
            return val
    branding = info.get("branding")
    if isinstance(branding, dict):
        for key in ("logo", "icon", "squareLogo"):
            val = branding.get(key)
            if isinstance(val, str) and val.startswith("http"):
                return val
    return None


def resolve_logo_url(symbol: str) -> str | None:
    """
    Best-effort logo URL for an IDX ticker.
    TradingView hosts many IDX issuer marks used on charting (not official IDX assets).
    """
    sym = normalize_idx_symbol(symbol)
    code = ticker_code(symbol)

    if code == "IHSG":
        return "https://s3-symbol-logo.tradingview.com/indices-jakarta-composite--big.svg"

    yahoo = _yahoo_logo_url(sym)
    if yahoo:
        return yahoo

    c = code.lower()
    return f"https://s3-symbol-logo.tradingview.com/idx-{c}--big.svg"


def logo_candidates(symbol: str) -> list[str]:
    """Ordered fallbacks for proxy endpoint."""
    sym = normalize_idx_symbol(symbol)
    code = ticker_code(symbol)
    out: list[str] = []
    y = _yahoo_logo_url(sym)
    if y:
        out.append(y)
    if code == "IHSG":
        out.extend(
            [
                "https://s3-symbol-logo.tradingview.com/indices-jakarta-composite--big.svg",
                "https://s3-symbol-logo.tradingview.com/indices-jakarta-composite.svg",
            ]
        )
    else:
        c = code.lower()
        out.extend(
            [
                f"https://s3-symbol-logo.tradingview.com/idx-{c}--big.svg",
                f"https://s3-symbol-logo.tradingview.com/idx-{c}.svg",
                f"https://s3-symbol-logo.tradingview.com/idx-{c}.png",
            ]
        )
    seen: set[str] = set()
    unique: list[str] = []
    for u in out:
        if u not in seen:
            seen.add(u)
            unique.append(u)
    return unique
