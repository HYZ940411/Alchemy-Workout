---
name: aibdd-form-bdd-analysis
description: >
  系統抽象驅動的 BDD 分析（Reconciler）。從已確認的 .feature Rule 骨架推導系統抽象、
  實體句型模型與覆蓋矩陣，再據此產出最小必要句型集的 .feature 檔案（含 Examples）。
  以 desired-state reconciliation 模式運作：三階段各自讀取現有 artifact →
  推導 desired state → 計算 diff → 增量更新。Greenfield 時 current = 空。
  善用 Scenario Outline + Examples 做 Data-Driven 測試，
  善用 Data Table 承載結構化輸入與驗證。
  支援 Boundary 偵測——偵測到 Web Backend 時載入內建 preset（句型分析方針 + Handler 決策樹）。
  由 /aibdd-discovery 在 Strategic 完成後、Tactical 開始前 DELEGATE 觸發。
---

# BDD 分析：系統抽象驅動的可執行規格產出（Reconciler）

從已確認的 .feature Rule 骨架出發，經三階段推導，產出最小必要句型集的 `.feature` 檔案（含具體 Examples）。

**Reconciler 合約**：啟動時 Read `aibdd-core/references/reconciler-contract.md`，全程遵循。

## 核心概念：Boundary → Operation → Handler

| 層級 | 定義 | 範例 |
|------|------|------|
| **Boundary** | 要測試的系統邊界 | `web-backend`（後端 API + DB） |
| **Operation** | 該邊界上可測試的操作 | 每個 API endpoint |
| **Handler** | 每種 Gherkin 句型對應的測試部位 | 6 種 web-backend handler |

## 4 種抽象測試角色（系統無關）

| 角色 | Gherkin 位置 | 職責 |
|------|-------------|------|
| **States Prepare** | Given | 直接注入狀態，繞過系統邊界 |
| **Operation Invocation** | Given / When | 調用系統操作 |
| **Operation Result Verifier** | Then | 驗證操作的直接輸出 |
| **States Verify** | Then | 驗證操作後的系統內部狀態 |

## 與非腦補原則的關係

**Examples 可從已確認的 Rule 系統性推導——這是分析，不是腦補。**

- Rule 已確認 → 可推導 Examples
- Rule 未確認（仍有 CiC） → 不可推導
- Rule 不存在 → 不可編造

## 輸入

- **features 資料夾路徑**：`${FEATURE_SPECS_DIR}`
- **已確認的 .feature 檔案**：含 Rule 骨架、已解決所有 CiC
- **Execution Plan scope**：哪些 domain 需要分析（create/modify）
- **Clarify Session**：`${CLARIFY_DIR}` 中的澄清紀錄

## 產出結構

```
${FEATURE_SPECS_DIR}/
├── 系統抽象.md              # 第一階段
├── {domain}/
│   ├── 句型.md              # 第二階段
│   └── *.feature            # 第三階段
└── ...
```

---

## 執行流程（三階段 Reconciliation）

每個階段都是獨立的 reconciler：derive desired → read current → diff → preview → apply。

```
1. 第一階段：系統抽象 Reconciliation
   ├── derive desired 系統抽象（從所有 scope 內 features）
   ├── read current 系統抽象.md（不存在 = greenfield）
   ├── compute diff → preview → apply
   └── 展示 → 等待使用者審核

1.5 Boundary 偵測
   ├── 有 erm.dbml → boundary = web-backend
   │   → Read references/web-backend/句型分析方針.md
   │   → 後續句型分類使用 web-backend Handler 決策樹
   └── 其他 → 使用通用推導（4 抽象角色框架，無 preset）

2. 確認目標 domain（從 scope + features/ 子目錄推導）

3. 第二階段：句型模型 Reconciliation（per domain）
   ├── derive desired 句型集（從該 domain 的 features，直接分析所有句型）
   ├── read current {domain}/句型.md（不存在 = greenfield）
   ├── compute diff → preview → apply
   └── 展示 → 等待使用者審核

3.5 共用句型萃取（僅多 domain 時觸發）
   ├── 條件：scope 內有 2+ domain
   │   ├── 掃描所有 domain 句型.md，找出句型文字完全相同的句子
   │   ├── 搬至系統抽象.md 共用句型 section
   │   └── 各 domain 句型.md 替換為引用（→ 見系統抽象 G1）
   └── 只有 1 個 domain → 跳過，不萃取共用句型

4. 第三階段：Feature Examples Reconciliation
   ├── derive desired Examples（從句型.md + QA 五維分析）
   ├── read current .feature（可能有舊 Examples 或 @ignore）
   ├── compute diff → preview → apply
   └── 展示摘要 → 等待使用者審核
```

### 三階段的 Diff 邏輯

**第一階段（系統抽象）diff**：

| 類型 | 條件 | 範例 |
|------|------|------|
| modify | 既有操作分類變更 | Lead scoring 從 Query → Mutation |
| modify | 共用句型需更新 | 新增共用 Given 句型 |
| create | 新操作 | scoring-rules 操作 |
| create | 新共用契約 | 新 violation pattern |

**第二階段（句型模型）diff**：

| 類型 | 條件 | 範例 |
|------|------|------|
| modify | 既有句型需新增參數 | Lead 的 Given 加 score 欄位 |
| modify | 覆蓋矩陣需更新 | 新增 scoring 相關的 Then 句型 |
| create | 新 domain | journey/ 全新分析 |
| create | 既有 domain 新句型 | lead/ 加 scoring 句型 |

**第三階段（Examples）diff**：

| 類型 | 條件 | 範例 |
|------|------|------|
| modify | 既有 Scenario 的 Examples 需更新 | Lead 建立加 score 欄位 |
| create | 新 Scenario Outline | Journey 的所有 scenarios |
| delete | 不再需要的 Example 行 | 需使用者確認 |

