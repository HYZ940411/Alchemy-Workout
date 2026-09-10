# Handler: command

## Trigger 辨識

Given/When 語句執行**寫入操作**（Command）。

**識別規則**：
- 動作會修改系統狀態
- 描述「執行某個動作」或「已完成某個動作」
- Given 常見過去式：「已訂閱」「已完成」「已建立」「已添加」「已註冊」
- When 常見現在式：「更新」「提交」「建立」「刪除」「添加」「移除」

**通用判斷**：如果語句是修改系統狀態的操作且不需要回傳值，就使用此 Handler。

## 任務

- **E2E**：調用 HTTP POST/PUT/PATCH/DELETE API
- **UT**：直接呼叫 Service 方法

## 與 Query Handler 的區別

| | Command | Query |
|---|---|---|
| HTTP 方法 | POST/PUT/PATCH/DELETE | GET |
| 系統狀態 | 修改 | 不修改 |
| Response 驗證 | 不驗證（交給 Then） | 不驗證（交給 Then） |
| 用途 | 執行操作 | 讀取資料 |

## Given vs When 的 Command 差異

| | Given + Command | When + Command |
|---|---|---|
| 目的 | 建立前置資料（透過 API） | 測試目標操作 |
| 失敗處理 | 不預期失敗 | 可能成功或失敗 |

## 實作流程

### E2E 版

1. 從共享狀態取得用戶 ID
2. 產生 JWT Token
3. 構建 Request Body（欄位名 = api.yml schemas）
4. 執行 HTTP POST/PUT/DELETE 請求
5. 儲存 response 到共享狀態（供 Then 驗證）
6. **不做 assertion** — 驗證交給 Then handler

### UT 版

1. 從共享狀態取得用戶 ID
2. 呼叫 Service 方法（try/except 捕獲 BusinessError）
3. 儲存結果或錯誤到共享狀態
4. **不做 assertion**

## BDD 模式

### When + Command

```gherkin
When 用戶 "Alice" 更新課程 1 的影片進度為 80%
```

### Given + Command（前置操作）

```gherkin
Given 用戶 "Alice" 已訂閱課程 1
```

### DataTable + Command

```gherkin
When 用戶 "Alice" 批量更新以下商品數量：
  | productId | quantity |
  | PROD-001  | 3        |
  | PROD-002  | 1        |
```

## 共用規則

1. **R1: Command 不驗 Response** — 只儲存 response，assertion 交給 Then
2. **R2: 欄位名 = api.yml** — Request Body 的 key 必須與 api.yml schemas 一致
3. **R3: 儲存 response** — E2E 存 HTTP response，UT 存結果/錯誤
4. **R4: ID 從共享狀態取得** — 不硬編碼 ID
5. **R5: Given Command 不預期失敗** — 前置操作應該總是成功
