---
name: aibdd-form-feature-spec
description: Feature 視圖的 Spec Skill。從 .feature 骨架（含便條紙）、ES spec 或 User idea 出發，澄清並產出完整的 Gherkin Feature File。可被 /discovery 調用，也可獨立使用。
user-invocable: true
---

## I/O

| 方向 | 內容 |
|------|------|
| Input | .feature skeleton (from /aibdd-form-activity) &#124; `${ES_SPEC_PATH}` (ES spec) &#124; User idea |
| Output | `${FEATURE_SPECS_DIR}/*.feature` |

# 行為探索

## References 導覽

| 檔案 | 何時載入 | 內容 |
|------|---------|------|
| `references/rule-writing-guide.md` | 撰寫 Rule + Example | Rule 命名原子化、資料驅動原則、Given 設定、Key 識別、When 格式 |
| `references/coverage-checklist.md` | Quality Gate（F1-F6） | 6 面向覆蓋率清單，被 /discovery Step 7 調用 |

---

## 執行流程

### 輸入來源判斷

**輸入來源一：`.feature` 骨架（含便條紙）**

來自 `/aibdd-form-activity` 連動生成的骨架。骨架已有 `@ignore @command` / `@ignore @query` + Feature header + 部分 Rule 框架。

執行方式：
1. 讀取骨架中的所有便條紙（`CiC(<CATEGORY>): ...`），整理成待澄清清單
2. 能直接推斷的便條紙（如格式明顯的假設）靜默處理，直接填入 + 刪除便條紙
3. 無法推斷的便條紙進入澄清模式，逐一解決
4. 所有便條紙解決後，填入完整的 Rule + Example，移除所有 `(待澄清)` 佔位

**輸入來源二：`${ES_SPEC_PATH}`（Event Storming spec）**

直接採用 ES 中的 Commands 與 Read Models。每個 Command 對應一個 Feature file（Command 類型），每個 Read Model 對應一個 Feature file（Query 類型）。不重新識別，不合併，不拆分。ES 中的 Actor、Aggregate、Rules、Description 作為澄清起點，僅對 `(待澄清)` 欄位進行澄清。

**輸入來源三：User idea（raw text）**

解析 idea，識別 Command（改變系統狀態的操作）與 Query（讀取狀態的查詢操作）。

---

### 功能識別

1. 依輸入來源確認功能清單（.feature 骨架已有功能清單；ES / idea 則識別後列出）
2. 列表呈現給用戶確認：會開出幾個 Feature、哪些是 Command 類型、哪些是 Query 類型
3. 確認後進入草稿模式或澄清模式

### 草稿模式（ES 項目已 clear）

**當 ES 項目無 `(待澄清)` 標記時，AI 直接根據 ES 的 Rules、參數、Aggregate 生成完整的 Feature File 草稿，不逐條提問。**

- ES 中的每條原子規則 → 對應一條 Gherkin Rule + Example
- AI 自行推斷具體的 datatable 測試資料（如用戶名 `Alice`、商品 ID `1`、價格 `50`）
- 草稿產出後由協調器統一展示，用戶審閱確認或糾正

### 澄清模式（逐一功能處理）

針對含便條紙、含 `(待澄清)` 的功能，或 raw idea 輸入，按以下固定順序澄清其規則：

1. **前置（狀態）** — 操作前系統必須滿足什麼狀態？
2. **前置（參數）** — 輸入參數有什麼約束？
3. **後置（回應）** — 操作回傳什麼內容？（主要用於 Query）
4. **後置（狀態）** — 操作成功後系統狀態如何變化？（主要用於 Command）

每條規則依照協調器定義的澄清循環進行：提問 → 更新 → 確認 → 下一題。

一個功能的所有規則皆為 clear 後，進入下一個功能。

---

## 便條紙格式（強制規範）

**完整格式定義、品質標準與範例見 `../aibdd-form-activity/references/cic-format.md`。**

本 skill 使用 Gherkin 註解前綴：`# CiC(<CATEGORY>): ...`

