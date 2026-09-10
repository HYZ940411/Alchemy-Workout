# Starter Variant: Python E2E

技術棧：FastAPI + SQLAlchemy 2.0 + Behave + Testcontainers (PostgreSQL)

---

## 目錄結構

```
${PROJECT_ROOT}/
├── ${PY_APP_DIR}/                          # 應用程式主目錄（例：app/）
│   ├── __init__.py
│   ├── main.py                             # FastAPI 入口（掛載 CORS、路由、/health）
│   ├── exceptions.py                       # 自定義例外：BusinessError, NotFoundError 等
│   ├── core/
│   │   ├── __init__.py
│   │   ├── config.py                       # Paths 類別 + Settings 類別（DB URL, JWT, API prefix）
│   │   └── deps.py                         # DI：get_db(), get_current_user_id(), set_session_factory()
│   ├── models/
│   │   └── __init__.py                     # 宣告 Base = declarative_base()
│   ├── repositories/
│   │   └── __init__.py                     # 空（由 automation skill 產生）
│   ├── services/
│   │   └── __init__.py                     # 空
│   ├── api/
│   │   └── __init__.py                     # 空 router 佔位
│   └── schemas/
│       └── __init__.py                     # 空
├── ${PY_TEST_FEATURES_DIR}/                # 測試目錄（例：tests/features/）
│   ├── environment.py                      # Behave 環境：Testcontainers 生命週期
│   ├── helpers/
│   │   ├── __init__.py
│   │   └── jwt_helper.py                   # 測試用 JWT Token 產生器
│   └── steps/
│       ├── __init__.py
│       └── common_then/
│           ├── __init__.py
│           ├── success.py                  # @then('操作成功')
│           ├── failure.py                  # @then('操作失敗')
│           ├── failure_with_reason.py      # @then('操作失敗，原因為 {reason}')
│           └── error_message.py            # @then('錯誤訊息應為 {msg}')
├── alembic/
│   ├── env.py                              # Alembic 環境（讀取 Base.metadata）
│   └── versions/                           # Migration 檔案目錄
├── ${SPECS_ROOT_DIR}/                      # 規格檔案（例：specs/）
│   ├── activities/
│   ├── features/
│   └── clarify/
├── requirements.txt
├── pyproject.toml
├── behave.ini
├── docker-compose.yml
└── alembic.ini
```

---

## 依賴安裝（pip）

`requirements.txt` 內容：

```
# BDD Testing
behave>=1.2.6
pytest>=7.0.0
typing-extensions>=4.0.0

# 開發工具
black>=23.0.0
isort>=5.0.0
mypy>=1.0.0

# === E2E 專屬 ===
# FastAPI
fastapi>=0.109.0
uvicorn>=0.27.0

# 資料庫
sqlalchemy>=2.0.0
psycopg[binary]>=3.1.0
alembic>=1.13.0

# 測試基礎設施
testcontainers[postgres]>=3.7.0
httpx>=0.26.0

# 認證
PyJWT>=2.8.0
```

安裝指令：`pip install -r requirements.txt`

---

## 設定檔說明

### behave.ini

指定 Behave 測試路徑至 `{{PY_TEST_FEATURES_DIR}}`，啟用 pretty 格式與彩色輸出。

### docker-compose.yml

開發用 PostgreSQL 15 容器。容器名稱 `{{PROJECT_SLUG}}-postgres`，資料庫 `{{PROJECT_SLUG}}_dev`，帳密 `postgres:postgres`，port 5432。附帶 healthcheck。

### alembic.ini

指定 migration 腳本目錄 `alembic/`，預設連線 URL `postgresql+psycopg://postgres:postgres@localhost:5432/{{PROJECT_SLUG}}_dev`。env.py 會在測試時從環境變數 `DATABASE_URL` 覆寫。

### pyproject.toml

專案 metadata（name、version、description）。包含 black、isort、mypy、behave 的工具設定。Python >= 3.11。

---

## 測試框架設定（Behave + Testcontainers）

### environment.py 生命週期

| Hook | 行為 |
|------|------|
| `before_all` | 啟動 PostgreSQL Testcontainer → 取得連線 URL → 設定 `DATABASE_URL` 環境變數 → 建立 SQLAlchemy engine → 執行 Alembic migrations (`upgrade head`) → 建立 SessionLocal → 呼叫 `set_session_factory()` |
| `before_scenario` | 初始化 `context.last_error/last_response/query_result/ids/memo` → 建立 DB Session → 建立 FastAPI TestClient → 建立 JwtHelper → 初始化 `context.repos`/`context.services` |
| `after_scenario` | Rollback → Truncate 所有 tables（排除 `alembic_version`）→ 關閉 Session → 清理 context 狀態 |
| `after_all` | Dispose engine → 停止 Testcontainer |

### Context 物件結構

```python
context.last_error       # str | None — 最近一次操作錯誤
context.last_response    # httpx.Response — 最近一次 HTTP 回應
context.query_result     # Any — 查詢結果
context.ids              # dict — 儲存建立的實體 ID（如 {"小明": 1}）
context.memo             # dict — 通用暫存
context.db_session       # sqlalchemy.orm.Session
context.api_client       # FastAPI TestClient
context.jwt_helper       # JwtHelper 實例
context.repos            # SimpleNamespace — 各 Repository 實例
context.services         # SimpleNamespace — 各 Service 實例
```

