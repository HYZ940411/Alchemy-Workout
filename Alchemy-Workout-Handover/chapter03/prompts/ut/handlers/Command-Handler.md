# Command-Handler

## Trigger
Given/When 語句執行**寫入操作**（Command）

**識別規則**:
- 動作會修改系統狀態
- 描述"執行某個動作"或"已完成某個動作"
- Given 常見過去式（非窮舉）:「已訂閱」「已完成」「已建立」「已添加」
- When 常見現在式（非窮舉）:「更新」「提交」「建立」「刪除」「添加」「移除」

**通用判斷**: 如果語句是修改系統狀態的操作且不需要回傳值，就使用此 Handler

## Task
調用 service.method()

## Key Difference
- **Command**: 無回傳值，修改狀態
- **Query**: 必須接收回傳值，不修改狀態

---

## Pattern Examples (Python)

### Given + Command (已完成的動作)
```gherkin
Given 用戶 "Alice" 已訂閱課程 1
```

```python
service.subscribe_lesson(user_id="Alice", lesson_id=1)
```

### When + Command (現在執行的動作)
```gherkin
When 用戶 "Alice" 更新課程 1 的影片進度為 80%
```

```python
service.update_video_progress(user_id="Alice", lesson_id=1, progress=80)
```

### 多參數 Command
```gherkin
When 用戶 "Alice" 提交訂單，包含商品 "PROD-001" 數量 2
```

```python
service.submit_order(user_id="Alice", product_id="PROD-001", quantity=2)
```

### 複雜 Command
```gherkin
When 用戶 "Alice" 建立訂單 "ORDER-123"，包含商品 "PROD-001" 數量 2，總金額 1000
```

```python
service.create_order(
    order_id="ORDER-123",
    user_id="Alice",
    product_id="PROD-001",
    quantity=2,
    total_amount=1000
)
```

---

## Method Naming

**規則**:
- 方法名使用動詞開頭，描述動作
- 方法名使用小寫加底線分隔
- 從 Gherkin 的動詞推斷方法名

**命名推斷**:
- 從 Gherkin 的動詞和目標物件推斷方法名
- 下表僅為常見範例

| Gherkin 動作範例 | Method 範例 (Python) |
|----------------|-------------------|
| 更新...進度 | update_{entity}_progress() |
| 提交...作業 | submit_{entity}() |
| 建立...訂單 | create_{entity}() |
| 刪除...商品 | delete_{entity}() |
| 添加...到購物車 | add_to_{entity}() |
| 移除...從購物車 | remove_from_{entity}() |

---

## Parameter Extraction

**規則**: 從 Gherkin 的名詞片段和數值推斷參數名稱和值

**推斷原則**:
- 實體名詞 → {entity}_id
- 屬性 → {attribute}
- 字串用引號，數字不用引號
- 下表僅為範例

| Gherkin 片段範例 | 參數範例 |
|----------------|---------|
| 用戶 "Alice" | user_id="Alice" |
| 課程 1 | lesson_id=1 |
| 進度為 80% | progress=80 |
| 數量 2 | quantity=2 |
| 總金額 1000 | total_amount=1000 |

---

## Given vs When Command

### 差異說明

**Given + Command (已完成的動作)**:
- 用於建立測試前置條件
- 描述過去已經發生的動作
- 常用過去式：「已訂閱」「已完成」「已建立」

**When + Command (現在執行的動作)**:
- 用於執行被測試的動作
- 描述現在要執行的動作
- 常用現在式：「更新」「提交」「建立」

### 範例對比

```gherkin
# Given: 建立前置條件
Given 用戶 "Alice" 已訂閱課程 1

# When: 執行被測試動作
When 用戶 "Alice" 更新課程 1 的影片進度為 80%
```

```python
# Given: 直接調用 service
service.subscribe_lesson(user_id="Alice", lesson_id=1)

# When: 同樣直接調用 service（可能在 pytest.raises 中）
service.update_video_progress(user_id="Alice", lesson_id=1, progress=80)
```

**關鍵**: Given 和 When 的 Command 在程式碼層面是一樣的，都是直接調用 service.method()

---

## Critical Rules

### R1: Command 不接收回傳值
```python
# ✅ service.update_video_progress(...)
# ❌ result = service.update_video_progress(...)
```

### R2: 參數名稱清晰
```python
# ✅ service.update_video_progress(user_id="Alice", lesson_id=1, progress=80)
# ❌ service.update_video_progress("Alice", 1, 80)
```

### R3: 與 repository 共用實例
Command 操作的 service 必須與 Given/Then 使用同一個 repository 實例

```python
repository = LessonProgressRepository()
service = LessonService(lesson_progress_repository=repository)

# Given: repository.save()
# When: service.update_video_progress() 使用注入的 repository
# Then: repository.find() 能查到 service 修改的資料
```

### R4: 失敗場景使用異常處理機制
當 Then 是「操作失敗」時，Command 需要包裹在異常處理中

```python
# ✅ with pytest.raises(InvalidStateError):
#       service.update_video_progress(...)
# ❌ service.update_video_progress(...)
```

