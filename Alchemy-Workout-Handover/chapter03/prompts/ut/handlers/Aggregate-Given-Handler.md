# Aggregate-Given-Handler

## Trigger
Given 語句描述**實體的存在狀態**，即定義實體的屬性值

**識別規則**：
- 語句中包含實體名詞 + 屬性描述
- 描述"某個東西的某個屬性是某個值"
- 常見句型（非窮舉）:「在...的...為」「的...為」「包含」「存在」「有」

**通用判斷**: 如果 Given 是在建立測試的初始資料狀態（而非執行動作），就使用此 Handler

## Task
創建 entity → repository.save()

## Steps
1. 識別 Aggregate 名稱
2. 從 DBML 提取: 屬性、型別、複合 Key、enum
3. 從 Gherkin 提取: Key 值、屬性值
4. 創建 entity → repository.save()

---

## Pattern Examples (Python)

### 單一 Aggregate
```gherkin
Given 學生 "Alice" 在課程 1 的進度為 80%,狀態為 "進行中"
```

```python
progress = LessonProgress(
    user_id="Alice",
    lesson_id=1,
    progress=80,
    status="IN_PROGRESS"
)
repository.save(progress)
```

### 三元複合 Key
```gherkin
Given 訂單 "ORDER-123" 中商品 "PROD-001" 在倉庫 "WH-01" 的數量為 5
```

```python
item = OrderItemWarehouse(
    order_id="ORDER-123",
    product_id="PROD-001",
    warehouse_id="WH-01",
    quantity=5
)
repository.save(item)
```

---

## Key Patterns

**目的**: 從 Gherkin 的關係詞推斷 DBML 中的複合主鍵結構

**規則**: Gherkin 中的關係詞通常對應實體間的多對多或一對多關係，這些關係在 DBML 中會定義為複合主鍵

| 關係詞 | Gherkin 範例 | 複合 Key |
|-------|------------|---------|
| 在 | 用戶 "Alice" 在課程 1 | (user_id, lesson_id) |
| 對 | 用戶 "Alice" 對訂單 "ORDER-123" | (user_id, order_id) |
| 與 | 用戶 "Alice" 與用戶 "Bob" | (user_id_a, user_id_b) |
| 於 | 商品 "MacBook" 於商店 "台北店" | (product_id, store_id) |
| 中...在 | 訂單中商品在倉庫 | (order_id, product_id, warehouse_id) |

---

## State Mapping

**目的**: 將 Gherkin 中的中文業務術語映射到 DBML enum 值

**規則**: 
1. 查詢 DBML 中對應欄位的 `note` 定義（如: `status varchar [note: 'IN_PROGRESS, COMPLETED']`）
2. 根據語意將 Gherkin 的中文描述映射到 DBML enum 值
3. 下表僅為常見範例，實際應從 DBML 提取

| 中文範例 | Enum 範例 | 適用情境 |
|---------|----------|---------|
| 進行中 | IN_PROGRESS | 進度、狀態 |
| 已完成 | COMPLETED | 進度、狀態 |
| 未開始 | NOT_STARTED | 進度、狀態 |
| 已付款 | PAID | 訂單、付款 |
| 待付款 | PENDING | 訂單、付款 |
| 上架中 | ACTIVE | 商品、服務 |

---

## Critical Rules

### R1: 必須查詢 DBML
在實作 Aggregate 的時候不能憑空猜測屬性名稱和型別。

### R2: 中文狀態映射到英文 enum
```python
# ✅ status="IN_PROGRESS"
# ❌ status="進行中"
```

### R3: 提供完整的複合 Key
```python
# ✅ LessonProgress(user_id="Alice", lesson_id=1, ...)
# ❌ LessonProgress(lesson_id=1, ...)
```

### R4: 與 service 共用同一個 repository 實例
```python
repository = LessonProgressRepository()
service = LessonService(lesson_progress_repository=repository)
repository.save(progress)  # Given 使用
# Then 才能查到 service 修改的資料
```
