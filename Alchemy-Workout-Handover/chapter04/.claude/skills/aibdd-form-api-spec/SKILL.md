---
name: aibdd-form-api-spec
description: >
  API 視圖的 Spec Skill（Reconciler）。從 .feature 文件推導 OpenAPI 格式的 api.yml。
  每個 Feature 的 command/query 對應一個 endpoint。
  以 desired-state reconciliation 模式運作：讀取現有 api.yml（若存在）→ 推導 desired state →
  計算 diff → 增量更新。Greenfield 時 current = 空，等同於從零建立。
  可被 /discovery 調用，也可獨立使用。
user-invocable: true
---

## I/O

| 方向 | 內容 |
|------|------|
| Input | `${FEATURE_SPECS_DIR}/**/*.feature` (completed, no sticky notes) |
| Output | `${API_SPECS_DIR}/api.yml` |

# 角色

管理 API 視圖。以 reconciler 模式從 Feature Files 推導 OpenAPI 規格。

**Reconciler 合約**：啟動時 Read `aibdd-core/references/reconciler-contract.md`，全程遵循。

## References 導覽

| 檔案 | 何時載入 | 內容 |
|------|---------|------|
| `references/openapi-format.md` | Step 1 Derive / Step 5 Apply | OpenAPI 格式範例、Path 命名、Status Code、型別推斷、CiC 分類 |

---

# Entry 條件

**獨立調用時**，先詢問：
- Feature Files 路徑（預設 `${FEATURE_SPECS_DIR}`）
- API spec 輸出路徑（預設 `${API_SPECS_DIR}/api.yml`）

**被 `/discovery` 或 carry-on 調用時**，由呼叫者提供以上資訊 + Execution Plan scope。

**前提**：所有輸入的 .feature 必須已完成（無便條紙、無 `(待澄清)` 佔位）。若發現未完成的 .feature，暫停並 **REPORT** 給協調器。

---

# Reconciliation 流程

## Step 1: Derive Desired State

Read `references/openapi-format.md` 取得型別推斷與格式規則。

從所有 scope 內的 .feature 推導「api.yml 應該長什麼樣」：

### Command Feature → 寫入操作

| When 動詞 | Method |
|-----------|--------|
| 建立、新增、送出、提交 | `POST` |
| 更新、修改、設定 | `PUT` / `PATCH` |
| 刪除、取消、移除 | `DELETE` |

- **Request Body Schema**：從 When 子句的參數提取
- **Path Parameter**：若 When 包含資源 ID → path parameter
- 呼叫者身份從 auth token 取得，**不放進** request body

### Query Feature → 讀取操作（GET）

- **Query Parameters**：從 When 子句的過濾條件提取
- **Response Schema**：從 Then datatable 的欄位提取

### Shared Schemas

`Error` schema：`{ message: string }`。Response envelope 依專案慣例。
**Shared schemas 只在 create 時產生，modify 時不動。**

## Step 2: Read Current State

讀取 `${API_SPECS_DIR}/api.yml`。不存在 → current = 空集。

## Step 3: Compute Diff

| 類型 | 條件 | 範例 |
|------|------|------|
| modify | endpoint 存在但 params/schema 不同 | GET /leads 加 score filter param |
| create | endpoint 不存在於 current | POST /scoring-rules 新增 |
| delete | current 有但 desired 無 | 需使用者確認 |

## Step 4: Preview

展示 diff 給使用者。格式見 reconciler-contract.md。

## Step 5: Apply with Clarify

**先改後增**：modify → create → delete（需確認）。

遇到模稜兩可 → clarify-loop（`AMB` / `GAP` / `ASM`）。

## Step 6: Output

寫入更新後的 api.yml + 回傳 change_summary（含 IMPL_IMPACT）。

### IMPL_IMPACT 產出規則

每個 **modify** 操作評估對 implementation 的影響（格式見 `reconciler-contract.md`）：

| api.yml Diff | Impact Type | Phase | 影響目標 |
|--------------|-------------|-------|---------|
| Endpoint path / method 變更 | `ENDPOINT_ROUTE` | 05+06 | Backend route + Frontend URL + MSW handler |
| Request/Response schema 變更 | `ENDPOINT_SCHEMA` | 05+06 | Backend endpoint + Frontend form/display + MSW |
| Status code 變更 | `ENDPOINT_SCHEMA` | 05+06 | Backend error handling + Frontend error display |
| 新 endpoint（create） | `NEW_OPERATION` | 05+06 | 完整 TDD + Frontend 頁面 |

---

# 完成條件

- 所有 scope 內 .feature 的 endpoint 均已生成/更新
- 無便條紙、無模糊型別
- api.yml 可被 OpenAPI validator 解析
- change_summary 正確反映實際操作（含 IMPL_IMPACT）
