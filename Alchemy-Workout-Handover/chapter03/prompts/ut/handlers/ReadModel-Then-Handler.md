# ReadModel-Then-Handler

## Trigger
Then 語句驗證**Query 的回傳結果**

**識別規則**:
- 前提: When 是 Query 操作（已接收 result）
- 驗證的是查詢回傳值（而非 repository 中的狀態）
- 常見句型（非窮舉）:「查詢結果應」「回應應」「應返回」「結果包含」

**通用判斷**: 如果 Then 是驗證 Query 操作的回傳值，就使用此 Handler

## Task
assert result.field == expected

## Critical Rule
不重新調用 service, 使用 When 中的 result

---

## Pattern Examples (Python)

### 驗證單一記錄
```gherkin
When 學生 "Alice" 查詢課程 1 的進度
Then 操作成功
And 查詢結果應包含進度 80,狀態為 "進行中"
```

```python
# When
result = service.get_lesson_progress(user_id="Alice", lesson_id=1)

# Then
assert result.progress == 80
assert result.status == "IN_PROGRESS"
```

### 驗證列表
```gherkin
When 學生 "Alice" 查詢所有課程進度
Then 操作成功
And 查詢結果應包含 2 筆記錄
And 第一筆記錄的課程 ID 應為 1,進度為 80%
And 第二筆記錄的課程 ID 應為 2,進度為 50%
```

```python
# When
result = service.list_lesson_progress(user_id="Alice")

# Then
assert len(result) == 2
assert result[0].lesson_id == 1
assert result[0].progress == 80
assert result[1].lesson_id == 2
assert result[1].progress == 50
```

### 驗證表格資料
```gherkin
And 查詢結果應包含:
  | 用戶ID | 課程ID | 進度 | 狀態   |
  | Alice  | 1     | 80  | 進行中 |
```

```python
assert result.user_id == "Alice"
assert result.lesson_id == 1
assert result.progress == 80
assert result.status == "IN_PROGRESS"
```

### 驗證空結果
```gherkin
When 學生 "Bob" 查詢所有課程進度
Then 操作成功
And 查詢結果應為空列表
```

```python
result = service.list_lesson_progress(user_id="Bob")
assert result == []
```

---

## Nested Structure

**目的**: 驗證查詢結果中的巢狀資料結構（如一對多關係）

**規則**: 使用物件屬性或列表索引存取巢狀資料

### 範例: 一對多關係
```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
Then 操作成功
And 訂單應包含 2 個商品
And 第一個商品為 "PROD-001",數量 2
And 第二個商品為 "PROD-002",數量 1
```

```python
result = service.get_order_details(order_id="ORDER-123")

assert len(result.items) == 2
assert result.items[0].product_id == "PROD-001"
assert result.items[0].quantity == 2
assert result.items[1].product_id == "PROD-002"
assert result.items[1].quantity == 1
```

---

## Query Failure (Python)

```gherkin
Given 學生 "Alice" 未訂閱課程 1
When 學生 "Alice" 查詢課程 1 的進度
Then 操作失敗
And 錯誤訊息應為 "無權限查詢此課程"
```

```python
# Given: 不創建任何資料

# When + Then 失敗
with pytest.raises(PermissionDeniedError) as exc_info:
    service.get_lesson_progress(user_id="Alice", lesson_id=1)

# And 驗證錯誤訊息
assert str(exc_info.value) == "無權限查詢此課程"
```

---

## Critical Rules

### R1: 使用 When 中的 result
```python
# ✅ assert result.progress == 80
# ❌ result = service.get_lesson_progress(...)
```

### R2: 只驗證 Gherkin 提到的欄位
```python
# ✅ assert result.progress == 80
# ❌ assert result.updated_at is not None
```

### R3: 中文狀態 → 英文 enum
```python
# ✅ assert result.status == "IN_PROGRESS"
# ❌ assert result.status == "進行中"
```

### R4: 列表索引從 0 開始
```python
# ✅ 第一筆是 result[0]
# ❌ 第一筆不是 result[1]
```
