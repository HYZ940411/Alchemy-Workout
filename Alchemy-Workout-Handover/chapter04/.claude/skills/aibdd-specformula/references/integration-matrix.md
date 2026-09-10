# Integration Validation 驗證矩陣

Phase 04 的核心 — 驗證前端（Phase 03）與後端（Phase 02）透過真實 HTTP 連線能正確協作。

## 來源

從 CRM 專案的 6 個整合問題中提煉：

| RCA # | 問題 | 驗證項 |
|-------|------|--------|
| #1 | 無 API proxy rewrite | 環境切換 |
| #2 | 無 response envelope | Envelope 格式 |
| #3 | 無 auth cookie/login | Auth flow |
| #4 | 欄位名 snake vs camel | 欄位名一致性 |
| #5 | Dashboard 缺 year/month | Query params |
| #2 | Error handling 路徑 | Error handling |

## 環境切換

| 設定 | Mock 模式 (Phase 03) | Real 模式 (Phase 04) |
|------|----------------------|----------------------|
| `NEXT_PUBLIC_MOCK_API` | `true` | `false` |
| `BACKEND_URL` | — | `http://localhost:{PORT}` |
| 後端 | 不啟動 | docker-compose / venv 啟動 |
| 資料 | MSW mock data | 真實 DB |

## 驗證項目

### 1. Response Envelope 格式

- 打任意 API endpoint
- 2xx 回應必須符合：`{ "success": true, "data": {...} }`
- 4xx/5xx 回應必須符合：`{ "success": false, "error": { "code": "...", "message": "..." } }`
- 比對 api.yml 中 SuccessResponse / ErrorResponse schema 定義

### 2. 欄位名一致性

- 前端 TypeScript type 定義的欄位名
- 後端 API response 的欄位名
- api.yml schemas 的 properties 欄位名
- **三者必須完全一致**（不存在 snake_case vs camelCase 的隱性轉換）

### 3. Auth Flow

- 執行 login → 取得 auth cookie/token
- 用取得的 credential 打 authenticated endpoint → 成功
- 不帶 credential 打 authenticated endpoint → 401
- 前端正確處理 401（導向 login 頁或顯示錯誤）

### 4. Query Params 完整性

- 前端傳送的 query parameters（如 year, month, page, limit）
- 後端接收的 query parameters
- api.yml parameters 定義
- **三者必須一致**（不存在前端傳了但後端沒接的 param）

### 5. Error Handling 路徑

- 觸發各種 4xx 錯誤（400 validation, 404 not found, 409 conflict）
- 前端正確解析 error envelope 並顯示對應訊息
- 觸發 5xx 錯誤 → 前端顯示通用錯誤而非崩潰

## 執行方式

1. 啟動後端（`docker-compose up` 或 `venv + uvicorn`）
2. 健康檢查通過
3. 前端環境切換（`.env.development` 修改）
4. 用 Chrome E2E 重跑 Phase 03 的 Activity Test Plan
5. 逐項核對上述 5 項驗證
6. 發現問題 → 定位前端/後端/契約 → 修正 → 重跑

## 判定標準

- 5 項全部通過 → Phase 04 完成
- 任一失敗 → 修正後重跑，直到全部通過
