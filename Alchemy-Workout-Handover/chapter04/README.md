# Chapter04: AI x BDD 開發實戰（E2E 測試）

本章節使用 **UT/E2E 測試 (End-to-End Test) + BDD**：真實 PostgreSQL + FastAPI，測試完整 API 流程。

## 目錄結構

```
chapter04/
├── app/                        # FastAPI 應用程式
│   ├── api/                    # API endpoints
│   ├── core/                   # 核心配置（config, deps）
│   ├── models/                 # SQLAlchemy ORM Models
│   ├── repositories/           # Repository 實作
│   ├── services/               # 業務邏輯
│   └── main.py                 # FastAPI 入口
├── tests/
│   └── features/               # BDD Features + Steps
│       ├── *.feature           # Gherkin Feature Files
│       ├── steps/              # Step Definitions
│       │   ├── aggregate_given/
│       │   ├── aggregate_then/
│       │   ├── commands/
│       │   ├── common_then/
│       │   ├── query/
│       │   └── readmodel_then/
│       ├── helpers/            # 測試輔助工具（JWT Helper）
│       └── environment.py      # Behave hooks（Testcontainers 設定）
├── alembic/                    # 資料庫遷移
├── specs/
│   ├── api.yml                 # API 規格（OpenAPI）
│   └── erm.dbml                # 資料表 Schema（SSOT）
└── prompts/
    ├── ut/                     # 單元測試 Prompts（參考用）
    └── e2e/                    # E2E 測試 Prompts
```

## 環境準備

### 1. 安裝依賴

```bash
cd chapter04
pip install -r requirements.txt
```

### 2. Docker（必要）

E2E 測試使用 Testcontainers 自動啟動 PostgreSQL，請確保 Docker 已安裝並運行。

```bash
# 檢查 Docker 是否運行
docker info
```

## 執行測試

```bash
# 執行所有測試
behave tests/features/

# 執行特定 feature
behave tests/features/01-增加影片進度.feature

# 顯示詳細輸出
behave tests/features/ --no-capture
```

## AI x BDD 開發流程

使用 Claude Code 進行 AI x BDD 開發的標準流程：

### Step 0: 資料表及遷移分析

```
do @prompts/e2e/00-資料表及遷移分析.md
for @tests/features/01-增加影片進度.feature
```

### Step 1: Feature → Step Definition 樣板

```
do @prompts/e2e/01-Feature-to-Step-Definition-樣板.md
for @tests/features/01-增加影片進度.feature
```

### Step 2: 紅燈（讓測試失敗）

```
do @prompts/e2e/02-紅燈.md
for @tests/features/01-增加影片進度.feature
```

### Step 3: 綠燈（實作 API 讓測試通過）

```
do @prompts/e2e/03-綠燈.md
for @tests/features/01-增加影片進度.feature
```

### Step 4: 重構

```
do @prompts/e2e/04-重構.md
for @tests/features/01-增加影片進度.feature
```

## 後端三巨頭規格

| 規格 | 檔案 | 說明 |
|------|------|------|
| Gherkin | `tests/features/*.feature` | 行為規格 |
| API Spec | `specs/api.yml` | OpenAPI 規格 |
| ERM | `specs/erm.dbml` | 資料表結構 |

## 技術架構

| 面向 | 技術選擇 |
|------|---------|
| 測試框架 | Behave |
| HTTP Client | FastAPI TestClient |
| 資料庫 | PostgreSQL（Testcontainers） |
| ORM | SQLAlchemy 2.0 |
| 遷移工具 | Alembic |
| 認證 | JWT（JwtHelper） |

## Prompts 說明

### 主流程 Prompts (`prompts/e2e/`)

| 順序 | 檔案 | 說明 |
|------|------|------|
| 0 | `00-資料表及遷移分析.md` | DBML → SQLAlchemy → Alembic |
| 1 | `01-Feature-to-Step-Definition-樣板.md` | Gherkin → E2E Step Definition |
| 2 | `02-紅燈.md` | HTTP 404 失敗 |
| 3 | `03-綠燈.md` | 實作 FastAPI endpoints |
| 4 | `04-重構.md` | 程式碼優化 |

### Handler Prompts (`prompts/e2e/handlers/`)

| Handler | 說明 |
|---------|------|
| `Aggregate-Given-Handler.md` | 建立測試資料（SQLAlchemy） |
| `Aggregate-Then-Handler.md` | 驗證資料庫狀態 |
| `Command-Handler.md` | HTTP POST/PUT/DELETE API |
| `Query-Handler.md` | HTTP GET API |
| `ReadModel-Then-Handler.md` | 驗證 API 回傳值 |
| `Success-Failure-Handler.md` | 驗證 HTTP status code |
