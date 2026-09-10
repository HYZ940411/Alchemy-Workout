# Phase 3: 互動迴圈（Human-review only）

## Shorthand 命令語法

使用者輸入格式：`{issue_ids} {modifiers}`

**Issue 選擇**（空格分隔，可多選）：

| 語法 | 意義 | 範例 |
|------|------|------|
| `A1` | 選定單一 issue | |
| `A1 C2 D1` | 選定多個 issue | |
| （省略） | 延續當前 issue | |

**Modifier**（`+` 前綴，可組合）：

| Modifier | 全名 | 作用 |
|----------|------|------|
| `+E` | Elaborate | 詳述 issue：問題是什麼、為什麼是問題、影響哪些位置 |
| `+P` | Propose | 提案：具體會修改哪些檔案的哪些位置、修改前後的對比 |
| `+EP` | Elaborate + Propose | 先詳述再提案（**預設行為**） |
| `+A` | Adopt | 採納當前提案，執行修改 |
| `+S` | Skip | 跳過當前 issue，標記為 skipped |
| `+R` | Rescan | 重新掃描整份產物（修改後可能產生新 issue 或消除舊 issue） |
| `+X` | Dismiss | 永久忽略此 issue（不是問題） |

**預設行為**：

| 輸入 | 等同 | 說明 |
|------|------|------|
| `C1` | `C1 +EP` | 只打 issue id → 詳述 + 提案 |
| `C1 C2` | `C1 C2 +EP` | 多個 id → 批次詳述 + 提案 |
| `+A` | （當前 issue）`+A` | 無 id + modifier → 對當前 issue 操作 |
| `+S` | （當前 issue）`+S` | 同上 |

**自由文字**：使用者也可以不用 shorthand，直接用自然語言回應。AI 應理解意圖並對應到正確的操作。

## 迴圈行為

### +E（Elaborate）

展示 issue 的完整分析：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ {id} — {一行摘要}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【問題】
{詳細說明問題是什麼}

【為什麼是問題】
{解釋影響：會導致什麼後果}

【影響位置】
- `{file_path}:{line}` — {說明}
- `{file_path}:{line}` — {說明}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Shorthand: +P 提案 | +S 跳過 | +X 忽略 | {id} 跳至
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### +P（Propose）

```
【提案】
修改 {N} 處：

1. `{file_path}:{line_range}`
   現況：
   > {原文 quote（1-3 行）}
   改為：
   > {修改後 quote}

2. `{file_path}:{line_range}`
   現況：
   > {原文 quote}
   改為：
   > {修改後 quote}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Shorthand: +A 採納 | +S 跳過 | 自由文字提意見
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### +A（Adopt）

1. 執行提案中描述的所有修改
2. 標記該 issue 為 ✓ resolved
3. **寫入 clarify-log.md**：追加 entry（Problem / Decision / Modification / Affected files）
4. **Git commit**：message 格式 `fix(spec): {issue_id} — {一行摘要}`。若為批次 +A，每個 issue 各自一個 commit。
5. **自動推進**：展示更新後的 issue 清單（已解決的標 ✓），並自動對下一個未處理的 issue 執行 +EP

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ {id} — {摘要}（已修改）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{簡要說明修改了什麼}

剩餘 Issues: {remaining} ({A}A / {B}B / {C}C / {D}D)
  ✓ A1. {摘要}
  → B1. {摘要}                    ← 下一個

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ B1 — {摘要}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{B1 的詳述 + 提案，自動展開}
```

### +S（Skip）

1. 標記為 ⊘ skipped（不是 resolved，未來 +R 時會重新出現）
2. **寫入 clarify-log.md**：追加 entry，Decision 記錄跳過原因
3. 自動推進至下一個

### +X（Dismiss）

1. 標記為 ✗ dismissed（永久忽略，+R 時不會重新出現）
2. **寫入 clarify-log.md**：追加 entry，Decision 記錄忽略理由
3. 自動推進至下一個

### +R（Rescan）

1. 重新讀取所有相關檔案 + **clarify-log.md**
2. 重新執行完整 consistency check
3. 比對 clarify-log：已 Dismissed 的 issue 不重複報告
4. 已 Resolved 的 issue 若修改後仍存在 → 重新標為未處理（regression）
5. 新發現的 issue 標註為 `[NEW]`
6. 展示全新的 issue 清單（含收斂指標）+ 自動展開第一個

### 使用者回覆自由文字

AI 應判斷意圖：
- 像是意見 → 視為對當前 proposal 的 feedback，調整提案後重新展示 +P
- 像是問題 → 回答後重新展示當前 issue 的 shorthand 選項
- 像是決定（如「不用改」「這不是問題」）→ 視為 +X

## 批次操作

當使用者選定多個 issue 時（如 `A1 A2 C1 +EP`）：

- 依序展開每個 issue 的 Elaborate + Propose
- 每個 issue 之間以分隔線區隔
- 最後統一顯示 shorthand（`+A` 會批次採納所有提案）

當使用者對多個 issue 執行 `+A` 時：

- 依序執行所有修改
- 一次性展示所有已完成的修改摘要
- 自動推進至下一個未處理的 issue
