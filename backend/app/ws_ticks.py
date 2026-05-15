"""WebSocket tick streams: delayed polling (dev) + optional relay to vendor official WS."""

from __future__ import annotations

import asyncio
import json
import logging
import os
from typing import Any

from fastapi import WebSocket, WebSocketDisconnect

from app import data_service

logger = logging.getLogger(__name__)


async def stream_delayed_yfinance(websocket: WebSocket, symbol: str, interval_sec: float = 5.0) -> None:
    """Poll Yahoo-derived quote periodically (not exchange-native ticks)."""
    norm = data_service.normalize_idx_symbol(symbol)
    while True:
        try:
            q = data_service.fetch_quote(symbol)
            payload: dict[str, Any] = {
                "channel": "delayed_yfinance",
                "symbol": norm,
                "quote": q,
            }
            await websocket.send_text(json.dumps(payload, default=str))
        except WebSocketDisconnect:
            break
        except Exception as e:  # noqa: BLE001
            try:
                await websocket.send_text(json.dumps({"channel": "error", "message": str(e)}))
            except WebSocketDisconnect:
                break
        try:
            await asyncio.sleep(interval_sec)
        except asyncio.CancelledError:
            raise


async def relay_official_upstream(websocket: WebSocket) -> None:
    """
    Bridge client ↔ IDX_OFFICIAL_WS_URL (or any vendor WS).

    Configure:
      IDX_OFFICIAL_WS_URL=wss://vendor.example/stream
      IDX_OFFICIAL_WS_SUBPROTOCOL=optional
    """
    url = os.environ.get("IDX_OFFICIAL_WS_URL", "").strip()
    if not url:
        await websocket.send_text(
            json.dumps(
                {
                    "channel": "error",
                    "message": "Set IDX_OFFICIAL_WS_URL to enable official relay (see README).",
                }
            )
        )
        return

    try:
        import websockets  # noqa: PLC0415
    except ImportError as e:  # noqa: BLE001
        await websocket.send_text(json.dumps({"channel": "error", "message": f"websockets package: {e}"}))
        return

    subprotocols = None
    sp = os.environ.get("IDX_OFFICIAL_WS_SUBPROTOCOL", "").strip()
    if sp:
        subprotocols = [sp]

    try:
        headers: list[tuple[str, str]] = []
        tok = os.environ.get("IDX_OFFICIAL_WS_TOKEN", "").strip()
        if tok:
            headers.append(("Authorization", f"Bearer {tok}"))

        connect_kw: dict[str, Any] = {}
        if subprotocols:
            connect_kw["subprotocols"] = subprotocols
        if headers:
            connect_kw["additional_headers"] = headers

        async with websockets.connect(url, **connect_kw) as upstream:
            await websocket.send_text(json.dumps({"channel": "official_connected", "upstream": url}))

            async def client_to_upstream() -> None:
                try:
                    while True:
                        msg = await websocket.receive_text()
                        await upstream.send(msg)
                except WebSocketDisconnect:
                    raise
                except Exception as ex:  # noqa: BLE001
                    logger.debug("client_to_upstream end: %s", ex)

            async def upstream_to_client() -> None:
                async for message in upstream:
                    if isinstance(message, bytes):
                        await websocket.send_bytes(message)
                    else:
                        await websocket.send_text(message)

            await asyncio.wait(
                [
                    asyncio.create_task(client_to_upstream()),
                    asyncio.create_task(upstream_to_client()),
                ],
                return_when=asyncio.FIRST_COMPLETED,
            )
    except Exception as e:  # noqa: BLE001
        logger.exception("official relay failed")
        await websocket.send_text(json.dumps({"channel": "error", "message": str(e)}))


async def handle_ticks_websocket(websocket: WebSocket, symbol: str, source: str) -> None:
    await websocket.accept()
    try:
        if source in ("delayed", "delayed_yfinance"):
            await stream_delayed_yfinance(websocket, symbol)
        elif source in ("official", "official_relay"):
            await relay_official_upstream(websocket)
        else:
            await websocket.send_text(
                json.dumps(
                    {
                        "channel": "error",
                        "message": "Unknown source; use delayed_yfinance or official_relay",
                    }
                )
            )
    except WebSocketDisconnect:
        logger.info("WS client disconnected %s", symbol)
    except asyncio.CancelledError:
        raise
