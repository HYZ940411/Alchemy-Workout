# Reconciler Contract

所有 form skill 共用的 desired-state reconciliation 合約。

## 核心思想

**每個 artifact 操作都是 delta：current state → desired state。**
Greenfield 是 current = 空的退化情況，不是特殊模式。

---

## 合約

```
Input:
  1. spec_inputs      — 推導 desired state 的來源（features, erm.dbml 等）
  2. current_artifact  — 現有 artifact 檔案（不存在 = greenfield）
  3. scope            — Execution Plan 中本 Phase 的區段（affected targets）

Output:
  1. updated_artifact  — 更新後的 artifact
  2. change_summary    — 實際執行的操作清單
```

---

## 流程（6 步）

### Step 1: Derive Desired State

從 spec_inputs 推導「artifact 應該長什麼樣」。

- 只處理 scope 範圍內的 targets
- 推導邏輯 = 各 skill 現有的「create」邏輯，不變

### Step 2: Read Current State

讀取 current_artifact。

- **不存在**（greenfield）→ current = 空集，進入 Step 3
- **存在** → parse 結構，提取可比較的元素

### Step 3: Compute Diff

```
diff(desired, current) → operations[]
```

Operations 分三類：

| 類型 | 定義 | 範例 |
|------|------|------|
| **modify** | 既有元素需更新 | Lead table 加 score 欄位 |
| **create** | 新元素不存在於 current | Journey table 新增 |
| **delete** | current 中有但 desired 中無 | 舊 endpoint 移除 |

**Greenfield 時**：current = 空 → 所有 desired 元素都是 create → 跟現有行為一致。

### Step 4: Preview

展示 diff 給使用者審查。格式：

```
══════════════════════════════════
Reconciliation Preview
══════════════════════════════════

modify (先改):
  • Lead table: +score:int, +score_updated_at:timestamp
  • Lead features: +Rule「後置 - 分數計算」

create (後增):
  • Journey table: id, lead_id, stage, created_at
  • Journey features: 3 new features

delete (需確認):
  • (無)

══════════════════════════════════
(P) Proceed  (E) Edit scope  (Q) Question
══════════════════════════════════
```

- **(P)** → 進入 Step 5
- **(E)** → 使用者調整 scope，回到 Step 3
- **(Q)** → 回答問題，重新展示 Preview

### Step 5: Apply with Clarify

**嚴格按順序執行**：

```
1. modify（先改）
   → 更新既有元素
   → 遇到衝突 → clarify-loop 解決
   → 每次 apply 後驗證 artifact 結構一致性

2. create（後增）
   → 新增元素（可引用已更新的既有元素）
   → 遇到模稜兩可 → clarify-loop

3. delete（最後，需確認）
   → 展示每個待刪除元素及其下游依賴
   → 使用者逐一確認
   → 清理引用
```

**先改後增原則**：modify 先於 create，因為新元素可能引用被修改的既有元素。

### Step 6: Output

- 寫入 updated artifact
- 回傳 change_summary：

```markdown
## Change Summary
| 操作 | 目標 | 說明 |
|------|------|------|
| modify | Lead table | +score:int |
| create | Journey table | 4 fields |
```

---

## 冪等性

同一組 `(spec_inputs, current_artifact)` 多次執行 → 產出相同結果。

已經是 desired state 的元素 → diff = 空 → 不動。

這使得 reconciler 可以安全地「重跑」— 中斷後重新執行不會產生副作用。

---

## 各 Skill 的職責分工

| 層級 | 誰做 | 做什麼 |
|------|------|--------|
| **跨 artifact** | Phase 01 (Execution Plan) | 判斷哪些 Phase 有工作、為什麼 |
| **單一 artifact** | Form Skill (Reconciler) | 計算精確 diff、執行 apply |

Execution Plan 提供 **scope**（哪些 targets 受影響）。
Reconciler 提供 **precision**（具體怎麼改）。

---

## Skill 遷移指南

將現有 form skill 遷移為 reconciler：

1. **現有的 create 邏輯 → Step 1**（Derive Desired State）— 不用改
2. **新增 Step 2**（Read Current）— 加一個「讀取現有 artifact」的步驟
3. **新增 Step 3**（Compute Diff）— 比較 desired vs current
4. **現有的 clarify 邏輯 → Step 5**（Apply with Clarify）— 包一層 diff-aware
5. **新增 Step 4 + 6**（Preview + Output）— UI 層