---

## 資料庫設定

- **開發環境**：透過 `docker-compose.yml` 啟動 PostgreSQL 15
- **測試環境**：透過 Testcontainers 自動管理（每次 test session 啟動新容器）
- **Migration**：Alembic。`alembic/env.py` 從 `{{PY_APP_MODULE}}.models` 匯入 `Base.metadata` 支援 autogenerate
- **清理策略**：每個 Scenario 結束後 TRUNCATE CASCADE 所有 tables

---

## arguments.yml 變數對照

| Placeholder | 來源 | 說明 | 範例 |
|-------------|------|------|------|
| `{{PROJECT_NAME}}` | 詢問使用者 | 專案顯示名稱 | `課程平台` |
| `{{PROJECT_DESCRIPTION}}` | 詢問使用者 | 專案描述 | `BDD Workshop - Python E2E` |
| `{{PROJECT_SLUG}}` | 從 PROJECT_NAME 推導 | URL-safe 識別碼（小寫、連字號） | `course-platform` |
| `{{PY_APP_DIR}}` | arguments.yml | 應用程式目錄名 | `app` |
| `{{PY_APP_MODULE}}` | 從 PY_APP_DIR 推導 | Python module 路徑（`.` 分隔） | `app` |
| `{{PY_TEST_MODULE}}` | 從 PY_TEST_FEATURES_DIR 推導 | 測試 module 路徑 | `tests.features` |
| `{{PY_TEST_FEATURES_DIR}}` | arguments.yml | 測試 features 目錄 | `tests/features` |
| `{{SPECS_ROOT_DIR}}` | arguments.yml | 規格檔案根目錄 | `specs` |

推導規則：
- `PROJECT_SLUG` = PROJECT_NAME 轉小寫、空格換連字號、移除特殊字元
- `PY_APP_MODULE` = PY_APP_DIR 中 `/` 換成 `.`
- `PY_TEST_MODULE` = PY_TEST_FEATURES_DIR 中 `/` 換成 `.`

---

## 驗證步驟

完成骨架建立後，確認以下事項：

1. **檔案完整性**：所有 template 對照表中的檔案都已寫入目標路徑
2. **Placeholder 替換**：專案中不應殘留任何 `{{...}}` 字串
3. **目錄結構**：所有空 `__init__.py` 都已建立（repositories、services、schemas）
4. **安裝測試**：`pip install -r requirements.txt` 能正常完成
5. **Behave 可執行**：`behave --dry-run` 不報錯（無 feature 檔案時會顯示 0 scenarios）

---

## 安全規則

- 不覆蓋已存在的檔案（跳過並回報）
- 不建立 feature-specific 程式碼（models、repositories、services、API endpoints、step definitions）
- 不執行 `pip install` 或 `alembic init`

---

## Template 檔案對照表

| Template 檔名（`__` = `/`） | 輸出路徑 |
|------------------------------|----------|
| `requirements.txt` | `requirements.txt` |
| `pyproject.toml` | `pyproject.toml` |
| `behave.ini` | `behave.ini` |
| `docker-compose.yml` | `docker-compose.yml` |
| `alembic.ini` | `alembic.ini` |
| `app__init__.py` | `${PY_APP_DIR}/__init__.py` |
| `app__main.py` | `${PY_APP_DIR}/main.py` |
| `app__exceptions.py` | `${PY_APP_DIR}/exceptions.py` |
| `app__core__init__.py` | `${PY_APP_DIR}/core/__init__.py` |
| `app__core__config.py` | `${PY_APP_DIR}/core/config.py` |
| `app__core__deps.py` | `${PY_APP_DIR}/core/deps.py` |
| `app__models__init__.py` | `${PY_APP_DIR}/models/__init__.py` |
| `app__api__init__.py` | `${PY_APP_DIR}/api/__init__.py` |
| `alembic__env.py` | `alembic/env.py` |
| `tests__features__environment.py` | `${PY_TEST_FEATURES_DIR}/environment.py` |
| `tests__features__helpers__init__.py` | `${PY_TEST_FEATURES_DIR}/helpers/__init__.py` |
| `tests__features__helpers__jwt_helper.py` | `${PY_TEST_FEATURES_DIR}/helpers/jwt_helper.py` |
| `tests__features__steps__init__.py` | `${PY_TEST_FEATURES_DIR}/steps/__init__.py` |
| `tests__features__steps__common_then__init__.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/__init__.py` |
| `tests__features__steps__common_then__success.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/success.py` |
| `tests__features__steps__common_then__failure.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/failure.py` |
| `tests__features__steps__common_then__failure_with_reason.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/failure_with_reason.py` |
| `tests__features__steps__common_then__error_message.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/error_message.py` |

額外建立的空 `__init__.py`（無 template）：
- `${PY_APP_DIR}/repositories/__init__.py`
- `${PY_APP_DIR}/services/__init__.py`
- `${PY_APP_DIR}/schemas/__init__.py`

---

## 完成後引導

```
Walking skeleton 已建立完成。

下一步：
1. cd ${PROJECT_ROOT} && pip install -r requirements.txt
2. /aibdd-discovery — 開始需求探索
```
