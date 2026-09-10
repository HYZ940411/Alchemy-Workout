# WSA 課程平台 - Python 版本

## 技術棧

- **Python**: 3.11+
- **Web Framework**: FastAPI
- **ORM**: SQLAlchemy 2.0
- **Database**: PostgreSQL 15 (via Testcontainers)
- **BDD Testing**: Behave
- **Migration**: Alembic

## 目錄結構

```
python/
├── app/                    # 應用程式主程式碼
│   ├── api/               # FastAPI endpoints
│   ├── models/            # SQLAlchemy models
│   ├── repositories/      # Data access layer
│   ├── services/          # Business logic
│   ├── schemas/           # Pydantic schemas
│   ├── core/              # Configuration & dependencies
│   └── main.py            # FastAPI app entry
├── tests/
│   └── features/          # Behave BDD tests
│       ├── *.feature      # Symlinks to shared features
│       ├── steps/         # Step definitions
│       ├── helpers/       # Test helpers
│       └── environment.py # Test setup
├── alembic/               # Database migrations
├── prompts/               # AI prompts for development
│   ├── e2e/              # E2E testing prompts
│   │   ├── handlers/     # Handler patterns
│   │   └── *.md          # Workflow prompts
│   └── rules/            # Development rules
├── specs/                 # API specifications
└── requirements.txt       # Python dependencies
```

## 快速開始

### 前置條件

- Python 3.11+
- Docker (for Testcontainers)

### 安裝依賴

```bash
cd python
pip install -r requirements.txt
```

### 執行測試

```bash
cd python
behave tests/features/
```

### 執行特定 Feature

```bash
behave tests/features/01-增加影片進度.feature
```

## E2E 開發流程

使用 prompts/e2e/ 中的 prompts 進行 BDD 開發：

1. **00-資料表及遷移分析.md** - 分析 Feature 需要的資料結構
2. **01-Feature-to-Step-Definition-樣板.md** - 產生 Step Definition 樣板
3. **02-紅燈.md** - 執行測試確認紅燈
4. **03-綠燈.md** - 實作程式碼讓測試通過
5. **04-重構.md** - 重構程式碼

## 與 Java 版本的關係

本 Python 版本與 Java 版本共用相同的 Feature Files（位於 `../features/`），確保兩個版本的行為一致。
