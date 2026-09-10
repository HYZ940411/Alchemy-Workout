---
name: aibdd-consistency-analyzer
description: >
  對工程計畫的交付物進行結構化 consistency check，產出分類排序的 issue 清單，
  並以互動迴圈逐一詳述、提案、修改。支援 shorthand 命令快速操作。
  當使用者說「consistency check」「challenge」「掃一遍」「consistency analyzer」時觸發。
---

# Consistency Analyzer

對工程計畫的交付物與規格產物進行結構化 consistency check，產出分類排序的 issue 清單，並以互動迴圈逐一處理。

## References 導覽

| 檔案 | 何時載入 | 內容 |
|------|---------|------|
| `references/interaction-protocol.md` | Phase 3 互動迴圈 | Shorthand 命令語法、所有 Modifier 行為、批次操作、展示格式 |

**核心目標：收斂。** 每次 session 都將規格推向更高的 Consistency（內部一致性）與 Completeness（結構完整性）。Clarify Log 記錄每次 session 的問題、決策與修改，確保跨 session 不重複、不倒退、可追溯。

## 輸入

接受以下任意組合：
- 要分析的檔案路徑（如 `spec.md`）
- Engineering plan 的 Phase 卡片路徑（從中提取交付物與規格產物清單）
- 若未提供，詢問使用者

## Clarify Log（收斂記錄）

### 目的

每次 consistency analysis session 的問題發現、使用者決策、修改結果都要持久化記錄。這確保：
1. **跨 session 收斂**——新 session 讀取歷史 log，不重複報告已處理的問題，不推翻已確認的決策
2. **決策可追溯**——任何人（包括未來的 AI）能理解「為什麼這樣設計」
3. **收斂可觀測**——issue 數量應逐 session 遞減，若沒有，log 能追蹤原因

### Log 位置

Log 檔案放在 engineering plan 的目錄中，路徑為：

```
{plan_dir}/clarify-log.md
```

例如：`graph_driver/model_base/clarify-log.md`

### Log 格式

```markdown
# Clarify Log

## Session {N} — {date}

掃描對象: {file_name}
掃描範圍: {file list}
Issues found: {total} ({A}A / {B}B / {C}C / {D}D)

### {id}. [{confidence}] {一行摘要}

- **Status**: ✓ Resolved | ✓ Auto-fixed | ⊘ Skipped | ✗ Dismissed
- **Confidence**: {score} ({auto-fix | human-review})
- **Problem**: {問題描述，1-2 句}
- **Decision**: {使用者的決策 或 "Auto-fix: AI 自動修正"——採納提案 / 跳過原因 / 忽略原因 / 使用者自己的修改方向}
- **Modification**: {實際修改摘要，若有}（若 Skipped/Dismissed 則為 "—"）
- **Affected files**: {修改的檔案路徑}（若有）
```

### 讀取 Log

在 Phase 1 掃描前，**必須先讀取 clarify-log.md**（若存在）。用途：
- 已 Dismissed 的 issue fingerprint：掃描時跳過（不重複報告）
- 已 Resolved 的 issue：掃描時驗證是否仍然 resolved（修改後可能又壞了）
- 歷史決策：提案時考慮先前的設計決策，避免矛盾

### 寫入 Log

**Auto-fix 時**：立即追加 log entry，Status = ✓ Auto-fixed，含 Confidence 分數與逐維度推理
**+A（Adopt）時**：立即追加 log entry，Status = ✓ Resolved
**+S（Skip）時**：立即追加 log entry，Status = ⊘ Skipped
**+X（Dismiss）時**：立即追加 log entry，Status = ✗ Dismissed
**Session 結束時**：在 log 末尾追加 session summary（resolved / skipped / dismissed 計數）

### 收斂指標

每次 session 開始時，在 issue 清單上方顯示：

```
收斂狀態: Session {N} | 歷史 resolved: {M} | 本次新 issues: {K}
```

