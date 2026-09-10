# WSA 課程平台 - Walking Skeleton

這是一個基於 FastAPI + PostgreSQL + pytest 的 Walking Skeleton，用於驗證整個系統架構能正常運作。

## 技術堆疊

- **後端框架**: FastAPI
- **資料庫**: PostgreSQL
- **ORM**: SQLAlchemy
- **Migration**: Alembic
- **測試框架**: pytest
- **HTTP Client**: requests
- **容器化**: Docker, Testcontainers

## 專案結構

```
wsa-課程平台/
├── app/                    # FastAPI 應用程式
│   ├── main.py            # 入口點
│   ├── api/               # API endpoints
│   │   └── messages.py    # Message CRUD API
│   ├── core/              # 核心設定
│   │   ├── config.py      # 設定檔
│   │   ├── security.py    # JWT 認證
│   │   └── deps.py        # 依賴注入
│   ├── models/            # SQLAlchemy Models
│   │   └── message.py     # Message model
│   └── schemas/           # Pydantic Schemas
│       └── message.py     # Message schemas
├── tests/
│   └── e2e/
│       ├── conftest.py    # pytest fixtures
│       └── test_walking_skeleton.py  # E2E 測試
├── alembic/               # 資料庫 migrations
│   └── versions/
│       └── 001_create_messages_table.py
├── requirements.txt       # 生產依賴
├── requirements-dev.txt   # 開發/測試依賴
├── Dockerfile
├── docker-compose.yml
├── alembic.ini
└── pytest.ini
```

## 啟動前提

在開始使用 Walking Skeleton 之前，請確保已安裝以下必要工具：

### 1. Python 3.11 或 3.12（推薦）

**注意**：目前推薦使用 **Python 3.11 或 3.12**，Python 3.13 可能會遇到某些套件相容性問題。

檢查 Python 版本：
```bash
python3 --version
# 或
python --version
```

**如果使用 Python 3.13**：
本專案使用 `psycopg[binary]` (psycopg3) 來支援 Python 3.13。

**建議安裝 Python 3.11**：
```bash
# macOS (使用 Homebrew)
brew install python@3.11

# 建立虛擬環境時指定版本
python3.11 -m venv venv
```

