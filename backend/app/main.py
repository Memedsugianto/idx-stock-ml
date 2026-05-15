"""FastAPI entry: IDX/BEI data, fundamental & technical analysis, ML predictions, WebSocket ticks."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, HTTPException, Query, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app import analysis, data_service, logos, market, ml_models, ml_persist, ws_ticks

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="IDX Stock ML API", version="1.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    # Browsers forbid Access-Control-Allow-Origin: * together with credentials.
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class PredictRequest(BaseModel):
    symbol: str = Field(..., description="Ticker e.g. BBCA, TLKM, or IHSG")
    period: str = Field("2y", description="yfinance period: 1y, 2y, 5y, max")
    test_size: float = Field(0.2, ge=0.1, le=0.4)
    train: bool = Field(True, description="If false, load saved models and infer only (fast).")
    save: bool = Field(
        False,
        description="Persist trained models under STOCK_ML_MODEL_DIR for /predict with train=false.",
    )
    lstm_lookback: int = Field(20, ge=5, le=120)
    lstm_epochs: int = Field(60, ge=5, le=500)
    tf_epochs: int = Field(80, ge=5, le=500)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/market/movers")
def market_movers(limit: int = Query(5, ge=1, le=15)) -> dict[str, Any]:
    try:
        return market.fetch_movers(limit=limit)
    except Exception as e:  # noqa: BLE001
        logger.exception("movers failed")
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/logo/{symbol}")
def logo_image(symbol: str) -> Response:
    """Proxy logo image (avoids browser CORS) with TradingView / Yahoo fallbacks."""
    from urllib.error import URLError
    from urllib.request import Request, urlopen

    for url in logos.logo_candidates(symbol):
        try:
            req = Request(url, headers={"User-Agent": logos._FETCH_UA})
            with urlopen(req, timeout=12) as resp:
                data = resp.read()
                ctype = resp.headers.get("Content-Type", "image/svg+xml")
            return Response(content=data, media_type=ctype)
        except (URLError, TimeoutError, ValueError) as e:
            logger.debug("logo fetch fail %s: %s", url, e)
            continue
    raise HTTPException(status_code=404, detail=f"No logo for {symbol}")


@app.get("/quote/{symbol}")
def quote(symbol: str) -> dict[str, Any]:
    try:
        return data_service.fetch_quote(symbol)
    except Exception as e:  # noqa: BLE001
        logger.exception("quote failed")
        raise HTTPException(status_code=400, detail=str(e)) from e


@app.get("/history/{symbol}")
def history(symbol: str, period: str = "2y") -> dict[str, Any]:
    try:
        df = data_service.fetch_history(symbol, period=period)
        rows = [
            {
                "date": str(idx.date()) if hasattr(idx, "date") else str(idx),
                "open": float(r["Open"]),
                "high": float(r["High"]),
                "low": float(r["Low"]),
                "close": float(r["Close"]),
                "volume": float(r["Volume"]),
            }
            for idx, r in df.iterrows()
        ]
        return {"symbol": data_service.normalize_idx_symbol(symbol), "period": period, "rows": rows}
    except Exception as e:  # noqa: BLE001
        logger.exception("history failed")
        raise HTTPException(status_code=400, detail=str(e)) from e


@app.get("/analysis/fundamental/{symbol}")
def fundamental(symbol: str) -> dict[str, Any]:
    try:
        info = data_service.fetch_info(symbol)
        summary = analysis.fundamental_summary(info)
        summary["raw_info_keys"] = list(info.keys())[:40]
        summary["symbol"] = data_service.normalize_idx_symbol(symbol)
        return summary
    except Exception as e:  # noqa: BLE001
        logger.exception("fundamental failed")
        raise HTTPException(status_code=400, detail=str(e)) from e


@app.get("/analysis/technical/{symbol}")
def technical(symbol: str, period: str = "2y") -> dict[str, Any]:
    try:
        df = data_service.fetch_history(symbol, period=period)
        tech = analysis.technical_summary(df)
        tech["symbol"] = data_service.normalize_idx_symbol(symbol)
        return tech
    except Exception as e:  # noqa: BLE001
        logger.exception("technical failed")
        raise HTTPException(status_code=400, detail=str(e)) from e


@app.get("/predict/artifacts/{symbol}")
def predict_artifacts(symbol: str) -> dict[str, Any]:
    sym = data_service.normalize_idx_symbol(symbol)
    exists = ml_persist.artifacts_exist(sym)
    return {
        "symbol": sym,
        "artifacts_exist": exists,
        "path": str(ml_persist.artifact_root(sym)),
    }


@app.post("/predict")
def predict(body: PredictRequest) -> dict[str, Any]:
    try:
        sym = data_service.normalize_idx_symbol(body.symbol)
        df = data_service.fetch_history(body.symbol, period=body.period)

        if not body.train:
            try:
                out = ml_persist.infer_from_artifacts(sym, df)
            except FileNotFoundError as e:
                raise HTTPException(status_code=404, detail=str(e)) from e
            out["symbol"] = sym
            out["period"] = body.period
            return out

        out = ml_models.train_and_predict(
            df,
            test_size=body.test_size,
            tf_epochs=body.tf_epochs,
            lstm_lookback=body.lstm_lookback,
            lstm_epochs=body.lstm_epochs,
            persist=body.save,
            persist_symbol=sym if body.save else None,
        )
        out["symbol"] = sym
        out["period"] = body.period
        out["train"] = True
        out["saved"] = bool(body.save)
        return out
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        logger.exception("predict failed")
        raise HTTPException(status_code=500, detail=str(e)) from e


@app.websocket("/ws/ticks/{symbol}")
async def websocket_ticks(
    websocket: WebSocket,
    symbol: str,
    source: str = Query(
        "delayed_yfinance",
        description="delayed_yfinance | delayed | official_relay | official",
    ),
) -> None:
    await ws_ticks.handle_ticks_websocket(websocket, symbol, source)