若 K > 0（新 issue 比上次多），標註哪些是新引入的（可能是修改副作用），哪些是之前漏掉的。

## Phase 1: 掃描

### 1.1 確定掃描範圍

- 若提供 Phase 卡片：讀取卡片中的「交付物」與「規格產物」表格，取得所有相關檔案路徑
- 若直接提供檔案：以該檔案為主要目標
- **讀取 clarify-log.md**（若存在），載入歷史 session 的決策記錄
- 讀取所有相關檔案的完整內容（不可跳讀）

### 1.2 執行 Consistency Check

從以下維度進行全面檢查：

| 維度 | 檢查內容 |
|------|---------|
| 結構完整性 | 結構定義中引用的欄位是否在操作中都有對應的建立/修改方式 |
| 操作覆蓋 | 每個 entity 是否有完整的 CRUD（或明確說明為何不需要） |
| 前/後置條件一致性 | 操作的前置條件引用的 entity/欄位是否存在於結構定義中 |
| 跨 section 引用 | section 之間的交叉引用（如 violation type code）是否對齊 |
| 編號連續性 | 操作編號是否連續、無跳號 |
| 術語一致性 | 同一概念在不同位置是否使用相同的用語 |
| Invariant 覆蓋 | 每個 invariant 是否被至少一個操作的前/後置條件引用 |
| 設計原則一致性 | 操作設計是否符合文件中宣告的設計原則（如 Two-Layer Model） |
| 與外部參考的一致性 | 與 Phase 卡片中列出的規格產物（如 YAML schema）是否一致 |

### 1.3 分類與排序

將發現的 issue 按嚴重程度分類：

| 類別 | 前綴 | 定義 |
|------|------|------|
| **Critical** | `A` | 結構性缺口——缺少必要的操作、欄位定義與使用矛盾、不可能正確實作 |
| **Design Tension** | `B` | 設計原則之間的矛盾——可以實作但設計上自相矛盾 |
| **API Consistency** | `C` | 介面一致性問題——能用但不一致、容易誤用、有更好的設計 |
| **Minor** | `D` | 小問題——文字模糊、慣例未統一、可改善但不影響正確性 |

每個類別內按影響範圍排序（影響多個 section 的排前面）。

### 1.4 Confidence 評分與分流

對每個 issue 計算 **Confidence 分數**（0-100），代表「AI 獨立正確修復此 issue 的把握程度」。

**評分維度矩陣**：

| 維度 | 高分方向（+分） | 低分方向（-分） |
|------|----------------|----------------|
| 修正唯一性 | 只有一種合理修法（如補漏參數、修錯字） | 有多種合理修法，需要 trade-off |
| 設計影響 | 不改變任何設計決策（純文件對齊） | 涉及 Invariant、API 簽名、架構選擇 |
| 波及範圍 | 只改 1-2 個位置，無連鎖效應 | 改動觸發其他位置連鎖修改 |
| 地基穩定性 | 引用的「正確來源」已明確定義且穩定 | 引用的來源本身有爭議或近期才變更 |
| 歷史先例 | 有 clarify-log 中已確立的同類決策可依循 | 無先例，是全新的設計判斷 |

**評分計算**（逐維度打分後取平均）：

| 維度得分 | 描述 |
|---------|------|
| 90-100 | 機械性修正——答案唯一、不碰設計 |
| 70-89 | 有明確方向但需少量判斷 |
| 50-69 | 有合理方案但存在替代選擇 |
| 0-49 | 涉及基礎設計決策、不確定性高 |

**推理要求**：AI 必須對每個 issue 展示逐維度的推理過程（每維度 1 句話），不可直接給出總分。

**分流規則**：

| Confidence | 路徑 | 行為 |
|-----------|------|------|
| ≥ 80 | **Auto-fix** | AI 直接修改 → commit → 寫 clarify-log。不問使用者。 |
| < 80 | **Human-review** | 進入 Phase 3 互動迴圈（+EP → 等使用者 +A） |

