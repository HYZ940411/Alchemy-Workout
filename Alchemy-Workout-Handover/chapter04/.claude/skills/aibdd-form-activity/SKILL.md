---
name: aibdd-form-activity
description: Activity 視圖的 Spec Skill。從 idea 生成 Activity 骨架（.mmd 或 .activity 格式）並連動生成所有綁定檔案（.feature/.md）骨架，不確定處標記便條紙。可被 /discovery 調用，也可獨立使用。支援兩種格式：.mmd（Mermaid flowchart，預設）與 .activity（自訂 DSL）。
user-invocable: true
---

## I/O

| 方向 | 內容 |
|------|------|
| Input | User idea (raw text) &#124; existing .mmd/.activity files (for update) |
| Output | `activities/*.mmd`（或 `*.activity`）, `features/**/*.feature` (skeleton), `specs/**/*.md` (skeleton) |

# 角色

管理 Activity 視圖。將業務流程以 Activity 格式記錄，並連動生成所有綁定檔案的骨架。

---

# Entry 條件

**獨立調用時**，先詢問：
- 規格根目錄路徑（預設 `${SPECS_ROOT_DIR}`）
- 任務類型：**新建**（從 idea 生成）或 **更新**（修改現有檔案）
- Activity 格式：`.mmd`（預設）或 `.activity`

**被 `/discovery` 調用時**，由協調器提供以上資訊（含 `${ACTIVITY_EXT}`），不再詢問。

---

# 語法速查

依當前格式讀取對應的語法參考：

| 格式 | 參考文件 |
|------|---------|
| `.mmd` | `references/syntax-mermaid.md` |
| `.activity` | `references/syntax-activity.md` |

**LOAD 對應的 reference 後再開始生成或更新。**

---

# 從 Idea 生成骨架

## 1. 識別 Actor

從 idea 找出所有參與者。每個 Actor 對應一個 Actor 宣告行，綁定 `specs/actors/<Actor名>.md`。

**Actor 合法性規則依 `/aibdd-discovery` 定義。** 摘要：僅允許「外部使用者」和「第三方系統」作為 Actor，禁止內建系統邏輯作為 Actor。

## 2. 推斷 STEP 序列

從 idea 的業務動詞依序抽出主線步驟：
- 步驟數以「完成業務目標的端到端完整性」為準，不人為壓縮
- 主線 STEP 純數字遞增（1、2、3 …）
- 每個 STEP 的 `@Actor`、label、`{binding}` 皆為選用（sf parser 允許省略），但建議盡量提供以維持可讀性

## 3. 識別 DECISION / FORK

**DECISION**（條件分支）：步驟結果有多種走向時加入。
- id = 上一個 STEP 數字 + 字母後綴（如 STEP:3 後的第一個分支為 `DECISION:3a`）
- Guard 必須窮舉所有條件，不可使用 `_`

**FORK**（並行）：多個動作可同時進行時加入。
- id = 同規則（如 STEP:4 後的第一個並行為 `FORK:4a`）

## 4. 綁定規則

每個 STEP 綁定一個檔案：

| STEP 性質 | 綁定格式 | Feature Tag |
|-----------|---------|-------------|
| Actor 執行改變狀態的操作 | `features/<domain>/<功能名>.feature` | `@ignore @command` |
| Actor 讀取 / 查詢資料 | `features/<domain>/<功能名>.feature` | `@ignore @query` |
| 純 UI 展示 / 頁面呈現 | `specs/ui/<頁面名>.md` | — |

`[ACTOR]` 行統一綁定 `specs/actors/<Actor名>.md`。
同一個 `.feature` 可被多個 STEP 共用（路徑相同即視為同一功能）。

---

# 便條紙生成原則

**便條紙格式與品質標準見 `references/cic-format.md`。** 本 skill 使用的註解前綴依格式而異（`.activity` 直接行末；`.mmd` 使用 `%%` 前綴）。

在以下情況標記便條紙：

| 代碼 | 何時標記 |
|------|---------|
| `AMB` | 需求存在多種合理解讀（含分支條件可能不完整） |
| `ASM` | AI 做了一個未經確認的選擇 |
| `GAP` | 資訊完全缺失，無法確定該步驟的詳細行為 |
| `CON` | 同一流程中前後文衝突 |
| `BDY` | 範圍邊界不明確（含存在其他可行路徑但暫時未建模） |

---

# 輸出格式

## Activity 檔案

依當前格式生成。具體結構見 `references/syntax-mermaid.md` 或 `references/syntax-activity.md`。

## .feature 骨架格式

**先有「如果」（Rule），再有「例如」（Example）。** 推理深度嚴格受組成分析的完整度約束：

| 組成分析結果 | .feature 骨架寫法 |
|-------------|-----------------|
| Rule 已知 | 寫出 `Rule: ...` |
| Rule 推論 | 寫出 `Rule: ...` + `# CiC(ASM): 推論依據` |
| Rule 缺失 | `Rule: (待澄清)  # CiC(GAP): 使用者未提及` |
| Example 使用者有給 | 寫出完整 `Example:` + Given/When/Then |
| Example 使用者沒給 | **不寫 Example**，在 Rule 上標記 `# CiC(GAP): 尚無具體案例` |
| Data 部分已知 | 已知欄位填入，未知用 `(待澄清)` |

```gherkin
@ignore @command
Feature: <功能名>

  Background:
    Given 系統中有以下<主要 Aggregate>：
      | <key欄位> | <欄位1> | <欄位2> |
      | (待澄清)  | (待澄清) | (待澄清) |

  Rule: 前置（狀態）- <使用者提及的約束>  # CiC(ASM): 推論依據：原文「...」

  Rule: 後置（狀態）- <使用者提及的後置效果>  # CiC(GAP): 後置狀態細節？

  # ⚠ Example 區段：使用者未提供具體案例，暫不生成。待澄清後補充。
```

## .md 骨架格式（Actor / UI）

```markdown
# <Actor名 / 頁面名>

CiC(GAP): <不確定的核心特徵>

## 描述
(待澄清)

## 關鍵屬性
- (待澄清)
```

---

# 更新規則

## 收到澄清後

1. **解決便條紙**：定位對應便條紙，刪除 CiC 標記
2. **修改流程**：若澄清導致結構改變，更新對應行（.mmd 格式需同時更新「節點定義」與「邊定義」兩個區段）
3. **新增便條紙**：若修改後暴露出新歧義，在受影響位置追加新便條紙
4. **同步綁定檔案**：若 STEP 的綁定路徑改變，同步更新或新建對應的 .feature / .md 骨架
5. **記錄澄清**：將問答內容寫入 `clarify/<YYYY-MM-DD-HHMM>.md`

## 便條紙刪除規則

每次只刪除「已被澄清的那一張」，其他便條紙不動。

---

# 完成條件

所有 Activity 檔案無未解便條紙（Grep `CiC\(` 結果為空），且所有綁定的 .feature / .md 骨架已建立。
