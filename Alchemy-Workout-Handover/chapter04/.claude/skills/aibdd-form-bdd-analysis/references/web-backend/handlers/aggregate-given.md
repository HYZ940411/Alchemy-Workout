# Handler: aggregate-given

## Trigger 辨識

Given 語句描述 **Aggregate 的存在狀態**，即定義 Aggregate 的屬性值。

**識別規則**：
- 語句中包含實體名詞 + 屬性描述
- 描述「某個東西的某個屬性是某個值」
- 常見句型（非窮舉）：「在...的...為」「的...為」「包含」「存在」「有」

**通用判斷**：如果 Given 是在建立測試的初始資料狀態（而非執行動作），就使用此 Handler。

## 任務

建立 ORM/Entity Instance → 透過 Repository.save() 寫入儲存 → 儲存 ID 到共享狀態。

## 與 Command Handler 的區別

| | aggregate-given | command（Given 用法） |
|---|---|---|
| 目的 | 直接建立 DB 資料（繞過 API） | 透過 API 執行命令 |
| 層級 | Repository 層 | HTTP API 層 |
| 適用時機 | 純前置資料設定 | 測試需要經過完整 API 流程 |

## 實作流程

1. 從 context / DI 取得儲存機制（db_session / Repository / FakeRepo）
2. 識別 Aggregate 名稱（從 TODO 標註或 Gherkin 語意）
3. 從 DBML 提取：屬性、型別、複合 Key、enum
4. 從 Gherkin 提取：Key 值、屬性值
5. 建立 ORM/Entity instance
6. 使用 Repository.save() 寫入
7. 將 ID 儲存到共享狀態（`context.ids["{natural_key}"]` 或 `testContext.putId()`）

## BDD 模式

### 單一 Aggregate

```gherkin
Given 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量為 2
```

### 複合主鍵 Aggregate

```gherkin
Given 用戶 "Alice" 在課程 1 的進度為 70%，狀態為 "進行中"
```

### DataTable 批量建立

```gherkin
Given 系統中有以下用戶：
  | userId | name  | email           |
  | 1      | Alice | alice@test.com  |
  | 2      | Bob   | bob@test.com    |
```

### DocString（多行文字）

```gherkin
Given 用戶 "Alice" 的個人簡介為：
  """
  我是一個軟體工程師，喜歡學習新技術。
  """
```

## 關鍵模式

### 複合主鍵推斷

從 Gherkin 的關係詞推斷 DBML 中的複合主鍵結構：

| 關係詞 | Gherkin 範例 | 複合 Key |
|-------|------------|---------|
| 在 | 用戶 "Alice" 在課程 1 | (user_id, lesson_id) |
| 對 | 用戶 "Alice" 對訂單 "ORDER-123" | (user_id, order_id) |
| 與 | 用戶 "Alice" 與用戶 "Bob" | (user_id_a, user_id_b) |
| 於 | 商品 "MacBook" 於商店 "台北店" | (product_id, store_id) |

### 中文狀態映射

Gherkin 中的中文業務術語需映射到 DBML enum 值：

| 中文 | Enum | 情境 |
|-----|------|-----|
| 進行中 | IN_PROGRESS | 進度、狀態 |
| 已完成 | COMPLETED | 進度、狀態 |
| 未開始 | NOT_STARTED | 進度、狀態 |
| 已付款 | PAID | 訂單 |
| 待付款 | PENDING | 訂單 |

## 共用規則

1. **R1: 必須查詢 DBML** — 不可憑空猜測屬性名稱和型別
2. **R2: 使用 ORM/Entity** — 不可使用 dict 或普通物件替代
3. **R3: 透過 Repository** — 不可直接操作 session/EntityManager
4. **R4: 中文狀態映射** — 中文 → enum 值（查 DBML note）
5. **R5: 提供完整複合 Key** — 缺少任一 key 欄位會導致查詢失敗
6. **R6: 儲存 ID 到共享狀態** — 供後續 Command/Query/Then handler 使用
7. **R7: 檢查依賴 ID** — 有外鍵的 Aggregate，先確認依賴的 ID 已存在
8. **R8: 使用 merge/upsert 語意** — 避免重複插入失敗