> **為什麼是 80？** ≥80 代表「修正唯一 + 不碰設計 + 波及小 + 來源穩定」，幾乎不可能改錯。
> <80 代表至少有一個維度存在不確定性，值得人工過目。

## Phase 2: 展示 Issue 清單

以下列格式輸出：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Consistency Analysis: {file_name}
掃描範圍: {列出所有讀取的檔案}
Issues: {total} ({A}A / {B}B / {C}C / {D}D)
Auto-fix: {auto_count} | Human-review: {human_count}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

A. Critical
  A1. [85 AUTO] {一行摘要}
  A2. [62 REVIEW] {一行摘要}

B. Design Tension
  B1. [45 REVIEW] {一行摘要}

C. API Consistency
  C1. [92 AUTO] {一行摘要}
  C2. [71 REVIEW] {一行摘要}

D. Minor
  D1. [95 AUTO] {一行摘要}
```

**清單展示後，立即進入 Phase 2.5 Auto-fix。**

## Phase 2.5: Auto-fix 執行

對所有 Confidence ≥ 80 的 issues，**依序**執行以下操作（每個 issue 獨立）：

1. **展示推理摘要**（不等待確認）：
   ```
   ⚡ Auto-fix {id} [{score}] — {摘要}
     修正唯一性: {分} — {1 句理由}
     設計影響: {分} — {1 句理由}
     波及範圍: {分} — {1 句理由}
     地基穩定性: {分} — {1 句理由}
     歷史先例: {分} — {1 句理由}
     → 修改 {N} 處: {file1}, {file2}
   ```
2. **執行修改**
3. **寫入 clarify-log.md**：entry 增加 `**Confidence**: {score} (auto-fix)` 欄位
4. **Git commit**：message 格式 `fix(spec): {issue_id} [auto-fix {score}] — {一行摘要}`

所有 auto-fix 完成後，展示摘要：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Auto-fix 完成: {N} issues
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ A1 [85] — {摘要}
  ✓ C1 [92] — {摘要}
  ✓ D1 [95] — {摘要}

剩餘 Human-review: {M} issues
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

然後進入 Phase 3 互動迴圈，自動展開第一個 Human-review issue。

## Phase 3: 互動迴圈（Human-review only）

**完整互動協議**：Read `references/interaction-protocol.md`（Shorthand 命令語法、所有 Modifier 行為 +E/+P/+A/+S/+X/+R、展示格式、批次操作、自由文字處理）。

Auto-fix 完成後，自動展開第一個 Human-review issue 的 +EP。

## 完成

當所有 issue 都已 resolved、skipped 或 dismissed 時：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Consistency Analysis 完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Resolved: {N}
⊘ Skipped: {N}
✗ Dismissed: {N}

修改的檔案：
- {file_path}（{N} 處修改）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 規則

1. **完整讀取。** 掃描時必須讀取所有相關檔案的完整內容。不可跳讀或只讀摘要。
2. **客觀分析。** 不要為了減少 issue 數量而降低標準。寧可多報一個 Minor 也不要漏報一個 Critical。
3. **提案必須具體且 quote 原文。** +P 的提案必須 quote 現況原文（1-3 行），不能只用簡述。使用者不應需要開檔案才能理解提案在改什麼。
4. **自動推進。** Adopt / Skip / Dismiss 後必須自動展開下一個 issue。使用者不需要手動選擇。
5. **保持清單同步。** 每次 Adopt 後更新 issue 清單。若修改可能影響其他 issue，在清單中標註。
6. **Shorthand 優先。** 始終在回應末尾顯示可用的 shorthand 選項。
7. **不擅自修改——除非 Auto-fix。** Confidence < 80 的 issue，只有使用者明確 +A 後才執行修改。Confidence ≥ 80 的 issue 由 Phase 2.5 自動修改，不需要使用者確認。+E 和 +P 只是展示，不動檔案。
8. **批次一致性。** 批次 +A 時，若某個修改與其他修改衝突，停下來告知使用者，不要靜默跳過。