---

## 第一階段：系統抽象

產出 `features/系統抽象.md`。

### 推導步驟（嚴格按順序）

1. **辨識操作** — 從所有 scope 內 .feature 的 Rule 列舉所有對外操作
1b. **拆解系統前置狀態** — 從操作的 Rule 反推狀態部件
2. **辨識實體** — 從操作反推 Aggregate 或 Gateway
3. **操作分類** — 按行為形狀分群（Creation / Mutation / Query / Diagnostic）
4. **萃取共用契約** — 跨 domain 重複的 postcondition、violation、I/O 模式
5. **辨識變異點** — 各 domain 特有行為

> **句型不在此階段萃取。** 句型的 single source of truth 在各 domain 的句型.md（Stage 2）。
> 只有在 Stage 2.5（所有 domain 分析完成後）才萃取真正跨 domain 共用的句型。

### 輸出格式

Read `assets/system-abstraction.template.md` 取得模板。

---

## 第二階段：實體句型模型

對每個 scope 內的 domain 產出 `features/{domain}/句型.md`。

### 推導步驟

1. **句型分類**：
   - **若 boundary = web-backend**：Read `references/web-backend/句型分析方針.md`，用 Handler 決策樹分類
   - **若無 preset**：使用 4 抽象角色從行為形狀推導
2. **列舉操作與參數** — 提取 When Data Table、Then Data Table、violation_type
3. **產出完整句型清單** — 該 domain 所需的 Given / When / Then 全部列於此，不分繼承/專屬
4. **QA 分析** — Read `references/qa-analysis-guide.md`，五維分析
5. **Scenario 結構決策** — Read `references/feature-writing-rules.md` Rule 5
6. **產出覆蓋矩陣**

> **句型清單是 single flat list。** 不分「繼承自系統層」與「本 domain 專屬」。
> 所有該 domain 需要的句型統一列出，避免與系統抽象.md 的資料重複。

### 輸出格式

Read `assets/sentence-model.template.md` 取得模板。

---

## 第三階段：產出 `.feature` 檔案（填入 Examples）

### 撰寫規則

Read `references/feature-writing-rules.md` 取得完整 9 條規則。

### 填入策略

對每個 scope 內的 .feature 檔案：
1. 保留所有已確認的 Rule（不修改 Rule 文字）
2. 移除 `# ⚠ Example 區段` 標記
3. 移除 `@ignore` tag
4. 依句型.md 的覆蓋矩陣填入 Scenario Outline / Scenario + Examples
5. Data Table 欄位名與 Rule 確認的欄位 1:1 對應
6. Examples 從 QA 五維分析推導，使用具體值（Spec by Example）

### Feature File 結構

Read `assets/feature-file.template.gherkin` 取得模板。

---

## IMPL_IMPACT 產出規則

第三階段（Feature Examples）的每個 **modify** 操作評估對 implementation 的影響。這是最關鍵的 IMPL_IMPACT 來源——Gherkin 句型變更直接影響 Step Definitions。

| .feature Diff | Impact Type | Phase | 影響目標 |
|---------------|-------------|-------|---------|
| Given datatable +column | `DATATABLE_SCHEMA` | 05 | Step Def 的 table 解析（欄位數變更） |
| Given datatable -column | `DATATABLE_SCHEMA` | 05 | Step Def 的 table 解析 + 可能影響 Model |
| Given 句型文字變更 | `SENTENCE_PATTERN` | 05 | Step Def pattern/regex 斷裂 |
| When 參數增刪 | `SENTENCE_PATTERN` | 05 | Step Def 的 When handler 參數解析 |
| When 句型文字變更 | `SENTENCE_PATTERN` | 05+06 | Step Def + Frontend 操作觸發點 |
| Then datatable +column | `DATATABLE_SCHEMA` | 05 | Step Def 的 Then 驗證邏輯 |
| Then 句型文字變更 | `SENTENCE_PATTERN` | 05 | Step Def pattern/regex 斷裂 |
| Examples +row | （無 IMPL_IMPACT） | — | 新 test case，既有 Step Def 不受影響 |
| Examples -row | （無 IMPL_IMPACT） | — | 少跑一個 case，不影響 implementation |
| 新 Scenario Outline（create） | `NEW_OPERATION` | 05 | 需要新 Step Def（若句型是新的） |

**關鍵判斷**：只有**句型結構**（Given/When/Then 的文字 pattern 或 DataTable schema）變更才產出 IMPL_IMPACT。Examples 行的增減不影響 implementation（Step Def 是 parameterized 的）。

change_summary 中附帶 IMPL_IMPACT 表，格式見 `aibdd-core/references/reconciler-contract.md`。

---

## 規則

1. **先分析再產出。** 絕不跳過系統抽象和句型模型直接填 Examples。
2. **每一層都需使用者審核。** 系統抽象.md → 確認 → 句型.md → 確認 → .feature → 確認。
3. **句型.md 是 .feature 的 single source of truth。**
4. **不發明無依據的句型。** 必須追溯到系統抽象的行為分類。
5. **QA 分析不可省略。** 五維分析，即使不適用也要標註。
6. **具體資料，不用白話。** Spec by Example。
7. **Rule 已確認才可推導。** 只從已通過 CiC 歸零的 Rule 推導 Examples。
8. **Reconciler 先改後增。** modify 既有 artifacts 先於 create 新 artifacts。
9. **Scope 限定。** 只處理 Execution Plan 標記的 domain，不動未受影響的 artifacts。
10. **IMPL_IMPACT 必須評估。** 每個 modify 操作的 change_summary 必須包含 IMPL_IMPACT 標記。
