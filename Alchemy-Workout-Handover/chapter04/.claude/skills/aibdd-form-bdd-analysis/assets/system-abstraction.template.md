# 系統抽象

## 實體清單

| 實體 | 性質 | 攜帶狀態摘要 | 對應 features subfolder |
|------|------|-------------|------------------------|
| ... | Aggregate / Gateway | ... | ... |

## 操作全景

| 操作 | 所屬實體 | 行為分類 | 輸入參數 | 回傳型別 |
|------|---------|---------|---------|---------|
| ... | ... | Creation / Mutation / Query / Diagnostic | ... | ... |

## 系統前置狀態拆解

> 從所有操作的 Rule（前置）反推，系統狀態由哪些可獨立建置的部件組成。
> 每個部件對應一個 Given 句型。

| 部件 | 資料型別 | 建置方式 | 內部子結構 | Given 句型 |
|------|---------|---------|-----------|-----------|
| ... | ... | Data Table / Doc String / JSON | 有：(列出子部件) / 無 | `Given ...` |

> **遞迴拆解原則**：若部件有內部子結構，需逐層拆解直到每個子部件都有明確的建置方式。
> Given 句型數量 = 葉子部件數量。

## 行為分類與句型骨架

### Creation

**When 句型模板**：
  `When {operation}:`（接 Data Table）

**Then 句型模板（成功）**：
  `Then {result_assertion}:`（接 Data Table）

**Then 句型模板（失敗）**：
  `Then 操作失敗，violation_type 為 "<violation>"`

（每個分類重複此結構）

## 共用契約

### Postcondition 模式
（跨 domain 重複的成功路徑模式）

### Violation 模式
（跨 domain 重複的 precondition → violation_type 對應）

## 共用句型

> **此 section 在 Stage 2.5（所有 domain 句型分析完成後）才填入。**
> 只有真正跨 2 個以上 domain 共用的句型才放在這裡。
> 若只有 1 個 domain，此 section 留空。
> 句型的 single source of truth 在各 domain 的句型.md。

（待 Stage 2.5 萃取）

## 變異點索引

| 實體 | 特有行為 | 需要的專屬句型類別 |
|------|---------|------------------|
| ... | ... | ... |
