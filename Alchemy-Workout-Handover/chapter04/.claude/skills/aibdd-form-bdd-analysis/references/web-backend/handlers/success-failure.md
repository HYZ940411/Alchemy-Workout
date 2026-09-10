# Handler: success-failure

## Trigger 辨識

Then 語句描述**操作的成功或失敗結果**。

**識別規則**：
- 明確描述操作結果（成功/失敗）
- 常見句型：「操作成功」「操作失敗」「執行成功」「執行失敗」
- 可附帶錯誤訊息驗證：「錯誤訊息應為 "..."」

**通用判斷**：如果 Then 只關注操作是否成功或失敗（不關注回傳資料內容），就使用此 Handler。

## 任務

- **E2E**：從共享狀態取得 HTTP response → 驗證 status code
- **UT**：從共享狀態取得結果/錯誤 → 驗證是否有例外

## 與其他 Then Handler 的區別

| | success-failure | aggregate-then | readmodel-then |
|---|---|---|---|
| 驗證對象 | 操作結果（成功/失敗） | DB 中的 Aggregate 狀態 | API Response 內容 |
| 資料來源 | HTTP status / exception | Repository 查詢 | response.json() |
| 前提操作 | Command | Command | Query |

## 實作流程

### E2E 版

1. 從共享狀態取得 `last_response`
2. 成功：assert `status_code in [200, 201, 204]`
3. 失敗：assert `400 <= status_code < 500`

### UT 版

1. 從共享狀態取得 `last_error`
2. 成功：assert `last_error is None`
3. 失敗：assert `last_error is not None`

## BDD 模式

### 操作成功

```gherkin
When 用戶 "Alice" 更新課程 1 的影片進度為 80%
Then 操作成功
```

### 操作失敗

```gherkin
When 用戶 "Alice" 更新課程 1 的影片進度為 60%
Then 操作失敗
```

### 失敗 + 錯誤訊息

```gherkin
When 用戶 "Alice" 更新課程 1 的影片進度為 60%
Then 操作失敗
And 錯誤訊息應為 "進度不可倒退"
```

## 錯誤訊息驗證

E2E 版從 response JSON 提取錯誤訊息：
- 嘗試 `data["message"]` → `data["detail"]` → `data["error"]`

UT 版從 exception 提取：
- `str(context.last_error)`

## 共用規則

1. **R1: 只驗成功/失敗** — 不驗 Response 內容（那是 readmodel-then 的事）
2. **R2: 不重新呼叫 API** — 使用共享狀態中已存的 response
3. **R3: 通用步驟可跨 Feature 共用** — 「操作成功」「操作失敗」是 common steps
