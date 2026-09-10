---
name: aibdd-auto-red
description: >
  BDD 紅燈實作執行器。對單一 .feature 執行完整紅燈流程：
  Schema Analysis（環境就緒）→ Step Template（骨架生成）→ Red Implementation（載入外部 Handler 實作測試）。
  Handler 定義來自 /aibdd-form-bdd-analysis 的 web-backend 模組。
  透過 arguments.yml 的 tech_stack + test_strategy 自動路由語言變體。
  當 /aibdd-auto-control-flow 呼叫紅燈階段，或使用者說「紅燈」「red」時觸發。
---

# 紅燈實作執行器

寫出測試程式，確認有 Failing Test（Value Difference，非環境問題）。

## 紅燈定義

- **(a) 環境正常** — Docker/DB 可連、API route 已註冊、import 無誤
- **(b) Value Difference** — 測試預期某個值，但系統回傳的值不對（或尚未實作）

環境的 Difference ≠ 紅燈。Value 的 Difference = 紅燈。兩者都符合，才算正式進入 Red。

## 變體路由

讀取 `arguments.yml`：

| tech_stack | test_strategy | variant reference | 失敗模式 |
|-----------|---------------|-------------------|---------|
| python | e2e | `web-backend/variants/python-e2e.md` | HTTP 404 |
| java | e2e | `web-backend/variants/java-e2e.md` | HTTP 404 |
| python | ut | `web-backend/variants/python-ut.md` | NotImplementedError |

**Handler 和 variant 的物理位置**：`bdd-analysis/references/web-backend/`

啟動時 Read 對應的 variant reference，全程保持在 context 中。

---

## 三步驟流程

```
Step 1: Schema Analysis    → Read references/schema-analysis.md → 確保環境就緒（條件 a）
Step 2: Step Template      → Read references/step-template.md → 系統無關的骨架生成
Step 3: Red Implementation → 對每個 TODO step:
                              → 讀 TODO 取得 handler type
                              → Read bdd-analysis/references/web-backend/handlers/{type}.md
                              → 搭配已載入的 variant reference
                              → 實作測試程式碼
                              → 驗證紅燈（條件 b）
```

### Step 1: Schema Analysis

Read `references/schema-analysis.md`。

核心任務：
1. 讀取 .feature + api.yml + erm.dbml
2. 比對現有 ORM Models / Migrations 是否一致
3. 產出 GO/NO-GO 決策
4. 若需要：建立 migration、補齊 ORM Models

完成後 schema-analysis reference 可釋放。

### Step 2: Step Template Generation

Read `references/step-template.md`。

核心任務：
1. 解析 .feature 中每個 Scenario 的 Given/When/Then steps
2. 用決策樹分類每個 step（完整規則見 `bdd-analysis/references/web-backend/句型分析方針.md`）
3. 產生 step definition 骨架，每個 step 含：
   - 函數簽名 + 參數
   - `pass` placeholder
   - `# TODO: [事件風暴部位: {TYPE}]` 標註
   - `# TODO: 參考 bdd-analysis/references/web-backend/handlers/{type}.md 實作` 標註

完成後 step-template reference 可釋放。

### Step 3: Red Implementation

對每個含 TODO 的 step definition：
1. 讀取 TODO 標註 → 取得 handler type
2. Read `bdd-analysis/references/web-backend/handlers/{type}.md`（若尚未載入）
3. 搭配已載入的 variant reference 中的語言模式
4. 將 `pass` 替換為完整測試程式碼
5. 處理下一個 step（handler reference 可切換）

同時產出基礎建設（若不存在）：
- ORM Models / JPA Entities（置於 app 目錄，非 test 目錄）
- Repository 介面/類別

---

## 共用規則（跨 handler、跨語言）

### R1: Command 不驗 Response 內容
Command handler 只儲存 response，不做 assertion。驗證交給 Then handler。

### R2: 欄位名必須與 api.yml 一致
Request/Response 欄位名以 `api.yml` schemas 為唯一真相來源。

### R3: ID 儲存到共享狀態
建立實體後，將 ID 存入共享狀態（`context.ids` / `ScenarioContext`）。

### R4: Models/Repositories 置於 app 目錄
基礎建設放在 production code 目錄，非 test 目錄。

### R5: 不實作後端業務邏輯
Red 階段只定義介面。API endpoint / Service 方法體留空。測試預期失敗。

### R6: 測試將失敗（紅燈）
這是 TDD 紅燈階段的本質。失敗原因必須是 Value Difference。

### R7: 使用真實資料庫（E2E）或記憶體（UT）
E2E 用 Testcontainers PostgreSQL，UT 用 dict-based FakeRepository。

### R8: Data Table 逐欄對應
Feature 的 Data Table 欄位與 api.yml/erm.dbml 欄位 1:1 對應。

### R9: API Endpoint Path = api.yml 定義
HTTP 路徑從 api.yml paths 讀取，不自行編造。

---

## Docker 環境檢查（E2E only）

Red 執行前確認：
1. `docker info` → Docker daemon 運行中
2. `docker ps` → 無殘留 Testcontainers
3. PostgreSQL image 可用

---

## 完成條件

- [ ] 環境正常（Docker/DB 可連、API route 已註冊）— 條件 (a)
- [ ] 測試執行後失敗，失敗原因是 Value Difference — 條件 (b)
      E2E: HTTP response 值不符預期（非 connection refused / 500）
      UT: assertion 值不符預期（非 ImportError / AttributeError）
- [ ] 所有 step definitions 已從 `pass` 替換為完整測試程式碼
- [ ] ORM Models / Entities 完整定義
- [ ] Repository 介面完整定義
- [ ] 欄位名與 api.yml schemas 一致
