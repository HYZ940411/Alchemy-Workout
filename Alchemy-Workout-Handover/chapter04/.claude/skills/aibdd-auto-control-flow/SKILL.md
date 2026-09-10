---
name: aibdd-auto-control-flow
description: >
  BDD 全自動批次迴圈。掃描 features 目錄，為每個 .feature 展開 3 phase TODO 清單
  （red → green → refactor），逐一執行直到全數完成。
  透過 arguments.yml 自動決定測試命令和變體。統合 Python E2E / Java E2E / Python UT 三個版本。
  當 /aibdd-specformula 的 Phase 02 觸發，或使用者說「control-flow」「批次執行」時觸發。
---

# 全自動 BDD 批次執行器

掃描 feature 檔案 → 建立 TodoWrite 任務清單 → 逐一執行 red → green → refactor。

## 變體路由

從 `arguments.yml` 讀取：

| tech_stack | test_strategy | 測試命令 | 備註 |
|-----------|---------------|---------|------|
| python | e2e | `behave ${FEATURES_DIR}/ --tags=~@ignore` | 含 Schema Analysis |
| java | e2e | `mvn clean test` | 含 Schema Analysis |
| python | ut | `behave ${FEATURES_DIR}/ --tags=~@ignore` | 無 Schema Analysis |

**E2E 變體在 Red 前多一步 Schema Analysis（由 `/aibdd-auto-red` 內部處理）。**
**UT 變體跳過 Schema Analysis（由 `/aibdd-auto-red` 的 variant reference 控制）。**

---

## Step 0：環境前置檢查

驗證 backend 骨架是否存在（依變體檢查：Python → `requirements.txt`、Java → `pom.xml`）。

- **不存在** → 詢問使用者「偵測到尚未建立 backend 骨架，是否先執行 `/aibdd-auto-backend-starter`？」→ 使用者確認後觸發 `/aibdd-auto-backend-starter`，完成後再繼續
- **存在** → 直接進入 Step 1

## Step 1：掃描 Feature 檔案

讀取 `${FEATURES_DIR}`，找出所有 `.feature` 檔案。

### 排序策略

**若 `${FEATURES_DIR}` 下存在 `句型.md`**，讀取其中的「覆蓋矩陣」或「操作清單」，以該文件列出的操作順序作為 feature 排序依據。此順序通常反映業務流程的依賴關係（核心功能 → 延伸功能）。

**若無 `句型.md`**，依以下啟發規則排序：
1. 掃描每個 feature 的 Background / Given 步驟，識別前置依賴（哪些操作假設已存在）
2. 無前置依賴的排最前，依賴最多的排最後
3. 同等依賴數量時，command（`@command`）優先於 query（`@query`）

**排序結果展示給使用者確認後再建立任務清單。**

## Step 2：建立 TodoWrite 任務清單

對每個 feature 檔案，建立 **3 個任務**：

```
TodoWrite([
  { content: "{feature} — Red",      status: "pending" },
  { content: "{feature} — Green",    status: "pending" },
  { content: "{feature} — Refactor", status: "pending" },
  ...
])
```

## Step 3：逐一執行

```
標記 → in_progress
    ↓
使用 Skill 工具呼叫對應 skill（帶入 feature file 路徑作為 args）
    ↓
標記 → completed
    ↓
前進到下一個 pending
```

### Skill 對照表

| 任務 phase | 呼叫的 Skill |
|-----------|-------------|
| Red | `/aibdd-auto-red` |
| Green | `/aibdd-auto-green` |
| Refactor | `/aibdd-auto-refactor` |

所有 Skill 內部自行讀取 arguments.yml 決定語言變體，control-flow 不需路由。

## Step 4：最終回歸測試

所有任務 completed 後，執行完整回歸測試（命令見變體路由表）。
- 通過 → 全部完成
- 失敗 → 閱讀錯誤、修正、重新執行

## 規則

1. **不要停下來問問題。** 遇到問題自己修正。
2. **不要跳過任何任務。** 每個 feature 的 3 phase 都必須完成。
3. **一次只有一個 in_progress。**
4. **Skill 是 lazy loading。** 每次呼叫都完整載入該 phase 規則，不受 compaction 影響。