最小改動：**加 Step 2 + 3**，其餘包裝現有邏輯。

---

## IMPL_IMPACT：Spec → Implementation 影響標記

Spec Reconciler（Phase 02-04）改動 spec artifact 時，可能影響已存在的 implementation artifacts（Phase 05-08）。Reconciler **不直接讀取或修改** implementation artifacts（無職責汙染），但在 change_summary 中標記影響，由 Execution Plan 傳播給下游 Phase。

### Impact Types

| 類型 | 觸發條件 | 影響的 Implementation |
|------|---------|----------------------|
| `SENTENCE_PATTERN` | Gherkin 句型（Given/When/Then 文字）變更 | Step Definition regex/pattern 可能斷裂 |
| `DATATABLE_SCHEMA` | DataTable 欄位增刪改 | Step Definition 的 table 解析邏輯 |
| `FIELD_CHANGE` | erm.dbml 欄位增刪改型 | Domain Model + DB Migration |
| `ENUM_CHANGE` | erm.dbml Enum 值域變更 | Domain Model enum 定義 |
| `ENDPOINT_SCHEMA` | api.yml request/response schema 變更 | Backend Endpoint + Frontend API Layer + MSW Handler |
| `ENDPOINT_ROUTE` | api.yml path 或 method 變更 | Backend route + Frontend fetch URL + MSW Handler |
| `NEW_OPERATION` | 全新 feature/endpoint（create） | 需要完整 TDD cycle，不是定向修復 |

### change_summary 擴充格式

```markdown
## Change Summary
| 操作 | 目標 | 說明 |
|------|------|------|
| modify | Lead table | +source:varchar |
| create | Journey table | 4 fields |

## IMPL_IMPACT
| Phase | 影響目標 | Impact Type | 說明 |
|-------|---------|-------------|------|
| 05 | step_defs/lead_steps | DATATABLE_SCHEMA | Given datatable +source column |
| 05 | models/lead | FIELD_CHANGE | +source:varchar |
| 05 | migrations/ | FIELD_CHANGE | Lead table +source column |
| 06 | mocks/handlers/ | ENDPOINT_SCHEMA | GET /leads response +source |
| 06 | pages/lead/ | ENDPOINT_SCHEMA | Lead 列表顯示 +source |
```

### 產出規則

1. **每個 modify 操作必須評估 IMPL_IMPACT**：create 操作產出 `NEW_OPERATION`（需完整實作），modify 才產出具體 impact type
2. **只標記可推論的影響**：從 spec diff 能推論出的（如「欄位加了 → model 要加」），不猜測實作細節
3. **Phase 歸屬**：
   - Step Definitions / Models / Endpoints / Migrations → Phase 05
   - MSW Handlers / Frontend Pages → Phase 06
   - Test Plan → Phase 07（當 Activity 結構變更時）
   - Integration → Phase 08（當 Phase 05 或 06 有影響時自動觸發重驗）
4. **Greenfield 不產出 IMPL_IMPACT**：全部是 create → 全部是 `NEW_OPERATION` → Phase 05-08 正常走 one-shot 流程

### 下游消費方式

Phase 05-08 從 Execution Plan 讀取 IMPL_IMPACT hints：

| 模式 | 觸發條件 | 行為 |
|------|---------|------|
| **One-shot**（正常） | Execution Plan 中該 Phase 只有 `NEW_OPERATION` 或無 IMPL_IMPACT | 走完整 TDD / Build 流程 |
| **Targeted Fix**（定向修復） | Execution Plan 中該 Phase 有具體 impact type | 定位受影響的 implementation artifact → 定向修復 → 跑回歸測試 |

---

## 限制

- Reconciler 不處理跨 artifact 依賴（那是 Execution Plan 的責任）
- Reconciler 不自行決定 scope（從 Execution Plan 讀取）
- Reconciler 不直接讀取或修改 implementation artifacts（IMPL_IMPACT 是標記，不是操作）
- delete 操作永遠需要使用者確認，不可自動刪除
