"""Save / load trained models for fast inference without retraining."""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

DEFAULT_MODEL_DIR = Path(os.environ.get("STOCK_ML_MODEL_DIR", "saved_models"))


def safe_symbol_dir(symbol: str) -> str:
    return symbol.replace("^", "IDXCOMP_").replace("/", "_").replace(".", "_")


def artifact_root(symbol: str, base: Path | None = None) -> Path:
    root = base or DEFAULT_MODEL_DIR
    return root / safe_symbol_dir(symbol)


def meta_path(symbol: str, base: Path | None = None) -> Path:
    return artifact_root(symbol, base) / "meta.json"


def artifacts_exist(symbol: str, base: Path | None = None) -> bool:
    p = meta_path(symbol, base)
    return p.is_file()


def read_meta(symbol: str, base: Path | None = None) -> dict[str, Any]:
    with meta_path(symbol, base).open(encoding="utf-8") as f:
        return json.load(f)


def save_meta(symbol: str, meta: dict[str, Any], base: Path | None = None) -> None:
    d = artifact_root(symbol, base)
    d.mkdir(parents=True, exist_ok=True)
    with (d / "meta.json").open("w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)


def save_sklearn_bundle(
    symbol: str,
    scaler,
    lr,
    dt,
    rf,
    mlp,
    base: Path | None = None,
) -> None:
    d = artifact_root(symbol, base)
    d.mkdir(parents=True, exist_ok=True)
    joblib.dump(scaler, d / "tabular_scaler.joblib")
    joblib.dump(lr, d / "linear.joblib")
    joblib.dump(dt, d / "decision_tree.joblib")
    joblib.dump(rf, d / "random_forest.joblib")
    joblib.dump(mlp, d / "mlp_ann.joblib")
    logger.info("Saved sklearn bundle to %s", d)


def save_keras_models(
    symbol: str,
    dense_ann,
    lstm_model,
    lstm_scaler,
    base: Path | None = None,
) -> None:
    d = artifact_root(symbol, base)
    d.mkdir(parents=True, exist_ok=True)
    if dense_ann is not None:
        dense_ann.save(d / "dense_ann.keras")
    if lstm_model is not None:
        lstm_model.save(d / "lstm.keras")
    if lstm_scaler is not None:
        joblib.dump(lstm_scaler, d / "lstm_frame_scaler.joblib")
    logger.info("Saved Keras / LSTM artifacts to %s", d)


def load_sklearn_bundle(symbol: str, base: Path | None = None):
    d = artifact_root(symbol, base)
    scaler = joblib.load(d / "tabular_scaler.joblib")
    lr = joblib.load(d / "linear.joblib")
    dt = joblib.load(d / "decision_tree.joblib")
    rf = joblib.load(d / "random_forest.joblib")
    mlp = joblib.load(d / "mlp_ann.joblib")
    return scaler, lr, dt, rf, mlp


def load_keras_models(symbol: str, base: Path | None = None):
    try:
        from tensorflow import keras  # noqa: PLC0415
    except ImportError:
        logger.warning("TensorFlow not installed; skipping Keras model load.")
        return None, None, None

    d = artifact_root(symbol, base)
    dense_path = d / "dense_ann.keras"
    lstm_path = d / "lstm.keras"
    lstm_scaler_path = d / "lstm_frame_scaler.joblib"
    dense_ann = keras.models.load_model(dense_path) if dense_path.is_file() else None
    lstm_model = keras.models.load_model(lstm_path) if lstm_path.is_file() else None
    lstm_scaler = joblib.load(lstm_scaler_path) if lstm_scaler_path.is_file() else None
    return dense_ann, lstm_model, lstm_scaler


def infer_from_artifacts(
    symbol: str,
    df: pd.DataFrame,
    base: Path | None = None,
) -> dict[str, Any]:
    """Load saved models and predict next close from latest OHLCV row / window."""
    if not artifacts_exist(symbol, base):
        raise FileNotFoundError(f"No saved models for {symbol}. Train with save=true first.")

    meta = read_meta(symbol, base)
    lookback = int(meta.get("lstm_lookback", 20))

    scaler, lr, dt, rf, mlp = load_sklearn_bundle(symbol, base)
    dense_ann, lstm_model, lstm_scaler = load_keras_models(symbol, base)

    last_X = df[["Open", "High", "Low", "Close", "Volume"]].astype(float).iloc[-1].values.reshape(1, -1)
    last_X_s = scaler.transform(last_X)

    out: dict[str, Any] = {"models": {}, "symbol": symbol, "mode": "infer_saved", "meta": meta}

    out["models"]["linear_regression_sklearn"] = {"next_close_prediction": float(lr.predict(last_X_s)[0])}
    out["models"]["decision_tree_regression"] = {"next_close_prediction": float(dt.predict(last_X_s)[0])}
    out["models"]["random_forest_regression"] = {"next_close_prediction": float(rf.predict(last_X_s)[0])}
    out["models"]["ann_mlp_sklearn"] = {"next_close_prediction": float(mlp.predict(last_X_s)[0])}

    if dense_ann is not None:
        p = float(dense_ann.predict(last_X_s, verbose=0).flatten()[0])
        out["models"]["tensorflow_keras_ann"] = {"next_close_prediction": p}
    else:
        out["models"]["tensorflow_keras_ann"] = {"error": "dense_ann.keras missing"}

    if lstm_model is not None and lstm_scaler is not None and len(df) >= lookback:
        tail = df[["Open", "High", "Low", "Close", "Volume"]].astype(float).iloc[-lookback:].values
        tail_s = lstm_scaler.transform(tail).reshape(1, lookback, 5)
        p_lstm = float(lstm_model.predict(tail_s, verbose=0).flatten()[0])
        out["models"]["tensorflow_lstm"] = {"next_close_prediction": p_lstm}
    else:
        out["models"]["tensorflow_lstm"] = {
            "error": "LSTM artifacts missing or insufficient history for lookback"
        }

    preds = [
        out["models"]["linear_regression_sklearn"]["next_close_prediction"],
        out["models"]["decision_tree_regression"]["next_close_prediction"],
        out["models"]["random_forest_regression"]["next_close_prediction"],
        out["models"]["ann_mlp_sklearn"]["next_close_prediction"],
    ]
    m_tf = out["models"].get("tensorflow_keras_ann", {})
    if "next_close_prediction" in m_tf:
        preds.append(m_tf["next_close_prediction"])
    m_ls = out["models"].get("tensorflow_lstm", {})
    if "next_close_prediction" in m_ls:
        preds.append(m_ls["next_close_prediction"])

    out["ensemble_next_close"] = float(np.mean(preds))
    out["last_row_features"] = {
        "open": float(last_X[0, 0]),
        "high": float(last_X[0, 1]),
        "low": float(last_X[0, 2]),
        "close": float(last_X[0, 3]),
        "volume": float(last_X[0, 4]),
    }
    out["disclaimer"] = (
        "Inference from saved models only; not investment advice. "
        "Retrain periodically as markets drift."
    )
    return out
