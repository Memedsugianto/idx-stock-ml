# IDX Stock ML

Flutter GUI + Python **FastAPI** backend for Indonesian stocks (**BEI/IDX**) and **IHSG** (IDX Composite), with **fundamental** and **technical** study views and **regression / ANN** models:

| Model | Library |
|--------|---------|
| Linear regression | scikit-learn `LinearRegression` |
| Decision tree regression | scikit-learn `DecisionTreeRegressor` |
| Random forest regression | scikit-learn `RandomForestRegressor` |
| ANN (MLP) | scikit-learn `MLPRegressor` |
| ANN (dense network) | **TensorFlow / Keras** `Sequential` |
| LSTM sequence model | **TensorFlow / Keras** `LSTM` + `Dense` |

**Data source:** [yfinance](https://github.com/ranaroussi/yfinance) uses Yahoo Finance symbols: `BBCA.JK`, `^JKSE` for IHSG, etc. This is **not** a licensed IDX real-time vendor feed; delays and gaps can occur. For production “BEI real-time”, integrate [IDX official data products](https://www.idx.co.id) or a broker API.

### Model persistence (fast inference)

- Train once with `POST /predict` and **`"save": true`**. Artifacts are written under `STOCK_ML_MODEL_DIR` (default `./saved_models/<symbol_slug>/`): `tabular_scaler.joblib`, sklearn models, `dense_ann.keras`, `lstm.keras`, `lstm_frame_scaler.joblib`, `meta.json`.
- Later, call **`POST /predict`** with **`"train": false`** (same `symbol` / `period` for fresh OHLCV tail). The server reloads weights and returns predictions **without** retraining.
- `GET /predict/artifacts/{symbol}` — whether a saved bundle exists and its folder path.

### WebSocket ticks

- **`WS /ws/ticks/{symbol}?source=delayed_yfinance`** — server polls delayed quotes every ~5s and pushes JSON (dev / demo; not exchange-native ticks).
- **`WS /ws/ticks/{symbol}?source=official_relay`** — transparent bridge to a **vendor** WebSocket (your licensed IDX/broker feed). Set environment variables on the API host:
  - `IDX_OFFICIAL_WS_URL` — e.g. `wss://vendor.example/stream`
  - `IDX_OFFICIAL_WS_TOKEN` — optional `Authorization: Bearer …`
  - `IDX_OFFICIAL_WS_SUBPROTOCOL` — optional subprotocol name
  You must adapt message format client-side to your vendor’s schema (subscription messages, heartbeats, etc.).

The Flutter app tab **Live** connects to this WebSocket (`ws://` / `wss://` derived from the API base URL).

## Backend (Python)

**Gunakan Python 3.12 atau 3.13.** Python **3.14** sering gagal membangun `pydantic-core` (Rust / PyO3: *newer than PyO3's maximum supported version*) karena belum ada wheel resmi — bukan bug proyek ini.

### Windows (disarankan): buat ulang venv dengan Python 3.12

```powershell
cd stock_predictor\backend
rmdir /s /q .venv
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Jika `py -3.12` tidak ada, instal [Python 3.12](https://www.python.org/downloads/) dan centang **Add to PATH**, atau pakai path penuh ke `python.exe` 3.12.

### Workaround eksperimental (tetap di Python 3.14)

Mungkin berhasil memaksa build `pydantic-core` dari sumber (tidak dijamin stabil):

```powershell
$env:PYO3_USE_ABI3_FORWARD_COMPATIBILITY = "1"
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

### Versi Python lain

```bash
cd stock_predictor/backend
python3.12 -m venv .venv   # Linux/macOS
source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Open `http://127.0.0.1:8000/docs` for Swagger.

### API overview

- `GET /quote/{symbol}` — latest daily bar fields (open, high, low, close, volume) and change %.
- `GET /history/{symbol}?period=2y` — OHLCV series.
- `GET /analysis/fundamental/{symbol}` — condensed `yfinance` fundamentals (P/E, P/B, market cap, …).
- `GET /analysis/technical/{symbol}` — RSI(14), MACD, SMA20/50, recent table.
- `POST /predict` — body fields:
  - `symbol`, `period`, `test_size`
  - **`train`** (default `true`) — `false` = load saved models and **infer only** (404 if never saved with `save: true`).
  - **`save`** (default `false`) — after training, persist artifacts for fast inference.
  - `lstm_lookback`, `lstm_epochs`, `tf_epochs` — training knobs.
- `GET /predict/artifacts/{symbol}` — saved bundle status.

### TensorFlow install issues

TensorFlow **2.18.x** requires **NumPy older than 2.1** (for example 2.0.x). Installing `numpy==2.1.x` next to TensorFlow makes pip fail with `ResolutionImpossible`. This repo pins `numpy>=1.26,<2.1` in `requirements.txt` for that reason.

If TensorFlow fails on your platform, install a build matching [tensorflow.org](https://www.tensorflow.org/install) for your Python version, or temporarily remove TensorFlow and rely on the sklearn models (the API will report `tensorflow_keras_ann` as unavailable).

## Satu klik dari Desktop (Windows)

1. **Setup sekali** (jika `.venv` belum ada):
   ```powershell
   cd stock_predictor\scripts
   .\setup_backend.bat
   ```
   Di folder `flutter_app` sekali juga: `flutter pub get` (dan `flutter create .` jika belum).

2. **Buat ikon Desktop**:
   ```powershell
   cd stock_predictor\scripts
   powershell -ExecutionPolicy Bypass -File .\create_desktop_shortcut.ps1
   ```

3. **Double-click** shortcut **「IDX Stock ML」** di Desktop:
   - Jendela 1: backend API (`uvicorn` port 8000)
   - Jendela 2: `flutter run -d chrome` (Chrome terbuka otomatis)

Atau jalankan langsung: `stock_predictor\scripts\start_app.bat`

## Flutter app

From `stock_predictor/flutter_app`:

```bash
flutter create . --project-name idx_stock_ml
flutter pub get
flutter run
```

Set **API base URL** in the app:

| Target | Typical base URL |
|--------|-------------------|
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator / desktop | `http://127.0.0.1:8000` |
| Physical phone | `http://<your-PC-LAN-IP>:8000` |

Checkboxes:

- **Fast infer** — `train: false` (requires models saved once with **Save models after training**).
- **Save models after training** — `save: true` on the next training run.

Tab **Live** opens a WebSocket to `/ws/ticks/{symbol}`.

**Android cleartext HTTP:** after `flutter create`, set `android:usesCleartextTraffic="true"` on the `<application>` tag in `android/app/src/main/AndroidManifest.xml` for local HTTP dev, or serve the API over HTTPS.

## Symbols

- **Stock:** `BBCA`, `TLKM`, `BMRI` (backend appends `.JK`).
- **IHSG / IDX Composite:** enter `IHSG`, `JKSE`, or `^JKSE`.

### Konfigurasi repo

Edit `scripts/github.config.ps1` jika perlu:

| Setting | Default |
|---------|---------|
| `GitHubUser` | `Memedsugianto` |
| `RepoName` | `idx-stock-ml` |
| `Visibility` | `public` |

URL hasil: `https://github.com/Memedsugianto/idx-stock-ml`

### Satu klik (Windows)

```powershell
cd stock_predictor\scripts
.\publish_to_github.bat
```

Atau PowerShell langsung:

```powershell
cd stock_predictor\scripts
powershell -ExecutionPolicy Bypass -File .\publish_to_github.ps1
```

Opsi tambahan:

```powershell
# Repo privat
.\publish_to_github.ps1 -Visibility private

# Nama repo lain
.\publish_to_github.ps1 -RepoName stock-predictor-idx

# Hanya commit + push (repo sudah dibuat di GitHub)
.\publish_to_github.ps1 -SkipCreate

# Lihat alur tanpa menjalankan push
.\publish_to_github.ps1 -DryRun
```

Setelah berhasil, clone di mesin lain:

```powershell
git clone https://github.com/Memedsugianto/idx-stock-ml.git
cd idx-stock-ml
scripts\setup_backend.bat
cd flutter_app
flutter pub get
```

## Disclaimer

Educational prototype only. **Not investment advice.** Model outputs depend on data quality, stationarity, and leakage risk; always validate with domain experts and regulatory requirements before any trading use.
