# Rule 撰寫指南

## Rule 命名與原子化

### 命名句型

每條 Rule 的名稱必須遵循：

```
Rule: <類型前綴> - <主詞> 必須/應 <單一條件>
```

- **類型前綴**：`前置（狀態）`、`前置（參數）`、`後置（回應）`、`後置（狀態）`
- **主詞**：一個明確的實體屬性或系統狀態
- **動詞**：前置用「必須」（約束），後置用「應」（預期結果）
- **單一條件**：一個可驗證的具體斷言

**正確：**
```
Rule: 前置（狀態）- 商品庫存必須大於 0
Rule: 前置（參數）- 加入數量必須大於 0
Rule: 後置（狀態）- 購物車應新增一筆商品項目
```

**錯誤（違反原子化）：**
```
Rule: 前置（狀態）- 商品庫存必須大於 0 且商品狀態必須為上架中
```
→ 兩個主詞、兩個條件，應拆為兩條 Rule。

### 原子化判定

- 陳述句中出現「且」「和」「並且」→ 拆分為多條 Rule
- 陳述句中出現「或」→ 保留在同一條 Rule
- 混合前置與後置 → 拆分

### 必要參數規則（必備 + 允許合併）

每個 Feature **至少**必須有一條「前置（參數）」Rule 驗證必要參數。

所有「缺少必要參數」的檢查可合併為單一 Rule，使用 Scenario Outline：

```gherkin
Rule: 前置（參數）- 必要參數必須提供

  Scenario Outline: 缺少 <缺少參數> 時操作失敗
    Given 系統中有以下用戶：
      | userId | name  |
      | 1      | Alice |
    When 用戶 "Alice" 將商品 <商品ID> 加入購物車，數量 <數量>
    Then 操作失敗，錯誤為"必要參數未提供"

    Examples:
      | 缺少參數 | 商品ID | 數量 |
      | 商品 ID  |        | 1    |
      | 數量     | 1      |      |
```

其他具有**領域特定約束**的參數規則仍各自獨立為原子 Rule。

---

## 資料驅動原則

每個 Step 必須指定具體、可驗證的資料，禁止模糊描述。

**正確示範：**
```gherkin
Given 系統中有以下用戶：
  | name  | email          | level | exp |
  | Alice | alice@test.com | 1     | 0   |
When 用戶 "Alice" 更新課程 1 的影片進度為 80%
Then 操作成功
And 課程 1 的進度應為：
  | lessonId | progress | status |
  | 1        | 80       | 進行中 |
```

**規則：**
- Given：使用 datatable 提供所有相關屬性的具體值
- When：明確指定用戶名稱/ID、資源 ID、參數值
- Then：使用 datatable 驗證具體的預期值，禁止模糊描述如「已改變」
- Then：失敗場景必須指定具體錯誤訊息：`Then 操作失敗，錯誤為"<具體錯誤訊息>"`
- **錯誤訊息一致性**：同一類失敗跨 Feature 使用同一條錯誤訊息
- **禁止在 datatable 中使用 JSON 字串**，複雜資料應拆分為多個 Given/And 步驟

---

## Given 設定方式

### 選擇 A：直接設定 Aggregate State

```gherkin
Given 訂單 "ORDER-123" 的狀態為：
  | orderId   | status | totalAmount |
  | ORDER-123 | 已付款  | 1500        |
```

適用：Aggregate 的不變條件（Invariant）簡單。

### 選擇 B：透過 Commands 設定

```gherkin
Given 用戶 "Alice" 建立訂單 "ORDER-123"，購買課程 1
And 用戶 "Alice" 完成訂單 "ORDER-123" 的付款，金額 1500 元
```

適用：Aggregate 有複雜的 Invariant（如「總金額 = Σ品項金額 + 運費 - 折扣」）。

| 條件 | 建議 |
|------|------|
| Invariant 簡單（如 `0 ≤ progress ≤ 100`） | 選擇 A |
| Invariant 複雜（跨屬性計算、狀態流轉） | 選擇 B |
| 建立路徑需要 5 個以上 Commands | 選擇 A |

---

## Key 識別規則

### Key 選擇原則

- **Actor（用戶等）**：優先使用 name（如 `"Alice"`），而非 ID
- **其他 Aggregate**：視情境選最具辨識度的屬性（如訂單用 `"ORDER-123"`）

### 引號規則

- **字串值用雙引號**：`"Alice"`、`"ORDER-123"`
- **數字值不用引號**：`1`、`80`

### 複合 Key

| 連接詞 | 範例 | 複合 Key |
|--------|------|----------|
| 在 | `用戶 "Alice" 在課程 1 的進度為 70%` | userId + lessonId |
| 對 | `用戶 "Alice" 對訂單 "ORDER-123" 的評價為 5 星` | userId + orderId |

**所有 Feature File 之間的句型應保持一致。**

---

## When 步驟格式

| 類型 | 格式 | 範例 |
|------|------|------|
| Command | `用戶 "<key>" <動詞＋參數>` | `When 用戶 "Alice" 更新課程 1 的影片進度為 80%` |
| Query | `用戶 "<key>" 查詢 <目標＋參數>` | `When 用戶 "Alice" 查詢課程 1 的進度` |
