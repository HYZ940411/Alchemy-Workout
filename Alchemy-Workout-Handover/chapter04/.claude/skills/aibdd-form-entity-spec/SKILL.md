---
name: aibdd-form-entity-spec
description: >
  Entity 視圖的 Spec Skill（Reconciler）。從 .feature 文件推導 DBML 格式的 erm.dbml（資料模型）。
  以 desired-state reconciliation 模式運作：讀取現有 erm.dbml（若存在）→ 推導 desired state →
  計算 diff → 增量更新。Greenfield 時 current = 空，等同於從零建立。
  可被 /discovery 調用，也可獨立使用。
user-invocable: true
---

## I/O

| 方向 | 內容 |
|------|------|
| Input | `${FEATURE_SPECS_DIR}/**/*.feature` (completed, no sticky notes) |
| Output | `${ENTITY_SPECS_DIR}/erm.dbml` |

# 角色

管理 Entity 視圖。以 reconciler 模式從 Feature Files 推導資料模型。

**Reconciler 合約**：啟動時 Read `aibdd-core/references/reconciler-contract.md`，全程遵循。

## References 導覽

| 檔案 | 何時載入 | 內容 |
|------|---------|------|
| `references/dbml-format.md` | Step 1 Derive / Step 5 Apply | 型別對應、約束推導、DBML 輸出格式、CiC 分類 |
| `references/strategy-guard.md` | Step 5 遇到衝突時 | Aggregate 結構衝突 / 缺少 Aggregate 的回退規則 |

---

# Entry 條件

**獨立調用時**，先詢問：
- Feature Files 路徑（預設 `${FEATURE_SPECS_DIR}`）
- Entity model 輸出路徑（預設 `${ENTITY_SPECS_DIR}/erm.dbml`）

**被 `/discovery` 或 carry-on 調用時**，由呼叫者提供以上資訊 + Execution Plan scope。

**前提**：所有輸入的 .feature 必須已完成（無便條紙、無 `(待澄清)` 佔位）。若發現未完成的 .feature，暫停並 **REPORT** 給協調器。

---

# Reconciliation 流程

## Step 1: Derive Desired State

Read `references/dbml-format.md` 取得型別對應與約束推導規則。

從所有 scope 內的 .feature 推導「erm.dbml 應該長什麼樣」：

1. **從 Background datatable 識別 Aggregate** — 每個 `Given 系統中有以下<Aggregate名>：` 對應一張資料表。datatable 的 key 欄位（`productId` 等）→ `id` 欄位（pk），其餘依型別推斷
2. **Enum 萃取** — 有限值域 → Enum。來源：datatable 欄位值 + .activity BRANCH guard 值
3. **Relationship 偵測** — 掃描跨 datatable 的 Aggregate 共現（`userId` → `users.id`），多對多 → junction table

## Step 2: Read Current State

讀取 `${ENTITY_SPECS_DIR}/erm.dbml`。

- **不存在**（greenfield）→ current = 空集，所有 desired 元素都是 create
- **存在** → parse tables、fields、enums、refs

## Step 3: Compute Diff

| 類型 | 條件 | 範例 |
|------|------|------|
| modify | table 存在但 fields 不同 | Lead table 缺 score 欄位 → +score:int |
| modify | enum 值域擴充 | order_status 新增「退款中」 |
| create | table 不存在於 current | Journey table 新增 |
| create | 新 enum / 新 ref | journey_stage enum |
| delete | current 有但 desired 無 | 需使用者確認 |

## Step 4: Preview

展示 diff 給使用者。格式見 reconciler-contract.md。

## Step 5: Apply with Clarify

**先改後增**：modify → create → delete（需確認）。

遇到衝突 → Read `references/strategy-guard.md`，REPORT 給協調器。
遇到模稜兩可 → clarify-loop（`GAP` / `ASM` / `AMB` / `CON`）。

## Step 6: Output

寫入更新後的 erm.dbml + 回傳 change_summary（含 IMPL_IMPACT）。

### IMPL_IMPACT 產出規則

每個 **modify** 操作評估對 implementation 的影響（格式見 `reconciler-contract.md`）：

| erm.dbml Diff | Impact Type | Phase | 影響目標 |
|---------------|-------------|-------|---------|
| Table +field / -field | `FIELD_CHANGE` | 05 | Model + Migration + Step Def |
| Field type / name 變更 | `FIELD_CHANGE` | 05+06 | Model + Migration + Step Def + Frontend |
| Enum +value / -value | `ENUM_CHANGE` | 05 | Model enum 定義 |
| New Table（create） | `NEW_OPERATION` | 05 | 完整 TDD cycle |

Greenfield 不產出 IMPL_IMPACT。只加 constraint 不影響 implementation 結構。

---

# 完成條件

- 所有 scope 內 .feature 的 Aggregate 均有對應資料表
- 所有欄位有明確型別，所有關聯已標示
- 無便條紙、無模糊約束
- erm.dbml 可被 DBML parser 解析
- change_summary 正確反映實際操作（含 IMPL_IMPACT）
