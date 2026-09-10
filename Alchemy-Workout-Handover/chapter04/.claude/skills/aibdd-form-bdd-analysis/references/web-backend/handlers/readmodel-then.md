# Handler: readmodel-then

## Trigger 辨識

Then 語句驗證 **Query 的 API 回傳結果**。

**識別規則**：
- 前提：When 是 Query 操作（已接收 response）
- 驗證的是 API 回傳值（而非資料庫中的狀態）
- 常見句型（非窮舉）：「查詢結果應」「回應應」「應返回」「結果包含」

**通用判斷**：如果 Then 是驗證 Query 操作的回傳值（Response body），就使用此 Handler。

## 任務

- **E2E**：從共享狀態取得 HTTP response → assert response.json() 內容
- **UT**：從共享狀態取得 query_result → assert 結果

## 與 aggregate-then 的區別

| | readmodel-then | aggregate-then |
|---|---|---|
| 資料來源 | API Response (response.json()) | DB/Repository 查詢 |
| 前提操作 | When = Query | When = Command |
| 驗證層級 | 表示層（API 回傳什麼） | 資料層（DB 存了什麼） |

## 關鍵原則

**不重新調用 API** — 使用 When 步驟中已儲存的 response/結果。

## 實作流程

### E2E 版

1. 從共享狀態取得 `last_response`
2. 解析 `response.json()`
3. 根據 Gherkin 語意 assert 對應欄位
4. 欄位名與 api.yml response schemas 一致

### UT 版

1. 從共享狀態取得 `query_result`
2. 根據 Gherkin 語意 assert 對應屬性

## BDD 模式

### 驗證單一記錄

```gherkin
When 用戶 "Alice" 查詢課程 1 的進度
Then 操作成功
And 查詢結果應包含進度 80，狀態為 "進行中"
```

### 驗證列表筆數

```gherkin
When 用戶 "Alice" 查詢購物車中的所有商品
Then 操作成功
And 查詢結果應包含 2 個商品
```

### 驗證列表內容

```gherkin
And 第一個商品的 ID 應為 "PROD-001"，數量為 2
```

### DataTable 驗證

```gherkin
Then 查詢結果應包含以下課程：
  | lessonId | name        | progress |
  | 1        | 物件導向基礎 | 80       |
  | 2        | 設計模式     | 50       |
```

## Response Envelope 處理

API 回傳通常有 envelope：`{ "success": true, "data": {...} }`

- 先取 `data` 欄位再驗證內容
- 列表回傳：`data` 可能是 array 或包含 `items` 欄位

## 共用規則

1. **R1: 不重新呼叫 API** — 使用 When 中已儲存的 response
2. **R2: 欄位名 = api.yml response schemas** — 不自行轉換命名
3. **R3: 中文狀態映射** — 驗證時做中文→enum 轉換
4. **R4: 處理 envelope** — 先解包再驗證
5. **R5: 列表驗證要同時驗筆數和內容** — 不只驗 length
