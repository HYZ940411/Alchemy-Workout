---
name: aibdd-specformula
description: >
  需求層級的全流程工程計畫產生器。給定任意新需求（功能群、單一功能、微調），
  自動產出 plan.md（含 Dependency Graph）+ 8 張 Phase 卡片
  （External Quality: Strategic → Entity → BDD Analysis → API Contract
   → Implementation: Backend TDD → Frontend Build → Frontend E2E → Integration），
  然後委派 /aibdd-carry-on-engineering-plan 以 feedback loop 審查機制逐步執行。
  當使用者說「specformula」「新需求」「走完整開發流程」「前後端開發」，
  或想對一個需求走 BDD 全流程時觸發。
  前提：arguments.yml 已存在（/aibdd-kickoff 已完成）。
---

# 角色

需求工程計畫產生器。你將任意需求轉化為結構化工程計畫，產出 plan.md + Phase 卡片，
然後委派 `/aibdd-carry-on-engineering-plan` 以 human-in-the-loop 審查機制逐步執行。

**你不負責審查迴圈** — 審查、簽核、consistency check 全部由 carry-on 處理。
**你負責的是「做什麼」** — carry-on 負責「怎麼走」。

---

# 前置條件檢查

啟動後立即檢查，任一不滿足則停止並告知使用者：

```
1. arguments.yml 存在？
   → 不存在：「請先執行 /aibdd-kickoff 初始化專案。」

2. 技術棧可辨識？
   → 從 arguments.yml 讀取 tech_stack + test_strategy
   → 決定 Phase 05 使用的 control-flow skill（python/java/typescript）

3. 計畫目錄路徑？
   → 詢問使用者或使用預設：${PROJECT_ROOT}/plans/{requirement-slug}/
```

---

# 計畫產生流程

## Step 1：蒐集需求

接收使用者的需求描述（raw text、截圖、文件均可）。
以 1-2 句話摘要需求核心，確認理解正確後進入 Step 2。

## Step 2：決定 Scope 與變數

根據 arguments.yml 填入模板變數：

| 變數 | 來源 | 範例 |
|------|------|------|
| `${LANG}` | arguments.yml → tech_stack | `python` / `java` |
| `${TEST_STRATEGY}` | arguments.yml → test_strategy | `e2e` / `ut` |
| `${SPECS_ROOT_DIR}` | arguments.yml → specs_root | `specs/` |
| `${PROJECT_ROOT}` | arguments.yml → project_root | `.` |
| `${FEATURES_DIR}` | arguments.yml → features_dir | `specs/features/` |
| `${PLAN_DIR}` | 使用者指定或預設 | `plans/crm-dashboard/` |

## Step 3：產生計畫資料夾

執行 `scripts/generate-plan.py`，一次產出 plan.md + 8 張 Phase 卡片：

```bash
uv run .claude/skills/aibdd-specformula/scripts/generate-plan.py \
  --slug "${REQUIREMENT_TITLE}" \
  --summary "${REQUIREMENT_SUMMARY}" \
  --project-root "${PROJECT_ROOT}"
```

腳本自動：讀 `arguments.yml` → 偵測技術棧 → 對 `assets/` 下 9 個模板做 `${VAR}` 替換 → 寫入 `plans/{slug}/`。

## Step 4：展示 + 委派

展示已產生的計畫：
- plan.md 中的 Dependency Graph
- todo/ 中的 8 張卡片名稱
- 提示：「計畫已產生，開始執行？」

使用者確認後：
- 將 plan.md 的 Status 從 DRAFT 改為 IN_PROGRESS
- **DELEGATE `/aibdd-carry-on-engineering-plan`**，傳入 `${PLAN_DIR}` 路徑

---

# Phase 概覽

## External Quality（外部品質）

站在使用者/業務方的角度——系統「做什麼」「資料長什麼樣」「行為規格夠不夠精準」。

| Phase | 名稱 | Asset 卡片 | 觸發 Skill | 核心產出 |
|-------|------|-----------|-----------|---------|
| 01 | Requirement Analysis | `assets/01-requirement-analysis.md` | `/aibdd-discovery` | Execution Plan + Activity Diagrams + Feature Rules |
| 02 | Entity Modeling | `assets/02-entity.md` | `/aibdd-form-entity-spec` | erm.dbml |
| 03 | BDD Analysis | `assets/03-bdd-analysis.md` | `/aibdd-form-bdd-analysis` | 系統抽象 + 句型模型 + Feature Examples |
| 04 | API Contract | `assets/04-api-contract.md` | `/aibdd-form-api-spec` | api.yml |

**統一流程** — 不區分 greenfield / 新功能 / 改變需求。每個需求都是 current state → desired state 的 delta 操作。Phase 01 產出 Execution Plan，決定 Phase 02-08 各自的工作範圍。

