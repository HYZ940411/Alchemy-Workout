# Aggregate-Then-Handler

## Trigger
Then 語句驗證**實體在 repository 中的最終狀態**

**識別規則**:
- 驗證實體的屬性值（而非查詢回傳值）
- 描述"某個東西的某個屬性應該是某個值"
- 常見句型（非窮舉）:「在...的...應為」「的...應為」「應包含」

**通用判斷**: 如果 Then 是驗證 Command 操作後的資料狀態（需要從 repository 重新查詢），就使用此 Handler

## Task
repository.find() → assert entity.field

## Steps
1. 識別 Aggregate 名稱
2. 從 DBML 提取: 複合 Key
3. 從 Gherkin 提取: Key 值、要驗證的欄位
4. repository.find(key...) → assert entity.field

---

## Pattern Examples (Python)

### 驗證單一欄位
```gherkin
And 學生 "Alice" 在課程 1 的進度應為 90%
```

```python
updated_progress = repository.find(user_id="Alice", lesson_id=1)
assert updated_progress.progress == 90
```

### 驗證多個欄位
```gherkin
And 課程 1 的進度應為 100%,狀態應為 "已完成"
```

```python
updated_progress = repository.find(user_id="Alice", lesson_id=1)
assert updated_progress.progress == 100
assert updated_progress.status == "COMPLETED"
```

### 失敗場景 (狀態不變)
```gherkin
Given 學生 "Alice" 在課程 1 的進度為 70%
When 學生 "Alice" 更新課程 1 的影片進度為 60%
Then 操作失敗
And 課程 1 的進度應為 70%
```

```python
# Given
progress = LessonProgress(user_id="Alice", lesson_id=1, progress=70, status="IN_PROGRESS")
repository.save(progress)

# When + Then 失敗（使用異常處理機制）
with pytest.raises(InvalidStateError):
    service.update_video_progress("Alice", 1, 60)

# And 驗證狀態不變
unchanged = repository.find(user_id="Alice", lesson_id=1)
assert unchanged.progress == 70
```

---

## Context Inheritance
若 Then/And 省略部分 Key,從上文 (Given/When) 繼承:

```gherkin
Given 學生 "Alice" 在課程 1 的進度為 70%
When 學生 "Alice" 更新課程 1 的影片進度為 80%
And 課程 1 的進度應為 80%  ← 省略 user_id
```

推斷: user_id="Alice", lesson_id=1

---

## Critical Rules

### R1: 使用同一個 repository 實例
```python
# Given: repository.save()
# When: service 使用注入的 repository
# Then: repository.find()  # 能查到 service 修改的資料
```

### R2: 只驗證 Gherkin 提到的欄位
```python
# ✅ assert updated.progress == 90
# ❌ assert updated.updated_at is not None
```

### R3: 驗證絕對值,不是變化量
```python
# ✅ assert updated.progress == 90
# ❌ assert updated.progress == original.progress + 10
```

### R4: 中文狀態映射到英文 enum
```python
# ✅ assert updated.status == "COMPLETED"
# ❌ assert updated.status == "已完成"
```
