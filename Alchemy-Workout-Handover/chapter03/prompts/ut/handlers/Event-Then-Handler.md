# Event-Then-Handler

## Trigger
Then 語句驗證**系統是否發布了預期的 Domain Event**

**識別規則**:
- 驗證事件的觸發（而非資料狀態）
- 常見句型（非窮舉）:「事件應被觸發」「應發布事件」「應產生事件」

**前提**: 系統需要 Event Store/Queue 來記錄事件

**通用判斷**: 如果 Then 是驗證某個事件是否被發布，就使用此 Handler

## Task
取得事件 → 過濾 → 驗證數量 → 驗證資料

---

## Pattern Examples (Python)

### 驗證單一事件
```gherkin
When 學生 "Alice" 更新課程 1 的影片進度至 100%
Then 操作成功
And VideoProgressUpdated 事件應被觸發,課程 ID 為 1
```

```python
service.update_video_progress(user_id="Alice", lesson_id=1, progress=100)

events = service.get_published_events()
video_events = [e for e in events if e.event_type == "VideoProgressUpdated"]

assert len(video_events) == 1
assert video_events[0].lesson_id == 1
```

### 驗證多個事件
```gherkin
And VideoProgressUpdated 事件應被觸發,課程 ID 為 1
And LessonCompleted 事件應被觸發,課程 ID 為 1
```

```python
events = service.get_published_events()

video_events = [e for e in events if e.event_type == "VideoProgressUpdated"]
assert len(video_events) == 1
assert video_events[0].lesson_id == 1

completed_events = [e for e in events if e.event_type == "LessonCompleted"]
assert len(completed_events) == 1
assert completed_events[0].lesson_id == 1
```

### 驗證事件資料 (詳細)
```gherkin
And VideoProgressUpdated 事件應被觸發,包含:
  | user_id | lesson_id | progress | old_progress |
  | Alice   | 1         | 100      | 95           |
```

```python
video_events = [e for e in events if e.event_type == "VideoProgressUpdated"]
assert len(video_events) == 1

event = video_events[0]
assert event.user_id == "Alice"
assert event.lesson_id == 1
assert event.progress == 100
assert event.old_progress == 95
```

---

## Event Filtering

**目的**: 從所有事件中過濾出特定類型的事件進行驗證

**規則**: 使用過濾機制篩選特定類型事件

**Python 範例**:
```python
# 過濾單一類型
video_events = [e for e in events if e.event_type == "VideoProgressUpdated"]

# 過濾多個類型
relevant_events = [e for e in events if e.event_type in ["VideoProgressUpdated", "LessonCompleted"]]
```

---

## Critical Rules

### R1: 驗證事件的關鍵資料
```python
# ✅ video_event = [e for e in events if e.event_type == "VideoProgressUpdated"][0]
#    assert video_event.lesson_id == 1
# ❌ assert "VideoProgressUpdated" in [e.event_type for e in events]
```

### R2: 驗證事件數量
```python
# ✅ assert len(video_events) == 1
# ❌ assert video_events[0].lesson_id == 1  # 如果有多個事件會有問題
```

### R3: 只驗證 Gherkin 提到的欄位
```python
# ✅ assert video_events[0].lesson_id == 1
# ❌ assert video_events[0].timestamp is not None
```

### R4: 取得事件的方法
```python
# ✅ events = service.get_published_events()
# ✅ events = event_store.get_all_events()
```
