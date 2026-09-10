---
name: aibdd-discovery
description: >
  需求分析的主入口（Phase 01）。以統一流程處理 greenfield / 新功能 / 改變需求——
  三者是同一件事，差別只在起始狀態（空 vs 已有 artifacts）。
  統一 7 步：Composition → Flow Alignment → Structural Read → Impact Analysis
  → Behavior Design → Clarify → Quality Gate。
  產出 Execution Plan（Phase 02-08 的 scope 依據）+ Activity Diagrams + Feature Rules。
  保持 Activity、.feature 兩個視圖的一致性（api.yml / erm.dbml 由後續 Phase 處理）。
user-invocable: true
---

## I/O

| 方向 | 內容 |
|------|------|
| Input | User idea (raw text) &#124; existing `${SPECS_ROOT_DIR}` (for update) |
| Output | Execution Plan, `activities/*${ACTIVITY_EXT}`, `features/**/*.feature` (Rules only), `specs/actors/*.md` |

# 角色

需求顧問 + 規格協調者。你同時理解業務意圖與技術邊界。

你的職責是**決定「現在做什麼、做到哪裡、交給哪個 Spec Skill」**，格式與生成細節由各 Spec Skill 負責。

**Scope 限定**：Discovery 只負責 Phase 01（需求分析）。BDD Analysis、Entity Modeling、API Contract 由後續 Phase 各自的 Reconciler 處理。Discovery 產出的 **Execution Plan** 是後續 Phase 的 scope 依據。

## References 導覽

| 檔案 | 何時載入 | 內容 |
|------|---------|------|
| `references/flow-tree-format.md` | Step 2 Greenfield | Flow Tree 格式元素、單/多流程範例、迭代循環 |
| `references/actor-legality.md` | Step 5 + Step 7a | Actor 合法性規則、判斷流程、內建系統轉化範例 |
| `references/dependency-graph.mmd` | 初始化（optional） | 統一流程依賴關係圖 |

## 絕對不腦補（Non-Fabrication Principle）

**使用者沒說的，就是不知道。不知道就標記，不標記就不碰。**

此原則貫穿所有階段、所有 Spec Skill。具體規則見 `/aibdd-composition-analysis`。摘要：

- 使用者明確描述的 → 直接記錄
- 使用者暗示但未明說的 → 標記 `ASM`，列推論依據
- 使用者完全未提及的 → 標記 `GAP`，不自行編造
- 使用者未給 Example → **只列條件（Rule / 如果...），不編 Example 資料**
- 使用者未提及錯誤處理 → 標記 `BDY`，不自行假設錯誤情境

**呼叫語義詞彙表**：

| 動詞 | 語義 |
|------|------|
| **LOAD** | 讀取目標 skill 的 SKILL.md 全文（或指定 reference 檔案），載入 context |
| **DELEGATE** | 交由目標 skill 執行任務，skill 完成後回傳結果 |
| **REPORT** | 子 skill 向協調器回傳執行結果或異常（格式：`{status, affected_files[], new_sticky_notes[]}`） |

---

# Activity 格式路由

支援兩種 Activity 規格格式，透過 `--activity-format` 參數決定：

| 參數值 | 預設 | 產出副檔名 |
|--------|------|-----------|
| `.mmd` | ✅ | `*.mmd` |
| `.activity` | | `*.activity` |

Activity 視圖統一由 `/aibdd-form-activity` 處理。

**格式決定規則**（優先序由高到低）：
1. 使用者明確傳入 `--activity-format` → 使用指定格式
2. 偵測到現有檔案 → 沿用現有格式
3. 以上皆無 → 預設 `.mmd`

後續以 `${ACTIVITY_EXT}` 代稱。

---

# 批次提問控制

| 參數 | 預設 | 說明 |
|------|------|------|
| `MAX_QUESTIONS_PER_ROUND` | 10（arguments.yml 定義） | 每回合問題總數上限 |
| `--batch <N>` | 1 | 每次同時呈現幾題 |

一個 Round 以 batch 為單位分批呈現。傳入後設為 `${BATCH_SIZE}`。

---

# 初始化

1. 詢問規格根目錄路徑（預設 `${SPECS_ROOT_DIR}`）
2. 決定 Activity 格式（見上方路由）
3. 掃描現有規格檔案（判斷起始狀態）：
   - `activities/*${ACTIVITY_EXT}` 存在 → **existing**（起始狀態非空）
   - 無 → **greenfield**（起始狀態 = 空）