如果未安裝 Python，請前往 [Python 官網](https://www.python.org/downloads/) 下載安裝。

### 2. Docker

Docker 用於啟動 PostgreSQL 容器和後端服務。

**檢查 Docker 是否已安裝：**
```bash
docker --version
docker-compose --version
```

**安裝 Docker：**
- **macOS**: 下載 [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop)
- **Linux**: 
  ```bash
  # Ubuntu/Debian
  sudo apt-get update
  sudo apt-get install docker.io docker-compose
  
  # 或使用官方安裝腳本
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  ```
- **Windows**: 下載 [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop)

**確認 Docker 服務運行：**
```bash
docker ps
```

如果出現錯誤，請啟動 Docker Desktop 或 Docker 服務。

### 3. Alembic

Alembic 用於資料庫 migration 管理。它會透過 `requirements-dev.txt` 自動安裝，但也可以單獨安裝：

```bash
pip install alembic
```

**驗證安裝：**
```bash
alembic --version
```

### 4. pip（Python 套件管理器）

通常隨 Python 一起安裝，確認可用：
```bash
pip3 --version
# 或
pip --version
```

### 5. 虛擬環境（建議）

雖然不是必須，但強烈建議使用虛擬環境來隔離專案依賴：

```bash
# 建立虛擬環境
python3 -m venv venv

# 啟動虛擬環境
# macOS/Linux:
source venv/bin/activate
# Windows:
# venv\Scripts\activate
```

### 驗證所有工具

執行以下命令確認所有工具都已正確安裝：

```bash
python3 --version && \
pip3 --version && \
docker --version && \
docker-compose --version && \
echo "所有工具已就緒！"
```

如果所有命令都成功執行，表示環境已準備完成。

## 快速開始

### 1. 安裝依賴

```bash
pip install -r requirements-dev.txt
```

### 2. 啟動開發環境

使用 Docker Compose：

```bash
docker-compose up -d
```

這會啟動：
- PostgreSQL (port 5432)
- FastAPI 後端 (port 8000)

### 3. 執行 Migration

```bash
alembic upgrade head
```

### 4. 測試 API

訪問 http://localhost:8000/docs 查看 API 文檔

健康檢查：
```bash
curl http://localhost:8000/health
```

建立 message：
```bash
curl -X POST http://localhost:8000/api/messages \
  -H "Content-Type: application/json" \
  -d '{"content": "Hello World!"}'
```

取得所有 messages：
```bash
curl http://localhost:8000/api/messages
```

### 5. 執行 E2E 測試

```bash
pytest tests/e2e/test_walking_skeleton.py -v
```

## 驗證 Walking Skeleton

### 快速驗證（推薦）

執行自動化驗證腳本：

```bash
./verify_skeleton.sh
```

這個腳本會自動完成所有驗證步驟，包括：
- 檢查必要工具和檔案
- 安裝依賴
- 啟動 PostgreSQL
- 執行 migration
- 啟動 FastAPI 服務
- 執行 E2E 測試

### 手動驗證

詳細的手動驗證步驟請參考 [VERIFY.md](./VERIFY.md)

### 驗證檢查清單

- [ ] PostgreSQL 容器可以啟動
- [ ] 資料庫連線成功
- [ ] Alembic migration 可以執行
- [ ] FastAPI 服務可以啟動
- [ ] Health check endpoint 回應正常
- [ ] Message CRUD API 運作正常
- [ ] 所有 E2E 測試通過
- [ ] 測試隔離機制正常運作

## Walking Skeleton 驗證內容

這個 Walking Skeleton 驗證了以下完整流程：

1. **PostgreSQL 容器啟動** (Testcontainers)
2. **資料庫 Schema 建立** (SQLAlchemy + Alembic)
3. **FastAPI 服務運作**
4. **HTTP API 呼叫成功** (requests)
5. **資料庫 CRUD 操作** (Create, Read, Delete)
6. **測試隔離機制** (Truncate tables)

## 測試說明

### E2E 測試架構

- **Session Scope**：
  - PostgreSQL 容器只啟動一次
  - 資料庫引擎建立一次
  
- **Function Scope**：
  - 每個測試有獨立的 DB session
  - 每個測試後自動清空所有 tables
  - 每個測試有獨立的 HTTP client

### 測試案例

1. `test_health_check`: 驗證服務健康檢查
2. `test_create_and_get_message`: 驗證完整的建立和取得流程
3. `test_list_messages`: 驗證列表功能
4. `test_delete_message`: 驗證刪除功能
5. `test_database_isolation`: 驗證測試隔離機制

## 說明

這是一個純基礎建設的 Walking Skeleton，不包含任何應用情境相關的程式碼。

- **基礎建設**：FastAPI、PostgreSQL、Alembic、pytest、Testcontainers
- **驗證用情境**：Message CRUD API（用於驗證整個系統架構運作正常）

所有應用情境相關的程式碼（如 User、Lesson、LessonProgress 等）都應該在後續開發階段加入。

## 環境變數

參考 `.env.example` 建立 `.env` 檔案：

```bash
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/wsa_course
SECRET_KEY=your-secret-key-here
DEBUG=True
```

## 開發指令

啟動開發服務器：
```bash
uvicorn app.main:app --reload
```

執行所有測試：
```bash
pytest tests/ -v
```

執行測試並顯示覆蓋率：
```bash
pytest tests/ --cov=app --cov-report=html
```

建立新的 migration：
```bash
alembic revision --autogenerate -m "description"
```

套用 migrations：
```bash
alembic upgrade head
```

回滾 migration：
```bash
alembic downgrade -1
```