---

## Feature File 格式

**關鍵字一律使用英文：Feature / Rule / Example / Given / When / Then / And / But。檔案開頭不標註語言。**

**本關注點產出的所有 Feature File 必須在最上方標註 `@ignore @command`（Command 類型）或 `@ignore @query`（Query 類型）。**

```gherkin
@ignore @command
Feature: <功能名（Command 類型）>

  Background:
    Given <全部 Example 共用的前置條件，使用具體 datatable>

  Rule: 前置（狀態）- <主詞>必須<單一條件>

    Example: <情境條件>時<預期結果>
      Given <前置條件>
      When <操作>
      Then 操作失敗，錯誤為"<具體錯誤訊息>"

  Rule: 前置（參數）- <主詞>必須<單一條件>

    Example: <情境條件>時<預期結果>
      Given <前置條件>
      When <帶有不合法參數的操作>
      Then 操作失敗，錯誤為"<具體錯誤訊息>"

  Rule: 後置（回應）- <主詞>應<單一條件>（用於 Query）

    Example: <情境描述>
      Given <前置條件>
      When <操作>
      Then 操作成功
      And 查詢結果應包含：
        | 欄位1 | 欄位2 |
        | 值1   | 值2   |

  Rule: 後置（狀態）- <主詞>應<單一條件>（用於 Command）

    Example: <情境描述>
      Given <前置條件>
      When <操作>
      Then 操作成功
      And <狀態驗證>
```

### Example 步驟數量

每個 Example 建議 3-5 步（不含 Background）。超過 5 步時，檢查是否：
- 某些 Given 可以提取到 Background
- 多個 Then/And 斷言可以合併為一個 datatable 驗證
- 該 Example 其實在測試多個行為，應拆分為多個 Example

### Example 標題命名

Example 標題描述「什麼情境 → 什麼結果」，讓測試失敗時能立刻定位問題。

**句型：** `<情境條件>時<預期結果>`（失敗場景）或 `<操作描述>後<預期結果>`（成功場景）

**正確：**
```gherkin
Example: 已購買旅程的用戶再次購買時操作失敗
Example: 使用已過期折扣券時操作失敗
Example: 影片進度達到 100% 時課程自動完成
Example: 建立多個商品的訂單後總價正確計算
```

**錯誤（模糊）：**
```gherkin
Example: 使用折扣券
Example: 測試失敗場景
Example: 正常情況
```

### Background 節制原則

Background 僅包含「所有 Example 都需要」的共用前置條件。逐條檢查 Background 中的每個 Given 步驟及 datatable 中的每一行資料，確認它被多數 Example 引用。若某筆資料只被 1-2 個 Example 使用，應移入那些 Example 的 Given 中。

**原則：讀者在讀一個 Example 時，不應為了理解它而去 Background 中搜尋只跟這個 Example 有關的資料。**

---

**Rule 撰寫指南**：Read `references/rule-writing-guide.md`（Rule 命名原子化、資料驅動原則、Given 設定方式、Key 識別規則、When 步驟格式）。

---

## 核心約束

**嚴格遵守用戶提供的資訊，不添加、不假設、不推測任何未明確說明的內容。**

**Feature file 的讀者是不了解功能細節的人。** 每一步都應該用業務語言描述，不依賴讀者對系統內部模型的理解。

**每個 Example 獨立執行。** Example 之間不共享可變狀態、不依賴執行順序。

---

## 完成條件

所有功能的所有規則皆為 clear、所有便條紙已解決、無 `(待澄清)` 佔位時，輸出完整的 Feature File，告知用戶行為探索已完成。

---

## 面向覆蓋率清單（F1-F6）

被 /discovery Step 7 調用。**完整清單**：Read `references/coverage-checklist.md`。

便條紙清零後，逐一過 F1-F6 六個面向，標記 `Clear` / `Partial` / `Missing`。對 `Missing` / `Partial` 面向補寫便條紙，重新進入澄清循環。所有面向 `Clear` 後通知 `/discovery` 放行。
