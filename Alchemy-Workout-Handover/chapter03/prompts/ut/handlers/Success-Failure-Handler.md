# Success-Failure-Handler

## Trigger
Then 語句描述**操作的成功或失敗結果**

**識別規則**:
- 明確描述操作結果（成功/失敗）
- 常見句型:「操作成功」「操作失敗」「執行成功」「執行失敗」

**通用判斷**: 如果 Then 只關注操作是否拋出異常（而非驗證具體資料），就使用此 Handler

## Task
決定是否使用異常處理機制包裹 When 語句

---

## Pattern 1: 操作成功 (Python)

不需要異常處理,直接執行

```gherkin
When 學生 "Alice" 更新課程 1 的影片進度為 90%
Then 操作成功
```

```python
service.update_video_progress(user_id="Alice", lesson_id=1, progress=90)
# 不需要額外程式碼
```

---

## Pattern 2: 操作失敗 (Python)

使用異常處理機制捕獲預期異常

```gherkin
When 學生 "Alice" 更新課程 1 的影片進度為 70%
Then 操作失敗
```

```python
with pytest.raises(InvalidStateError):
    service.update_video_progress(user_id="Alice", lesson_id=1, progress=70)
```

---

## Exception Type Inference

**目的**: 根據失敗原因推斷適當的異常類型

**規則**: 分析 Given 和 When 的上下文，判斷失敗的根本原因

| 失敗原因 | Exception Type | Pattern 範例 |
|---------|---------------|-------------|
| 參數不合法 | InvalidArgumentError | 負數、超出範圍、格式錯誤 |
| 狀態不允許 | InvalidStateError | 進度倒退、訂單已取消 |
| 權限不足 | PermissionDeniedError | 未訂閱、未登入 |
| 資源不存在 | NotFoundError | 課程不存在、商品不存在 |

### Inference Examples

```gherkin
# 參數不合法
When 學生 "Alice" 更新課程 1 的影片進度為 -10%
Then 操作失敗
```
→ InvalidArgumentError

```gherkin
# 狀態不允許
Given 學生 "Alice" 在課程 1 的進度為 80%
When 學生 "Alice" 更新課程 1 的影片進度為 70%
Then 操作失敗
```
→ InvalidStateError

```gherkin
# 權限不足
Given 學生 "Alice" 未訂閱課程 1
When 學生 "Alice" 查詢課程 1 的進度
Then 操作失敗
```
→ PermissionDeniedError

---

## Error Message Verification

```gherkin
When 學生 "Alice" 查詢課程 1 的進度
Then 操作失敗
And 錯誤訊息應為 "無權限查詢此課程"
```

```python
with pytest.raises(PermissionDeniedError) as exc_info:
    service.get_lesson_progress(user_id="Alice", lesson_id=1)

assert str(exc_info.value) == "無權限查詢此課程"
```

---

## Critical Rules

### R1: 成功不需要額外程式碼
```python
# ✅ service.update_video_progress(...)
# ❌ assert service.update_video_progress(...) is None
```

### R2: 失敗必須使用異常處理機制
```python
# ✅ with pytest.raises(InvalidStateError):
# ❌ try-except
```

### R3: 根據上下文選擇異常類型
分析 Given 和 When 的內容推斷

### R4: 失敗時 Query 不用接收 result
在異常處理中,不需要接收回傳值

```python
# ✅ with pytest.raises(PermissionDeniedError):
#       service.get_lesson_progress(...)
# ❌ with pytest.raises(PermissionDeniedError):
#       result = service.get_lesson_progress(...)
```
