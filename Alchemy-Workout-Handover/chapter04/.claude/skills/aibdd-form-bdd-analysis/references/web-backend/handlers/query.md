# Handler: query

## Trigger 辨識

When 語句執行**讀取操作**（Query）。

**識別規則**：
- 動作不修改系統狀態，只讀取資料
- 描述「取得某些資訊」的動作
- 常見動詞（非窮舉）：「查詢」「取得」「列出」「檢視」「獲取」「搜尋」

**通用判斷**：如果 When 是讀取操作且需要回傳值供 Then 驗證，就使用此 Handler。

## 任務

- **E2E**：調用 HTTP GET API，將 response 存入共享狀態
- **UT**：呼叫 Service/Query 方法，將結果存入共享狀態

## 與 Command Handler 的區別

| | Query | Command |
|---|---|---|
| HTTP 方法 | GET | POST/PUT/PATCH/DELETE |
| 系統狀態 | 不修改 | 修改 |
| Then 搭配 | readmodel-then | success-failure / aggregate-then |

## 實作流程

### E2E 版

1. 從共享狀態取得用戶 ID
2. 產生 JWT Token
3. 構建 URL（含 path parameters 和 query parameters）
4. 執行 HTTP GET 請求
5. 儲存 response 到共享狀態（供 readmodel-then 驗證）

### UT 版

1. 從共享狀態取得用戶 ID
2. 呼叫 Service/Query 方法
3. 儲存查詢結果到 `context.query_result`

## BDD 模式

### 基本查詢

```gherkin
When 用戶 "Alice" 查詢課程 1 的進度
```

### 帶 Query Parameters 的查詢

```gherkin
When 用戶 "Alice" 查詢第 1 章的所有課程
```

### 列表查詢

```gherkin
When 用戶 "Alice" 查詢購物車中的所有商品
```

## URL 構建規則

### Path Parameters
直接嵌入 URL 路徑：`/api/v1/lessons/{lesson_id}/progress`

### Query Parameters
使用 params 傳遞：`params={"chapter_id": chapter_id}`

### 路徑來源
從 api.yml paths 讀取，不自行編造。

## 共用規則

1. **R1: Query 不修改狀態** — GET 請求不應有副作用
2. **R2: 儲存 response** — E2E 存 HTTP response，UT 存查詢結果
3. **R3: URL = api.yml paths** — 路徑從 api.yml 讀取
4. **R4: ID 從共享狀態取得** — 不硬編碼
5. **R5: 不驗證結果** — 驗證交給 readmodel-then handler
