# Refactor Variant: Python UT

## Linter / Formatter

```bash
black --line-length 100 .
isort --profile black .
mypy --python-version 3.11 app/
ruff check .
```

## 測試命令

```bash
# 每次重構後必須執行（不需要 Docker）
behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore
```

## 入口

### 被 control-flow 調用

接收 `FEATURE_FILE`，直接進入重構流程。

### 獨立使用

詢問目標 Feature File，確認綠燈階段已完成後執行重構。

---

## 兩階段工作流

**Python UT 特有** — 先重構測試碼，再重構產品碼。

```
執行測試（確認綠燈）
    │
    ▼
【Phase A】重構測試碼（steps / environment）
    │
    ▼
執行測試（確認仍然綠燈）
    │
    ▼
【Phase B】重構產品碼（models / repositories / services）
    │
    ▼
執行測試（確認仍然綠燈）
    │
    ▼
完成
```

**關鍵**：Phase 順序不可顛倒。每個 Phase 結束跑測試，Phase 內每次小步驟也跑測試。

---

## 安全規則

- **兩段式順序不可顛倒** — Phase A → 綠燈 → Phase B → 綠燈
- **禁止自動抽 helpers** — 除非使用者明確要求，不新增 `helpers.py`、不搬移 step 結構
- **禁止跨檔搬動** — 優先在原檔案內做最小改善（移除 TODO、補 docstring、調整命名/縮排）
- **如果真的要抽共用** — 必須先徵詢確認，一次只抽一個小片段，每次變更後跑測試

---

## Phase A：測試程式碼重構

### 範圍

- `${PY_STEPS_DIR}/**/*.py`（Step Definitions）
- `${PY_ENV_FILE}`（environment hooks）

### 常見任務

1. **移除 TODO 註解** → 替換為有意義的 docstring

```python
# 重構前
def step_impl(context, user_name, lesson_id, progress, status):
    """
    TODO: [事件風暴部位: Aggregate - LessonProgress]
    TODO: 參考 /aibdd-auto-python-ut-handlers-aggregate-given 實作
    """
    ...

# 重構後
def step_impl(context, user_name, lesson_id, progress, status):
    """建立用戶的課程進度初始狀態"""
    ...
```

2. **改善命名** → 變數名稱更語意化
3. **簡化邏輯** → 減少巢狀、使用 Early Return
4. **調整格式** → 統一程式碼風格

---

## Phase B：生產程式碼重構

### 範圍

- `${PY_MODELS_DIR}/**/*.py`（Aggregates）
- `${PY_REPOSITORIES_DIR}/**/*.py`（FakeRepositories）
- `${PY_SERVICES_DIR}/**/*.py`（Services）
- `${PY_APP_DIR}/exceptions.py`（自定義例外）

### 常見任務

1. **改善 Model** → 添加型別註解、property

```python
# 重構前
class LessonProgress:
    def __init__(self, user_id, lesson_id, progress, status):
        self.user_id = user_id
        self.lesson_id = lesson_id
        self.progress = progress
        self.status = status

# 重構後
from dataclasses import dataclass

@dataclass
class LessonProgress:
    user_id: str
    lesson_id: int
    progress: int
    status: str
```

2. **改善 Repository 介面** → 方法命名一致性、型別標註

```python
def find(self, user_id: str, lesson_id: int) -> Optional[LessonProgress]:
    return self._data.get((user_id, lesson_id))
```

3. **改善 Service** → Early Return、Guard Clause

```python
# 重構前
def update_video_progress(self, user_id, lesson_id, progress):
    existing = self.lesson_progress_repository.find(user_id, lesson_id)
    if existing:
        if progress <= existing.progress:
            raise BusinessError("進度不可倒退")
    ...

# 重構後
def update_video_progress(self, user_id: str, lesson_id: int, progress: int) -> None:
    existing = self.lesson_progress_repository.find(user_id, lesson_id)
    if existing and progress <= existing.progress:
        raise BusinessError("進度不可倒退")
    ...
```

4. **提取共用常數** → 狀態映射、錯誤訊息集中定義

---

## FakeRepository 特有模式

UT 的 Repository 是 dict-based，重構重點不同於 E2E：

- 確保 key 結構一致（tuple vs single）
- 方法簽名加上型別標註
- `Optional[T]` 回傳型別
- 不需要 session/commit（無 DB）

---

## Critical Rules

1. **每個 Phase 與每個小步驟後都跑測試**
2. **一次只做一個小重構**
3. **只抽取重複 3+ 次的邏輯**
4. **保持 step 函數簡潔**
5. **不改變測試行為**
6. **移除所有 TODO 註解**
7. **遵守安全規則**（不自動抽 helpers、不跨檔搬動）

---

## 品質規範

完整 Python 品質規範詳見 `references/code-quality/python.md`。
