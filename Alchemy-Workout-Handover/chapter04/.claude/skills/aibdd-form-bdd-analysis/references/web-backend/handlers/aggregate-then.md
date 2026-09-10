# Handler: aggregate-then

## Trigger 辨識

Then 語句驗證 **Aggregate 的屬性狀態**（從資料庫/Repository 查詢）。

**識別規則**：
- 驗證實體的屬性值（而非 API 回傳值）
- 描述「某個東西的某個屬性應該是某個值」
- 常見句型（非窮舉）：「在...的...應為」「的...應為」「應包含」

**通用判斷**：如果 Then 是驗證 Command 操作後的資料狀態（需要從儲存層查詢），就使用此 Handler。

## 任務

- **E2E**：使用 SQLAlchemy Repository 從 PostgreSQL 查詢 → Assert 屬性值
- **UT**：使用 FakeRepository 查詢 → Assert 屬性值

## 與其他 Then Handler 的區別

| | aggregate-then | readmodel-then | success-failure |
|---|---|---|---|
| 資料來源 | DB/Repository 查詢 | API Response | HTTP status/exception |
| 驗證對象 | Aggregate 內部屬性 | Response body 欄位 | 成功/失敗狀態 |
| 前提操作 | Command | Query | Command |
| 用途 | 驗證副作用（寫入後的 DB 狀態） | 驗證回傳值（讀取結果） | 驗證操作結果 |

## 實作流程

1. 從 context 取得儲存機制（db_session / FakeRepo）
2. 識別要查詢的 Aggregate 名稱
3. 從 Gherkin 提取查詢條件（通常是複合主鍵）
4. 使用 Repository 查詢 Aggregate
5. Assert Aggregate 不為 null
6. Assert Aggregate 的屬性值

## BDD 模式

### 驗證單一屬性

```gherkin
And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2
```

### 驗證多個屬性

```gherkin
And 用戶 "Alice" 在課程 1 的進度應為 80%，狀態應為 "進行中"
```

### DataTable 驗證

```gherkin
Then 用戶 "Alice" 的購物車應包含以下商品：
  | productId | quantity |
  | PROD-001  | 3        |
  | PROD-002  | 1        |
```

## 共用規則

1. **R1: 從 Repository 查詢** — 不從 API response 取值
2. **R2: 使用複合主鍵查詢** — 查詢條件從 Gherkin 語意推斷
3. **R3: 中文狀態映射** — 與 aggregate-given 相同的映射規則
4. **R4: Assert 不為 null** — 先確認 Aggregate 存在，再驗屬性
5. **R5: 不修改資料** — Then 只讀不寫