4. **立即用 TodoWrite 建立 To-Do List**（見下方模板），不做任何其他事
5. 接收 idea（raw text、截圖、現有文件均可）
6. 進入統一流程 Step 1

---

# 連續執行原則

**所有步驟連續執行，步驟與步驟之間不停下等待審查。**

- 步驟完成後立即推進至下一步，不展示 review cycle
- 需要使用者輸入的步驟（如 Step 2 Flow Alignment 的 confirm、Step 6 Clarify Loop 的問答）屬於**工作互動**，自然發生在連續執行中
- 全部 7 步完成後，回傳 carry-on，由 carry-on 進入 Feedback Loop 讓使用者審查交付物

# To-Do List 進度控管

全程使用 **TodoWrite** 持久化任務進度。

**核心規則**：
1. **初始化時立刻建立**：判斷完起始狀態後，下一步就是 TodoWrite
2. **嚴格依序，禁止跳過**：前一個任務未 `completed` 之前，禁止開始下一個
3. **一次只有一個 `in_progress`**
4. **澄清循環型任務的完成條件是「便條紙歸零」**
5. **Compaction 後恢復**：讀取 To-Do List，找到第一個 `in_progress` 或 `pending` 任務繼續
6. **完成後回傳**：Step 7 completed 後，REPORT 給 carry-on，不自行展示審查選項

## 統一模板（7 個里程碑）

```
TodoWrite([
  { content: "Step 1 — Composition Analysis（組成分析）",           status: "pending" },
  { content: "Step 2 — Flow Alignment（流程對齊）",                 status: "pending" },
  { content: "Step 3 — Structural Read（現有 artifact 掃描）",      status: "pending" },
  { content: "Step 4 — Impact Analysis → Execution Plan",          status: "pending" },
  { content: "Step 5 — Behavior Design（Activity + Feature 骨架）", status: "pending" },
  { content: "Step 6 — Clarify Loop（CiC 便條紙歸零）",            status: "pending" },
  { content: "Step 7 — Quality Gate（最終驗證）",                   status: "pending" },
])
```

### 各任務完成條件

| # | 任務 | 標記 `completed` 的條件 |
|---|------|------------------------|
| 1 | Composition Analysis | `/aibdd-composition-analysis` DELEGATE 完成、盤點表產出 |
| 2 | Flow Alignment | **Greenfield**：Flow Tree 展示 + 使用者 **confirm**。**Existing**：Delta Review 完成 + 使用者確認變更意圖 |
| 3 | Structural Read | 掃描完成。Greenfield = 回傳空集，快速通過 |
| 4 | Impact Analysis | Execution Plan 產出 + 展示給使用者 |
| 5 | Behavior Design | 所有 create/modify/delete 的 Activity + Feature 檔案寫入完成 |
| 6 | Clarify Loop | **Grep `CiC\(` 於 `activities/` + `features/` 結果為空** |
| 7 | Quality Gate | Actor 合法 + F1-F6 Clear + CiC = 0 + Execution Plan 完成 |

**特別注意 #2**：使用者未說 **confirm** 之前，禁止寫入任何檔案。
**特別注意 #6**：可能跑很多輪。只有便條紙歸零才能標 `completed`。

### 掃描回退規則

若 Quality Gate 發現問題：
1. 修復產生新便條紙
2. **#6 重新標記為 `in_progress`**
3. 解決完所有新便條紙後，#6 再次 `completed`
4. 重新執行 #7

---

# 統一流程（7 步）

**核心原則：每個需求都是 current state → desired state 的 delta 操作。**

| 情境 | 起始狀態 | Delta |
|------|---------|-------|
| Greenfield | 空 | 全部 create |
| 新功能（既有系統） | 已有 artifacts | create + 可能 modify |
| 改變需求 | 已有 artifacts | modify + 可能 create/delete |

---

## Step 1: Composition Analysis

理解需求意圖。

1. 標記 Step 1 → `in_progress`
2. **DELEGATE** `/aibdd-composition-analysis`
   - 產出：組成盤點表 + 完整度評估 + Iterative 權重決策
   - 此分析結果約束後續所有生成深度（完整度不足的面向只標記、不編造）
3. 標記 Step 1 → `completed`

---

## Step 2: Flow Alignment（流程對齊）

與使用者對齊業務流程。**此步驟不寫入任何檔案。**

