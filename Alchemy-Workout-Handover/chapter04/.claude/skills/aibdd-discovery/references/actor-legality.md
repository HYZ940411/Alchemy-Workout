# Feature 顆粒度與 Actor 合法性

## 核心定義

**1 Feature File = 1 API Endpoint = 1 外部觸發動作**

## Actor 合法性規則

Activity Diagram 的 STEP / BRANCH 只允許以下兩類 Actor：

| 類別 | 定義 | 範例 |
|------|------|------|
| **外部使用者** | 透過 UI / CLI 主動操作系統的人類角色 | 行銷人員、客服夥伴、助教 |
| **第三方系統** | 自有系統控制範圍**以外**的外部服務 | 影片平台（Webhook）、金流系統（Callback） |

**禁止作為 Actor**：**內建系統**（自有系統內部的自動化邏輯）→ 無外部觸發 → 無 API Endpoint → 無獨立 Feature File。

## 內建系統邏輯的正確處理方式

將其收入**觸發者 Feature 的 Rule（Post-condition / Conditional Rule）**。

### 判斷流程

```
收到一個業務動作 →
  Q1: 誰觸發？
    → 外部使用者 / 第三方系統 → 建立獨立 STEP + Feature File ✓
    → 內建系統自動執行 →
      Q2: 被哪個外部觸發的 STEP 連鎖引發？
        → 找到上游 → 收入該觸發者的 Feature 作為 Rule ✓
        → 找不到 → 標記便條紙待澄清
```

### 區分：第三方系統 vs. 內建系統

判斷標準：**該系統是否在我方控制範圍之外？**

- 影片平台 Webhook → 第三方 ✓
- 金流系統回呼 → 第三方 ✓
- 自有系統判斷是否建立 Journey → 內建 ✗（收入上游 Rule）

### 轉化範例

❌ 錯誤（內建系統作為獨立 STEP）：
```
[STEP:1] @行銷人員 {features/lead/手動新增Lead.feature}
[STEP:2] @系統 {features/journey/判斷是否建立Journey.feature}  ← 無外部觸發
[STEP:3] @系統 {features/sop/自動綁定SOP.feature}              ← 無外部觸發
```

✅ 正確（內建邏輯收入觸發者的 Feature）：
```
[STEP:1] @行銷人員 {features/lead/手動新增Lead.feature}
  手動新增Lead.feature 中以 Rule 表達：
    Rule: 後置（連鎖）- 已購課 Lead 自動建立 Journey 並設定 Stage 為等待開課
    Rule: 後置（連鎖）- Journey 建立後自動綁定對應 SOP
```

### 對下游視圖的傳播影響

| 視圖 | 影響 |
|------|------|
| Activity | 不得出現 @內建系統 作為 STEP Actor；內建邏輯從圖上移除 |
| .feature | 內建系統邏輯以 Rule 呈現在觸發者的 Feature 中 |
| api.yml | 不為內建系統邏輯建立獨立 Endpoint |
| erm.dbml | 不受直接影響（資料模型由 Feature 的 datatable 決定） |
