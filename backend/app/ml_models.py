"""Train regression + LSTM models; optional persistence for fast inference."""

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeRegressor

from app import ml_persist

logger = logging.getLogger(__name__)

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

try:
    import tensorflow as tf  # noqa: F401
    from tensorflow import keras
    from tensorflow.keras import layers

    _HAS_TF = True
except Exception as e:  # noqa: BLE001
    logger.warning("TensorFlow not available: %s", e)
    _HAS_TF = False


def build_supervised_frame(df: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    data = df[["Open", "High", "Low", "Close", "Volume"]].astype(float).copy()
    data["Target"] = data["Close"].shift(-1)
    data = data.dropna()
    X = data[["Open", "High", "Low", "Close", "Volume"]].values
    y = data["Target"].values
    return X, y


def build_lstm_xy(df: pd.DataFrame, lookback: int) -> tuple[np.ndarray, np.ndarray]:
    """Window of `lookback` daily OHLCV rows ending before day t; target = Close on day t."""
    raw = df[["Open", "High", "Low", "Close", "Volume"]].astype(float).values
    xs: list[np.ndarray] = []
    ys: list[float] = []
    for t in range(lookback, len(raw)):
        xs.append(raw[t - lookback : t].copy())
        ys.append(float(raw[t, 3]))
    if not xs:
        return np.empty((0, lookback, 5)), np.empty((0,))
    return np.stack(xs, axis=0), np.array(ys, dtype=np.float64)


def _metrics(y_true: np.ndarray, y_pred: np.ndarray) -> dict[str, float]:
    mae = float(mean_absolute_error(y_true, y_pred))
    mse = float(mean_squared_error(y_true, y_pred))
    rmse = float(np.sqrt(mse))
    return {"mae": mae, "rmse": rmse}


def train_and_predict(
    df: pd.DataFrame,
    test_size: float = 0.2,
    random_state: int = 42,
    tf_epochs: int = 80,
    tf_batch_size: int = 32,
    lstm_lookback: int = 20,
    lstm_epochs: int = 60,
    lstm_batch_size: int = 16,
    persist: bool = False,
    persist_symbol: str | None = None,
    model_base_dir: Path | None = None,
) -> dict[str, Any]:
    X, y = build_supervised_frame(df)
    if len(X) < 30:
        raise ValueError("Not enough rows to train models (need >= 30).")

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, shuffle=False
    )
    scaler = StandardScaler()
    X_train_s = scaler.fit_transform(X_train)
    X_test_s = scaler.transform(X_test)

    results: dict[str, Any] = {
        "models": {},
        "ensemble_next_close": None,
        "last_row_features": {},
        "mode": "train_fresh",
    }

    last_X = df[["Open", "High", "Low", "Close", "Volume"]].astype(float).iloc[-1].values.reshape(1, -1)
    last_X_s = scaler.transform(last_X)

    dense_ann = None
    lstm_model = None
    lstm_scaler: StandardScaler | None = None

    lr = LinearRegression()
    lr.fit(X_train_s, y_train)
    pred_lr = lr.predict(X_test_s)
    p_next_lr = float(lr.predict(last_X_s)[0])
    results["models"]["linear_regression_sklearn"] = {
        "test_metrics": _metrics(y_test, pred_lr),
        "next_close_prediction": p_next_lr,
    }

    dt = DecisionTreeRegressor(max_depth=8, random_state=random_state)
    dt.fit(X_train_s, y_train)
    pred_dt = dt.predict(X_test_s)
    p_next_dt = float(dt.predict(last_X_s)[0])
    results["models"]["decision_tree_regression"] = {
        "test_metrics": _metrics(y_test, pred_dt),
        "next_close_prediction": p_next_dt,
    }

    rf = RandomForestRegressor(
        n_estimators=200,
        max_depth=12,
        random_state=random_state,
        n_jobs=-1,
    )
    rf.fit(X_train_s, y_train)
    pred_rf = rf.predict(X_test_s)
    p_next_rf = float(rf.predict(last_X_s)[0])
    results["models"]["random_forest_regression"] = {
        "test_metrics": _metrics(y_test, pred_rf),
        "next_close_prediction": p_next_rf,
    }

    mlp = MLPRegressor(
        hidden_layer_sizes=(64, 32),
        activation="relu",
        max_iter=500,
        random_state=random_state,
        early_stopping=True,
    )
    mlp.fit(X_train_s, y_train)
    pred_mlp = mlp.predict(X_test_s)
    p_next_mlp = float(mlp.predict(last_X_s)[0])
    results["models"]["ann_mlp_sklearn"] = {
        "test_metrics": _metrics(y_test, pred_mlp),
        "next_close_prediction": p_next_mlp,
    }

    p_next_dense = None
    if _HAS_TF and len(X_train_s) >= 20:
        keras.utils.set_random_seed(random_state)
        dense_ann = keras.Sequential(
            [
                layers.Input(shape=(X_train_s.shape[1],)),
                layers.Dense(48, activation="relu"),
                layers.Dense(24, activation="relu"),
                layers.Dense(1),
            ]
        )
        dense_ann.compile(optimizer=keras.optimizers.Adam(1e-3), loss="mse")
        dense_ann.fit(
            X_train_s,
            y_train,
            validation_split=0.15,
            epochs=tf_epochs,
            batch_size=tf_batch_size,
            verbose=0,
        )
        pred_tf = dense_ann.predict(X_test_s, verbose=0).flatten()
        p_next_dense = float(dense_ann.predict(last_X_s, verbose=0).flatten()[0])
        results["models"]["tensorflow_keras_ann"] = {
            "test_metrics": _metrics(y_test, pred_tf),
            "next_close_prediction": p_next_dense,
        }
    else:
        results["models"]["tensorflow_keras_ann"] = {
            "error": "TensorFlow unavailable or insufficient data",
            "test_metrics": None,
            "next_close_prediction": None,
        }

    p_next_lstm = None
    if _HAS_TF and len(df) >= lstm_lookback + 35:
        X_seq, y_seq = build_lstm_xy(df, lstm_lookback)
        if len(X_seq) >= 40:
            k = max(int(len(X_seq) * (1 - test_size)), lstm_lookback + 5)
            Xtr, Xte = X_seq[:k], X_seq[k:]
            ytr, yte = y_seq[:k], y_seq[k:]
            lstm_scaler = StandardScaler()
            lstm_scaler.fit(Xtr.reshape(-1, 5))
            Xtr_s = lstm_scaler.transform(Xtr.reshape(-1, 5)).reshape(Xtr.shape[0], lstm_lookback, 5)
            Xte_s = lstm_scaler.transform(Xte.reshape(-1, 5)).reshape(Xte.shape[0], lstm_lookback, 5)

            keras.utils.set_random_seed(random_state)
            lstm_model = keras.Sequential(
                [
                    layers.Input(shape=(lstm_lookback, 5)),
                    layers.LSTM(48, return_sequences=False),
                    layers.Dense(24, activation="relu"),
                    layers.Dense(1),
                ]
            )
            lstm_model.compile(optimizer=keras.optimizers.Adam(1e-3), loss="mse")
            lstm_model.fit(
                Xtr_s,
                ytr,
                validation_split=0.12,
                epochs=lstm_epochs,
                batch_size=lstm_batch_size,
                verbose=0,
            )
            pred_ls = lstm_model.predict(Xte_s, verbose=0).flatten()
            tail = (
                df[["Open", "High", "Low", "Close", "Volume"]]
                .astype(float)
                .iloc[-lstm_lookback:]
                .values
            )
            tail_s = lstm_scaler.transform(tail).reshape(1, lstm_lookback, 5)
            p_next_lstm = float(lstm_model.predict(tail_s, verbose=0).flatten()[0])
            results["models"]["tensorflow_lstm"] = {
                "test_metrics": _metrics(yte, pred_ls),
                "next_close_prediction": p_next_lstm,
                "lookback_days": lstm_lookback,
            }
        else:
            results["models"]["tensorflow_lstm"] = {
                "error": "Not enough LSTM sequence samples",
                "next_close_prediction": None,
            }
    else:
        results["models"]["tensorflow_lstm"] = {
            "error": "TensorFlow unavailable or insufficient history for LSTM",
            "next_close_prediction": None,
        }

    preds = [p_next_lr, p_next_dt, p_next_rf, p_next_mlp]
    if p_next_dense is not None:
        preds.append(p_next_dense)
    if p_next_lstm is not None:
        preds.append(p_next_lstm)
    results["ensemble_next_close"] = float(np.mean(preds))
    results["last_row_features"] = {
        "open": float(last_X[0, 0]),
        "high": float(last_X[0, 1]),
        "low": float(last_X[0, 2]),
        "close": float(last_X[0, 3]),
        "volume": float(last_X[0, 4]),
    }
    results["disclaimer"] = (
        "Educational prototype only. Not investment advice. "
        "Market data may be delayed; verify with IDX / your broker."
    )

    if persist and persist_symbol:
        base = model_base_dir
        ml_persist.save_sklearn_bundle(persist_symbol, scaler, lr, dt, rf, mlp, base)
        ml_persist.save_keras_models(persist_symbol, dense_ann, lstm_model, lstm_scaler, base)
        meta: dict[str, Any] = {
            "normalized_symbol": persist_symbol,
            "lstm_lookback": lstm_lookback,
            "saved_at": datetime.now(timezone.utc).isoformat(),
            "tabular_target": "next_close_from_same_day_ohlcv",
            "lstm_target": "close_at_day_t_from_window_ending_t_minus_1",
        }
        ml_persist.save_meta(persist_symbol, meta, base)
        results["saved_artifacts"] = {
            "path": str(ml_persist.artifact_root(persist_symbol, base)),
            "symbol": persist_symbol,
        }

    return results
