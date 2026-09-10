---
name: aibdd-carry-on-engineering-plan
description: >
  逐步執行工程計畫，搭配 human-in-the-loop 審查。
  每個 Phase 由對應 skill 連續執行所有內部步驟，完成後展示交付物進入 feedback loop。
  使用者審查通過後才推進至下一個 Phase。
  支援資料夾結構（plan.md + todo/doing/done/）與 Dependency Graph，
  允許多個 AI 平行執行互不依賴的 Phase。
  當使用者說「carry on engineering plan」「carry on」「繼續工程計畫」
  「執行工程計畫」，或想恢復執行先前擬定的工程計畫時觸發。
---

# 執行工程計畫

每個 Phase 由對應 skill **連續執行所有步驟**，完成後進入 **feedback loop** 讓使用者審查交付物。

## References 導覽

| 檔案 | 何時載入 | 內容 |
|------|---------|------|
| `references/feedback-loop.md` | Skill 完成後進入審查 | 交付物展示格式、A/B1/B2/C/D 審查選項詳細流程、LGTM 簽核、交付物狀態生命週期 |

## 計畫資料夾結構

```
{plan_dir}/
├── plan.md              # Dependency Graph + 線性執行順序 + Phase 名稱（唯讀）
├── clarify-log.md       # Consistency Analyzer 的收斂記錄
├── todo/                # 待執行的 Phase 卡片
├── doing/               # 執行中的 Phase 卡片
└── done/                # 已完成的 Phase 卡片
```

**狀態由卡片所在的資料夾決定。** 不依賴檔案內容判斷 Phase 狀態。

## 輸入

- 計畫資料夾路徑（未提供則詢問）
- 可選：指定要執行哪個 Phase（未指定則自動偵測）

## 啟動流程

1. **讀取 `plan.md`** → 取得 Dependency Graph 表格。
2. **掃描三個資料夾**：
   - `done/` → 已完成的 Phase
   - `doing/` → 正在執行中的 Phase（可能是自己中斷的，或另一個 AI 正在做）
   - `todo/` → 待執行的 Phase
3. **決定當前可執行的 Phase**：
   - 從 `todo/` 中，篩選出「Dependency Graph 中所有依賴的 Phase 皆已在 `done/` 中」的卡片。
   - 排除 `doing/` 中的 Phase（其他 AI 正在處理）。
   - 若有多個候選，按 plan.md 中的線性執行順序挑第一個。
   - 若無候選（全部被依賴或被占用），告知使用者並等待。
4. **移動卡片**：`mv todo/{NN}-{slug}.md → doing/{NN}-{slug}.md`
5. **建立當前 Phase 的 TodoWrite**（只建當前 Phase，不建後續 Phase）：
   ```
   Phase {NN}: {名稱} [doing]
     - [ ] 交付物已產出
     - [ ] 交付物已審查
   ```
6. **觸發卡片指定的 skill** → skill 連續執行所有內部步驟（見「Skill 委派」）。
7. Skill 完成後 → **進入 Feedback Loop**。

## Feedback Loop（完整協議見 `references/feedback-loop.md`）

Skill 完成後，展示交付物狀態並進入審查迴圈：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase {NN}: {階段名稱} — 交付物審查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

交付物狀態：

| # | 交付物 | 路徑 | 狀態 |
|---|--------|------|------|
| {NN}.1 | ... | `{/absolute/path}` | PENDING / DONE |
| {NN}.2 | ... | `{/absolute/path}` | PENDING / DONE |

卡片: `{/absolute/path/to/doing/NN-slug.md}`

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
審查選項：

  (A)  我已更新產物——請審查我的修改
  (B1) 我有意見——你來修
  (B2) 我有意見——你先複述我的意圖，我確認後你再修
  (C)  LGTM
  (D)  澄清——我有問題想問

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**路徑規則：所有產物路徑一律使用絕對路徑。**

各選項的完整流程見 `references/feedback-loop.md`。摘要：

| 選項 | 行為 | 推進？ |
|------|------|--------|
| (A) | AI 客觀審查使用者修改 → Consistency Check → 重新展示 | 否 |
| (B1) | AI 依意見直接修改 → Consistency Check → 重新展示 | 否 |
| (B2) | AI 先複述意圖 → 確認後修改 → Consistency Check → 重新展示 | 否 |
| (C) | 簽核卡片 → 交付物 DONE → 移動卡片至 done/ → 下一 Phase（一氣呵成，不再逐項確認） | 是 |
| (D) | 回答問題 → 重新展示 | 否 |

