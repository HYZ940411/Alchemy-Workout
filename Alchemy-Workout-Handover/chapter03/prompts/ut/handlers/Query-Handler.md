# Query-Handler

## Trigger
When 語句執行**讀取操作**（Query）

**識別規則**:
- 動作不修改系統狀態，只讀取資料
- 描述"取得某些資訊"的動作
- 常見動詞（非窮舉）:「查詢」「取得」「列出」「檢視」「獲取」

**通用判斷**: 如果 When 是讀取操作且需要回傳值供 Then 驗證，就使用此 Handler

## Task
result = service.query_method()

## Key Difference
- **Command**: 無回傳值，修改狀態
- **Query**: 必須接收回傳值，不修改狀態

---

## Method Naming

**規則**:
- 單一記錄: `get_{entity}` 或 `get_{entity}_{aspect}`
- 列表: `list_{entities}` (複數形式)
- 方法名使用小寫加底線分隔

**命名推斷**:
- 從 Gherkin 的動詞和目標物件推斷方法名
- 下表僅為常見範例

| Gherkin 動作範例 | Method 範例 (Python) |
|----------------|-------------------|
| 查詢...進度 | get_{entity}_progress() |
| 取得...詳情 | get_{entity}_details() |
| 列出...列表 | list_{entities}() |
| 查詢...狀態 | get_{entity}_status() |

---

## Pattern Examples (Python)

### Query 單一記錄
```gherkin
When 用戶 "Alice" 查詢課程 1 的進度
```

```python
result = service.get_lesson_progress(user_id="Alice", lesson_id=1)
```

### Query 列表
```gherkin
When 學生 "Alice" 查詢所有課程進度
```

```python
result = service.list_lesson_progress(user_id="Alice")
```

### Query 詳情
```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
```

```python
result = service.get_order_details(order_id="ORDER-123")
```

---

## Parameter Extraction

**規則**: 從 Gherkin 的名詞片段推斷參數名稱和值

**推斷原則**:
- 實體名詞 → {entity}_id
- 字串用引號，數字不用引號
- 下表僅為範例

| Gherkin 片段範例 | 參數名稱範例 |
|----------------|------------|
| 學生 "Alice" | user_id="Alice" |
| 課程 1 | lesson_id=1 |
| 訂單 "ORDER-123" | order_id="ORDER-123" |

---

## Critical Rules

### R1: Query 必須接收回傳值
```python
# ✅ result = service.get_lesson_progress(...)
# ❌ service.get_lesson_progress(...)
```

### R2: 使用 result 變數名稱
統一使用 `result` 方便 Then 中驗證

### R3: 參數名稱清晰
```python
# ✅ service.get_lesson_progress(user_id="Alice", lesson_id=1)
# ❌ service.get_lesson_progress("Alice", 1)
```

### R4: result 在 Then 中複用
Query 的 result 會在 Then 中被 ReadModel-Then-Handler 使用,不重新調用
