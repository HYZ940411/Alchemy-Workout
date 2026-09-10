# Refactor Variant: Python E2E

## Linter / Formatter

```bash
black --line-length 100 .
isort --profile black .
mypy --python-version 3.11 app/
ruff check .
```

## 測試命令

```bash
# 每次重構後必須執行
behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore
```

## 入口

### 被 control-flow 調用

接收 `FEATURE_FILE`，直接進入重構流程。

### 獨立使用

```
請指定要重構的範圍：
1. 特定 Feature 相關的程式碼（提供 feature file 路徑）
2. 全域重構（所有已通過測試的程式碼）
```

---

## Python 特有重構模式

### Type Hints

- 所有 public 函數加上 type hints
- Repository 方法加上 `Optional[T]` 回傳型別
- Service 方法加上參數和回傳型別

```python
# 重構前
def find(self, user_id, lesson_id):
    return self._data.get((user_id, lesson_id))

# 重構後
def find(self, user_id: str, lesson_id: int) -> Optional[LessonProgress]:
    return self._data.get((user_id, lesson_id))
```

### Dataclass / NamedTuple

Model 若只是資料容器，考慮用 `@dataclass`：

```python
from dataclasses import dataclass

@dataclass
class LessonProgress:
    user_id: str
    lesson_id: int
    progress: int
    status: str
```

### Exception 層級

```python
class BusinessError(Exception): ...
class InvalidStateError(BusinessError): ...
class NotFoundError(BusinessError): ...
```

### Import 排序（isort 規則）

```python
# 1. 標準庫
from typing import Optional

# 2. 第三方
from behave import given, when, then
from sqlalchemy.orm import Session

# 3. 本地
from app.models.lesson_progress import LessonProgress
```

### Behave Step 整理

- 一個 step 一個檔案
- 共用 helpers 提取到 `steps/helpers.py`
- 狀態映射 dict 集中定義

```python
# steps/helpers.py
STATUS_MAP = {
    "進行中": "IN_PROGRESS",
    "已完成": "COMPLETED",
    "未開始": "NOT_STARTED",
}

def translate_status(chinese: str) -> str:
    return STATUS_MAP.get(chinese, chinese)
```

---

## 常見重構方向

### Step Definition 層
- 提取共用的 Given 步驟到 helpers
- 統一 context.ids 的使用模式
- 消除重複的 status mapping 邏輯
- 改善 DataTable 解析的可讀性

### Service 層
- 提取業務規則為獨立方法
- 消除過長的方法
- 統一異常處理模式
- Early Return / Guard Clause

### API 層
- 統一回應格式
- 提取共用的驗證邏輯

### Repository 層
- 方法命名一致性
- 查詢優化

---

## 品質規範

完整 Python 品質規範詳見 `references/code-quality/python.md`。