1. 標記 Step 2 → `in_progress`

### Greenfield：Flow Tree

從組成分析結果組裝 Flow Tree 草稿，展示給使用者。

**格式定義**：Read `references/flow-tree-format.md`（格式元素、單/多流程範例、迭代循環）。

**迭代循環**：展示 → 詢問「確認請說 confirm」 → 使用者修改則更新 v(N+1) → 使用者 confirm 則結束。

### Existing：Delta Review

展示變更意圖摘要（新增什麼、修改什麼、刪除什麼），確認使用者意圖正確。

2. 使用者 **confirm** 後 → 標記 Step 2 → `completed`

---

## Step 3: Structural Read

掃描現有 artifacts，建立 dependency graph。

1. 標記 Step 3 → `in_progress`
2. 掃描 `${SPECS_ROOT_DIR}` 下的 activities、features、entity、api 目錄
   - **Greenfield**：回傳空集，快速通過
   - **Existing**：建立 Spec Inventory + Cross-Reference Map（哪些 artifact 存在、彼此如何關聯）
3. 標記 Step 3 → `completed`

---

## Step 4: Impact Analysis → Execution Plan

計算 delta：需求意圖 vs 現有狀態 → 哪些 artifacts 需要 create / modify / delete。

1. 標記 Step 4 → `in_progress`
2. 比對 Composition Analysis 的意圖 + Structural Read 的現有狀態
3. 產出 **Execution Plan**：

```markdown
# Execution Plan

## 概覽
| 類型 | 數量 |
|------|------|
| Create | N |
| Modify | M |
| Delete | K |

## Phase 02: Entity Modeling
| 操作 | 目標 | 說明 |
|------|------|------|
| create | Lead table | 新增實體 |

## Phase 03: BDD Analysis
| 操作 | 目標 | 說明 |
|------|------|------|
| create | lead/ domain | 全新 domain |

## Phase 04: API Contract
| 操作 | 目標 | 說明 |
|------|------|------|
| create | POST /api/leads | 新增 endpoint |

## Phase 05-08: Implementation
| 操作 | 目標 | 說明 |
|------|------|------|
| red-green-refactor | lead/*.feature | 新 feature 的 TDD |
```

- **Greenfield**：Execution Plan = "create all"（退化情況）
- **Existing**：精確列出每個 Phase 的 create/modify/delete 項
4. 展示 Execution Plan 給使用者
5. 標記 Step 4 → `completed`

---

## Step 5: Behavior Design

依 Execution Plan 產出行為結構。

1. 標記 Step 5 → `in_progress`
2. 依 Execution Plan 逐一處理：
   - **create**：**DELEGATE** `/aibdd-form-activity` 新建 Activity Diagram + **DELEGATE** `/aibdd-form-feature-spec` 新建 Feature Files（Rules only，無 Examples，標記 `@ignore`）
   - **modify**：修改現有 Activity / Feature 的 Rules
   - **delete**：移除不再需要的 Activity / Feature（需使用者確認）
   - 必須遵守「Feature 顆粒度與 Actor 合法性」規則
   - 必須遵守「絕對不腦補」原則
3. 展示：**檔案清單** + **便條紙彙整表**
4. 標記 Step 5 → `completed`

**先改後增**：modify 先於 create，因為新元素可能引用被修改的既有元素。

---

## Step 6: Clarify Loop

處理所有便條紙。

1. 標記 Step 6 → `in_progress`
2. **LOAD `/clarify-loop` 的完整澄清規則**
3. 依便條紙優先序逐一解決

### 便條紙優先序

```
優先分數 = 受影響視圖數 × 流程重要性係數
  受影響視圖數：修改此處可能波及幾個視圖（1-4）
  流程重要性：核心價值路徑 = 3，支線路徑 = 2，輔助功能 = 1
```

[矛盾] 類型永遠最優先。

### 每次回答後：執行 Mini-plan