**簽名格式**：`YYYY-MM-DD HH:mm`（只有日期時間，不含姓名）。

## Consistency Check（委派 `/aibdd-consistency-analyzer`）

### 觸發時機

Feedback Loop 中產生實際改動後觸發：

- **(B1)** AI 直接修改後
- **(B2-Y)** 確認意圖後 AI 修改後
- **(A-1)** 套用審查建議後

### 執行方式

1. 從當前 Phase 卡片中解析所有相關規格、交付物的**絕對路徑**清單。
2. 觸發 `/aibdd-consistency-analyzer`，傳入這些檔案路徑。
3. `/aibdd-consistency-analyzer` 會自行完成掃描、展示 issue 清單、互動迴圈（+A/+S/+X）、以及寫入 `{plan_dir}/clarify-log.md`。
4. **Consistency Check 完成後**（所有 issue 已 resolved / skipped / dismissed），回到 Feedback Loop。

## Skill 委派

觸發卡片指定 skill 時：

1. Skill **連續執行所有內部步驟**，用自己的 TodoWrite 追蹤進度。
2. Skill 內部需要使用者輸入的步驟（如 Flow Alignment 的 confirm、Clarify Loop 的問答）自然發生在連續執行中，屬於**工作互動**，不是審查閘門。
3. Skill 完成後回傳控制權 → carry-on 更新 TodoWrite（交付物已產出 → completed），進入 Feedback Loop。

**交付物由專責 skill 產出，carry-on 負責審查。**

## 進度追蹤（不可違反）

- **TodoWrite 只建當前 Phase。** 進入下一 Phase 時才建立下一組任務。前一 Phase 的任務已完成，不需要保留。
- **Phase 卡片是簽核真相。** LGTM 後立即將簽名寫入卡片檔案。
- **資料夾是狀態真相。** 卡片在 `todo/`、`doing/`、`done/` 之間的位置即為 Phase 狀態。
- **plan.md 是唯讀的。**（除了更新狀態欄位）
- **若計畫在執行中發生變更**（例如後期階段發現前期產物有缺口），需由使用者主動調整。若已完成的 Phase 需要重新審查，將卡片從 `done/` 移回 `todo/`，重設簽核勾選框。

## 平行執行（多 AI 協作）

1. **每個 AI 獨立掃描資料夾**，判斷自己可以做什麼。
2. **`doing/` 中的卡片視為已被占用**——不搶、不重複執行。
3. **各 AI 只修改自己正在處理的卡片**。
4. **plan.md 不被修改**。
5. 若所有候選 Phase 都在 `doing/` 中，告知使用者。

## 完成

當所有 Phase 卡片皆在 `done/` 中時：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
工程計畫已完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

所有階段已簽核完畢。

plan.md 狀態已更新為：COMPLETED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 規則

1. **依 Dependency Graph 執行。** 只執行依賴皆已在 `done/` 中的 Phase。
2. **絕不自動 LGTM。** 只有使用者明確選擇 (C) 才能推進。
3. **立即持久化。** 簽核 → 寫入卡片 → 更新任務。不批量處理。
4. **(A) 時客觀審查。** 不要橡皮圖章。挑戰產物的正確性。
5. **簽名格式固定。** `YYYY-MM-DD HH:mm`（只有日期時間，不含姓名）。
6. **恢復優先。** 若對話恢復或 context 被壓縮，重新掃描資料夾 + 讀取 plan.md + TodoWrite 找到當前狀態。`doing/` 中的卡片一律視為被占用（規則 8），不接手——僅從 `todo/` 中依正常流程選取下一個可執行的 Phase。若無候選，告知使用者並等待。
7. **絕對路徑。** 展示時所有產物路徑一律使用絕對路徑。
8. **不搶 doing。** 看到 `doing/` 中有卡片，一律視為其他 AI 正在處理，跳過。
9. **Consistency Check 不可跳過。** Feedback Loop 中每次修改後必須觸發。
10. **TodoWrite 只建當前 Phase。** 下一 Phase 進入時才建立下一組任務。
