# Schema Analysis

## 目的

在 Red 階段開始前，分析 .feature + api.yml + erm.dbml，確保現有資料模型（ORM/Entity、Migration）
與規格一致。若不一致則修正，確保後續 Step Template 和 Red Implementation 有正確的基礎。

## 分析 Checklist

### 1. 讀取規格檔案
- `.feature` — 需要的 Aggregate 和欄位
- `api.yml` — API 契約（路徑、Request/Response schemas）
- `erm.dbml` — Entity 結構定義（Table、Column、FK、enum）

### 2. 比對現有程式碼
- 掃描現有 ORM Models / JPA Entities
- 掃描現有 DB Migrations（Alembic versions / Flyway）
- 識別差異：新增欄位、改名、新 Aggregate、enum 變更

### 3. GO / NO-GO 決策

| 狀態 | 行動 |
|------|------|
| 全部一致 | GO — 直接進入 Step Template |
| 有差異但可自動修正 | 修正後 GO |
| 有衝突需人工判斷 | 暫停，報告差異 |

## 修正流程

### 新增 Aggregate
1. 根據 DBML 定義建立新的 Model/Entity
2. 建立對應 Repository
3. 建立 DB Migration

### 新增/修改欄位
1. 更新 Model/Entity 的欄位定義
2. 建立新的 Migration（ALTER TABLE）
3. 更新 Repository 的 finder 方法（如需要）

### Enum 變更
1. 更新 enum 定義
2. 建立 Migration（如 DB 層需要）

## 輸出

Schema Analysis 完成後產出：
- 更新後的 ORM Models / JPA Entities（若有變更）
- 新的 DB Migrations（若需要）
- GO / NO-GO 報告

## 跨語言差異

| 面向 | Python E2E | Java E2E | Python UT |
|------|-----------|----------|----------|
| ORM | SQLAlchemy | JPA (Hibernate) | 純 Python class |
| Migration | Alembic | Flyway / Liquibase | N/A（無 DB） |
| Repository | SQLAlchemy Session | Spring Data JPA | FakeRepository (dict) |
| 需要 Schema Analysis? | 是 | 是 | 否（跳過） |

**Python UT 跳過 Schema Analysis** — 沒有真實 DB，不需要 migration。
