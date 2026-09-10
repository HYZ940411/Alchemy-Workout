# WSA 課程平台 - 多語言 BDD 練習專案

這是一個支援多程式語言的 BDD (Behavior-Driven Development) 練習專案，用於展示如何使用相同的 Feature Files 在不同技術棧中實作相同的功能。

## 專案結構

```
wsa-課程平台/
├── features/           # 共用的 BDD Feature Files（11 個）
├── python/             # Python 版本實作
└── java/               # Java 版本實作
```

## 共用 Feature Files

兩個版本共用相同的 Feature Files，確保行為一致：

| Feature | 描述 |
|---------|------|
| 01-增加影片進度 | 用戶觀看影片並更新進度 |
| 02-提交挑戰題作業 | 用戶提交課程挑戰題 |
| 03-交付課程 | 用戶完成課程交付 |
| 04-查詢課程進度 | 查詢用戶的課程進度 |
| 05-查詢課程清單 | 查詢可用課程列表 |
| 06-查詢商品清單 | 查詢可購買商品 |
| 07-建立訂單 | 用戶建立購買訂單 |
| 08-查詢訂單 | 查詢訂單詳情 |
| 09-訂單付款 | 訂單付款流程 |
| 10-取消訂單 | 取消未付款訂單 |
| 11-查詢用戶角色清單 | 查詢用戶角色和權限 |

## 技術棧對比

| 面向 | Python | Java |
|------|--------|------|
| 語言版本 | Python 3.11+ | Java 17 |
| Web Framework | FastAPI | Spring Boot 3.2 |
| ORM | SQLAlchemy 2.0 | Spring Data JPA |
| BDD Framework | Behave | Cucumber 7.15 |
| DB Migration | Alembic | Flyway |
| Test Container | Testcontainers | Testcontainers |
| Database | PostgreSQL 15 | PostgreSQL 15 |

## 開發流程

兩個版本都使用相同的 E2E 開發流程：

1. **分析** (00-資料表及遷移分析.md) - 識別 Feature 需要的資料結構
2. **樣板** (01-Feature-to-Step-Definition-樣板.md) - 產生 Step Definition
3. **紅燈** (02-紅燈.md) - 確認測試失敗（TDD）
4. **綠燈** (03-綠燈.md) - 實作讓測試通過
5. **重構** (04-重構.md) - 優化程式碼品質

## 快速開始

### Docker Compose 模式（推薦）

專案提供三種運行模式：

#### 1. Mock 模式（僅前端，使用假資料）

```bash
docker-compose --profile mock up -d
```

- 前端：http://localhost:3000
- 使用前端內建的 mock 資料
- 適合前端開發和 UI 測試

#### 2. Java 後端模式

```bash
docker-compose --profile java up -d
```

- 前端：http://localhost:3000（連接後端 API）
- Java 後端：http://localhost:8080
- PostgreSQL：localhost:5432
- 適合 Java 後端開發和測試

#### 3. Python 後端模式

```bash
docker-compose --profile python up -d
```

- 前端：http://localhost:3000（連接後端 API）
- Python 後端：http://localhost:8080
- PostgreSQL：localhost:5432
- 適合 Python 後端開發和測試

#### 停止服務

```bash
# 停止 mock 模式
docker-compose --profile mock down

# 停止 Java 模式
docker-compose --profile java down

# 停止 Python 模式
docker-compose --profile python down
```

### 本地開發模式

#### Python 版本

```bash
cd python
pip install -r requirements.txt
behave tests/features/
```

#### Java 版本

```bash
cd java
mvn compile
mvn test
```

## AI 輔助開發

每個版本都有對應的 prompts 目錄，包含：

- **e2e/handlers/** - 不同類型 Step Definition 的實作模式
- **e2e/*.md** - 開發流程指引
- **rules/** - 程式碼品質和架構規範

這些 prompts 設計用於配合 AI 工具（如 Claude）進行輔助開發。