推理順序：**意圖 + 影響評估 → 行為 → 資料 → 規格精煉 → 實作契約**

- 01：理解意圖 + 掃描現狀 + 計算 delta → Execution Plan + 行為結構
- 01→02：有了行為（features）才能推導「作用在什麼實體上」
- 02→03：有了實體結構（erm.dbml）才能寫出精準的 Examples
- 03→04：每個 command/query 天然對應一個 API endpoint

**Reconciler 架構** — Phase 02-04 的 form skill 均以 desired-state reconciliation 運作（derive desired → read current → compute diff → preview → apply）。共用合約見 `aibdd-core/references/reconciler-contract.md`。

## Implementation（實作）

| Phase | 名稱 | Asset 卡片 | 觸發 Skill | 核心產出 |
|-------|------|-----------|-----------|---------|
| 05 | Backend TDD | `assets/05-backend-tdd.md` | `/aibdd-auto-control-flow` | Step Defs + Models + Endpoints + Migrations |
| 06 | Frontend Build | `assets/06-frontend-build.md` | 3 frontend skills | frontend/ 完整可運行 |
| 07 | Frontend E2E | `assets/07-frontend-e2e.md` | activity-testplan + Chrome | mock 模式全通過 |
| 08 | Integration Validation | `assets/08-integration.md` | Chrome E2E real mode | real backend 全通過 |

---

# Phase 間依賴

```
01 → 02 → 03 → 04 ──┬──→ 05 ──┐
                     │         │
                     └──→ 06 → 07 ──→ 08
                                      ↑
                               05 ────┘
```

- Phase 01→02→03→04：嚴格串行（每步依賴前步產出）
- Phase 05 & 06：互不依賴，可由兩個 AI 平行執行（carry-on 的 `doing/` 資料夾作為 lock）
- Phase 07：依賴 06（需要 Pages 已建好）
- Phase 08：依賴 05 + 07（前後端都完成）

---

# 共同契約

External Quality（Phase 01-03）的產出物是後續所有 Phase 的共同依據：

| 產物 | 產出 Phase | 消費者 |
|------|-----------|--------|
| Execution Plan | 01 | 02-08（各 Phase 的 scope 依據） |
| Activity Diagrams | 01 | 07（Test Plan 結構） |
| Feature Files（Rules） | 01 | 02（實體推導依據）、03（BDD Analysis 輸入） |
| Feature Files（含 Examples） | 03 | 04（API 推導）、05（TDD 循環） |
| erm.dbml | 02 | 03（Examples 欄位/邊界值）、05（Schema Analysis） |
| api.yml | 04 | 05（Red 欄位守衛）、06（MSW handlers）、08（驗證基準） |

---

# Context Management

詳見 `references/context-management.md`。核心摘要：

## 三層持久化

| 層 | 載體 | 持久性 | 內容 |
|----|------|--------|------|
| 1 | 檔案系統 | 最持久 | plan.md + 卡片位置 + 簽核 + clarify-log |
| 2 | TodoWrite | 跨 compaction | specformula 8 任務（每 Phase 1 個）/ 各 Phase 內部自管細節 |
| 3 | Context Window | 最易失 | 當前步驟的審查狀態 |

## Compact Proof 層次化

specformula 層管 **8 個 TodoWrite 任務**（每 Phase 1 個）。
每個 Phase 內部由對應 skill 自己展開自己的細節任務，不混在一起。

## Lazy Loading

每個 Phase 只載入當前需要的 skill。跨 skill 切換時必定重新 LOAD（non-negotiable）。

---

# 規則

1. **前置條件不可跳過。** arguments.yml 不存在就停止，不嘗試繼續。
2. **卡片格式必須匹配 carry-on。** 2 個審查步驟（相關規格/交付物）+ 交付物狀態表。
3. **Feature Files 是 Single Source of Truth。** Phase 01 產出 Rules，Phase 03 補上 Examples，Phase 04 從中推導 api.yml。
4. **bdd-analysis 不可跳過。** Phase 03 是 External Quality 的精煉階段，不可從 Rules 直接跳到實作。
5. **erm.dbml 先於 BDD Analysis。** Phase 02 在 Phase 03 之前——Examples 需要實體結構作為輸入。
6. **api.yml 是推導產物。** Phase 04 從 features 的 command/query 機械映射，不是獨立設計決策。
7. **不自己做審查。** 產生計畫後立即委派 carry-on，不重新發明輪子。
8. **卡片用絕對路徑。** 所有產物路徑一律絕對路徑，carry-on 需要。
9. **Phase 05 & 06 可平行。** plan.md 的 Dependency Graph 必須正確反映這一點。
10. **Integration Validation 是正式 Phase。** 不是 Gate、不是檢查清單 — 有完整卡片和 2 步審查。
