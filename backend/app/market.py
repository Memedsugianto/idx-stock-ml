"""Top gainers / losers from a liquid IDX watch universe (Yahoo delayed quotes)."""

from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from typing import Any

from app import data_service

logger = logging.getLogger(__name__)

# Liquid / large-cap IDX tickers (without .JK suffix)
LIQUID_IDX_TICKERS = [
    "BBCA",
    "BBRI",
    "BMRI",
    "TLKM",
    "ASII",
    "UNVR",
    "GOTO",
    "ANTM",
    "ADRO",
    "ICBP",
    "KLBF",
    "MDKA",
    "SMGR",
    "PTBA",
    "CPIN",
    "INDF",
    "TOWR",
    "EXCL",
    "ACES",
    "MNCN",
    "BBNI",
    "BRIS",
    "PGAS",
    "JSMR",
    "INCO",
]


def _quote_row(symbol: str) -> dict[str, Any] | None:
    try:
        q = data_service.fetch_quote(symbol)
        code = symbol.replace(".JK", "")
        return {
            "symbol": q["symbol"],
            "code": code,
            "logo_url": q.get("logo_url"),
            "logo_proxy_path": q.get("logo_proxy_path") or f"/logo/{code}",
            "last_price": q["last_price"],
            "change_percent": q.get("change_percent"),
            "volume": q.get("volume"),
        }
    except Exception as e:  # noqa: BLE001
        logger.debug("quote skip %s: %s", symbol, e)
        return None


def fetch_movers(limit: int = 5, universe: list[str] | None = None) -> dict[str, Any]:
    tickers = universe or LIQUID_IDX_TICKERS
    rows: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(_quote_row, t): t for t in tickers}
        for fut in as_completed(futures):
            row = fut.result()
            if row is not None and row.get("change_percent") is not None:
                rows.append(row)

    rows.sort(key=lambda r: r["change_percent"], reverse=True)
    gainers = rows[:limit]
    losers = list(reversed(rows[-limit:])) if len(rows) >= limit else list(reversed(rows))

    return {
        "gainers": gainers,
        "losers": losers,
        "scanned": len(tickers),
        "ok_count": len(rows),
        "as_of": datetime.now(timezone.utc).isoformat(),
    }