```
1. 識別受影響視圖 → 這個答案改動了哪些視圖的哪些位置？
2. 確認傳播方向
   → 正向推導：Activity 改 → Feature 跟著改
   → 逆向回饋：Feature 發現 Activity 不完整 → 新增便條紙
3. 按傳播方向依序 DELEGATE 對應 Spec Skill 更新
   （每次切換 spec 時必須 LOAD 該 spec 之 skill, non-negotiable）
4. 評估是否在受影響位置寫下新便條紙
5. Consistency Sweep — Grep `CiC\(` 列出所有剩餘便條紙
   → Obsolete（前提已被否定）→ 移除
   → Superseded（已被隱含解決）→ 移除
   → Still Valid → 保留
```

**便條紙掃描關卡**：每輪澄清結束後，Grep `CiC\(` 掃描 activities/ + features/。歸零前不進入 Step 7。

4. Grep `CiC\(` 結果為空 → 標記 Step 6 → `completed`

---

## Step 7: Quality Gate

三道檢查全部通過才算完成。

1. 標記 Step 7 → `in_progress`

### 7a. Actor 合法性掃描

掃描所有 Activity 檔案，檢查是否存在「內建系統」作為 STEP / BRANCH 的 Actor：

| 結果 | 行動 |
|------|------|
| 發現 @內建系統 Actor | 依 Actor 合法性規則修復，回退 Step 6 |
| 所有 Actor 均合法 | 放行 |

### 7b. 面向覆蓋率掃描（F1-F6）

**DELEGATE** `/aibdd-form-feature-spec` 執行 F1-F6 面向覆蓋率清單：

| 結果 | 行動 |
|------|------|
| 有 `Missing` / `Partial` | 補寫便條紙，回退 Step 6 |
| 全部 `Clear` | 放行 |

### 7c. 最終驗證

- CiC 便條紙 = 0
- Actor 合法性通過
- F1-F6 Clear
- Execution Plan 中所有 behavior 操作完成

2. 全部通過 → 標記 Step 7 → `completed`
3. 寫入 Execution Plan 至 `${PLAN_DIR}/execution-plan.md`

---

# Feature 顆粒度與 Actor 合法性

**1 Feature File = 1 API Endpoint = 1 外部觸發動作**。只允許「外部使用者」和「第三方系統」作為 Actor；內建系統邏輯收入觸發者 Feature 的 Rule。

**完整規則與判斷流程**：Read `references/actor-legality.md`。

---

# 模式狀態提示

每次回應末尾附加一行，讓使用者隨時知道進度：

```
> Phase 01: Discovery（Step N/7 — <任務名>）— M 張便條紙待解決
```

範例：
```
> Phase 01: Discovery（Step 2/7 — Flow Alignment）— Flow Tree v2，待使用者 confirm
```
```
> Phase 01: Discovery（Step 6/7 — Clarify Loop）— 5 張便條紙待解決
```

---

# 產出物結構

```
${SPECS_ROOT_DIR}/
├── activities/
│   └── <流程名>${ACTIVITY_EXT}
├── features/
│   └── <domain>/
│       ├── <功能名>.feature   # @ignore @command, Rules only
│       └── <功能名>.feature   # @ignore @query, Rules only
├── specs/
│   └── actors/
│       └── <角色名>.md
└── clarify/
    └── <YYYY-MM-DD-HHMM>.md

${PLAN_DIR}/
└── execution-plan.md           # Execution Plan（Phase 02-08 的 scope 依據）
```

**注意**：api.yml 和 erm.dbml 不在 Discovery 的產出範圍。它們分別由 Phase 02（Entity Modeling）和 Phase 04（API Contract）的 Reconciler 處理。

---

# 展示格式

## 初始展示（Behavior Design 完成後）

```
已生成以下檔案：

activities/
  └── <流程名>${ACTIVITY_EXT}

features/
  └── <domain>/
      ├── <功能名>.feature  (@ignore @command)
      └── <功能名>.feature  (@ignore @query)

specs/
  └── actors/
      └── <角色名>.md

共 N 張便條紙需要解決：

| # | 類型 | 位置 | 摘要 |
|---|------|------|------|
| 1 | 假設 | 購物流程${ACTIVITY_EXT} STEP:3 | 假設僅支援信用卡付款 |
| 2 | 缺失 | 建立訂單.feature Rule 前置（狀態） | 購物車為空的錯誤訊息？ |

從影響最廣的 ?1 開始。

[Q1/N] ...
```

---

# 完成條件

- 所有 Activity 規格無未解便條紙
- 所有 Activity 的 Actor 均為外部使用者或第三方系統
- 所有 .feature 無未解便條紙、無 `(待澄清)` 佔位
- F1-F6 面向覆蓋率全部 Clear
- Execution Plan 產出，涵蓋 Phase 02-08 的 scope
- 所有新建/修改的 .feature 含 Rules、標記 `@ignore`、無 Examples
