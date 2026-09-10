# Red Variant: python-ut

## 測試框架

- **語言**：Python 3.11+
- **BDD 框架**：Behave
- **測試策略**：Unit Test（直接呼叫 Service 方法，不透過 HTTP）
- **Repository**：FakeRepository（dict-based 記憶體儲存）
- **資料庫**：無（不需要真實 DB，不需要 Docker）
- **認證**：無（不需要 JWT）
- **測試執行**：`behave ${PY_TEST_FEATURES_DIR}/{feature_file}`
- **紅燈失敗原因**：`NotImplementedError`（Service/FakeRepository 方法尚未實作）

## 檔案結構

```
${PY_APP_DIR}/
├── __init__.py
├── models/                    # Aggregate 類別（純 Python class）
│   ├── __init__.py
│   └── {aggregate}.py
├── repositories/              # FakeRepository（dict-based，紅燈拋 NotImplementedError）
│   ├── __init__.py
│   └── {aggregate}_repository.py
├── services/                  # Service 介面（紅燈拋 NotImplementedError）
│   ├── __init__.py
│   └── {domain}_service.py
└── exceptions.py

${PY_TEST_FEATURES_DIR}/
├── environment.py             # hooks：context 初始化（repos + services）
├── steps/                     # Step Definitions
│   ├── {subdomain}/           # 按業務領域分（lesson, order, product, role）
│   │   ├── aggregate_given/
│   │   ├── commands/
│   │   ├── query/
│   │   ├── aggregate_then/
│   │   └── readmodel_then/
│   └── common_then/           # 跨 subdomain 共用（操作成功/失敗）
└── *.feature                  # Feature files（symlink 自 ${FEATURE_SPECS_DIR}）
```

**一個 Step Pattern 對應一個 `.py` 檔案**，檔案內只放一個 step function。

## 程式碼模式

### 依賴注入機制

所有依賴透過 Behave `context` 物件傳遞，在 `environment.py` 的 `before_scenario` 中初始化：

```python
# ${PY_ENV_FILE}
from types import SimpleNamespace
from app.repositories.lesson_progress_repository import LessonProgressRepository
from app.services.lesson_service import LessonService

def before_scenario(context, scenario):
    # 狀態
    context.last_error = None        # Exception | None（When 寫入、Then 只讀）
    context.query_result = None      # Any | None（When(Query) 寫入、Then(ReadModel) 只讀）
    context.ids = {}                 # dict：名稱 -> ID 映射
    context.memo = {}                # dict：其他臨時共享狀態

    # 依賴（Fake Repositories + Services）
    context.repos = SimpleNamespace()
    context.services = SimpleNamespace()

    context.repos.lesson_progress = LessonProgressRepository()

    context.services.lesson = LessonService(
        lesson_progress_repository=context.repos.lesson_progress
    )

def after_scenario(context, scenario):
    context.last_error = None
    context.query_result = None
    context.ids.clear()
    context.memo.clear()
```

**核心契約**：
- Steps 只能從 `context.repos.*` / `context.services.*` 取依賴
- 禁止在 step 內 new repo/service
- 禁止 module/global 變數跨 scenario
- 每個 scenario 前都重新初始化

### Step Definition 範例

函數簽名：第一個參數必須是 `context`，後接 pattern 解析的參數。不使用 fixtures。

```python
from behave import given

@given('用戶 "{user_name}" 在課程 {lesson_id:d} 的進度為 {progress:d}%，狀態為 "{status}"')
def step_impl(context, user_name, lesson_id, progress, status):
    repo = context.repos.lesson_progress
    # ...
```

Behave 參數類型標記：
- `{param}` — 字串（預設）
- `{param:d}` — 整數
- `{param:f}` — 浮點數
- `"{param}"` — 帶引號的字串

### Handler 實作範例

#### Aggregate-Given（建立前置資料 — 存入 FakeRepository）

```python
from behave import given
from app.models.lesson_progress import LessonProgress

@given('用戶 "{user_name}" 在課程 {lesson_id:d} 的進度為 {progress:d}%，狀態為 "{status}"')
def step_impl(context, user_name, lesson_id, progress, status):
    # 取得或建立用戶 ID
    if user_name not in context.ids:
        context.ids[user_name] = user_name
    user_id = context.ids[user_name]

    # 狀態映射（中文 -> 英文 enum）
    status_map = {
        "進行中": "IN_PROGRESS",
        "已完成": "COMPLETED",
        "未開始": "NOT_STARTED",
    }

    # 建立 Aggregate
    lesson_progress = LessonProgress(
        user_id=user_id,
        lesson_id=lesson_id,
        progress=progress,
        status=status_map.get(status, status)
    )

    # 儲存到 FakeRepository（從 context 取得）
    context.repos.lesson_progress.save(lesson_progress)
```

DataTable 版本：

```python
@given('系統中有以下課程：')
def step_impl(context):
    for row in context.table:
        lesson = Lesson(
            lesson_id=int(row['lessonId']),
            name=row['name'],
            lesson_type=row['type'],
            journey_id=int(row['journeyId']),
            chapter_id=int(row['chapterId']),
            reward_exp=int(row['rewardExp'])
        )
        context.repos.lesson.save(lesson)
```

#### Command（直接呼叫 Service 方法）

```python
from behave import when

@when('用戶 "{user_name}" 更新課程 {lesson_id:d} 的影片進度為 {progress:d}%')
def step_impl(context, user_name, lesson_id, progress):
    if user_name not in context.ids:
        raise KeyError(
            f"找不到 user_name '{user_name}' 對應的 user_id。"
            f"請確認是否在 Given 步驟中建立了該用戶"
        )
    user_id = context.ids[user_name]

    try:
        context.services.lesson.update_video_progress(
            user_id=user_id,
            lesson_id=lesson_id,
            progress=progress
        )
        context.last_error = None
    except Exception as e:
        context.last_error = e
```

Given + Command（已完成動作，通常不需要 try-except）：

```python
@given('用戶 "{user_name}" 已訂閱旅程 {journey_id:d}')
def step_impl(context, user_name, journey_id):
    if user_name not in context.ids:
        raise KeyError(f"找不到 user_name '{user_name}' 對應的 user_id。")
    user_id = context.ids[user_name]

    # Given 通常假設成功，不需要 try-except
    context.services.journey.subscribe(
        user_id=user_id,
        journey_id=journey_id
    )
```

#### Query（直接呼叫 Service 查詢方法）

```python
from behave import when

@when('用戶 "{user_name}" 查詢課程 {lesson_id:d} 的進度')
def step_impl(context, user_name, lesson_id):
    if user_name not in context.ids:
        raise KeyError(f"找不到 user_name '{user_name}' 對應的 user_id。")
    user_id = context.ids[user_name]

    try:
        context.query_result = context.services.lesson.get_progress(
            user_id=user_id,
            lesson_id=lesson_id
        )
        context.last_error = None
    except Exception as e:
        context.last_error = e
        context.query_result = None
```

#### Aggregate-Then（驗證 FakeRepository 中的狀態）

```python
from behave import then

@then('用戶 "{user_name}" 在課程 {lesson_id:d} 的進度應為 {progress:d}%')
def step_impl(context, user_name, lesson_id, progress):
    if user_name not in context.ids:
        raise KeyError(
            f"找不到 user_name '{user_name}' 對應的 user_id。"
            f"請確認是否在 Given 步驟中建立了該用戶"
        )
    user_id = context.ids[user_name]

    lesson_progress = context.repos.lesson_progress.find(
        user_id=user_id,
        lesson_id=lesson_id
    )

    assert lesson_progress is not None, \
        f"找不到用戶 {user_name} 在課程 {lesson_id} 的進度"
    assert lesson_progress.progress == progress, \
        f"預期進度 {progress}%，實際為 {lesson_progress.progress}%"
```

#### ReadModel-Then（驗證 Query 回傳值）

```python
from behave import then

@then('查詢結果應包含進度 {progress:d}，狀態為 "{status}"')
def step_impl(context, progress, status):
    result = context.query_result

    status_map = {
        "進行中": "IN_PROGRESS",
        "已完成": "COMPLETED",
        "未開始": "NOT_STARTED",
    }
    expected_status = status_map.get(status, status)

    assert result is not None, "查詢結果為 None"
    assert result.progress == progress, f"預期進度 {progress}，實際 {result.progress}"
    assert result.status == expected_status, f"預期狀態 {expected_status}，實際 {result.status}"
```

#### Success-Failure（驗證 context.last_error）

```python
from behave import then

@then("操作成功")
def step_impl(context):
    assert context.last_error is None, \
        f"預期操作成功，但發生錯誤：{context.last_error}"

@then("操作失敗")
def step_impl(context):
    assert context.last_error is not None, \
        "預期操作失敗，但操作成功了"
```

## API 呼叫模式

**不透過 HTTP，直接呼叫 Service 方法**：

- **Command**：`context.services.{domain}.{method}(...)`，用 try-except 捕獲錯誤到 `context.last_error`
- **Query**：`context.services.{domain}.{method}(...)`，結果存入 `context.query_result`
- **Given（Aggregate）**：直接使用 `context.repos.{aggregate}.save(...)`，不透過 Service
- **Given（Command）**：直接呼叫 `context.services.{domain}.{method}(...)`，不需要 try-except

## 基礎設施定義

### Aggregate 類別（純 Python class）

```python
# ${PY_MODELS_DIR}/lesson_progress.py
class LessonProgress:
    """課程進度 Aggregate"""

    def __init__(self, user_id: str, lesson_id: int, progress: int, status: str):
        self.user_id = user_id
        self.lesson_id = lesson_id
        self.progress = progress
        self.status = status
```

### FakeRepository（紅燈：NotImplementedError）

```python
# ${PY_REPOSITORIES_DIR}/lesson_progress_repository.py
from typing import Optional
from app.models.lesson_progress import LessonProgress

class LessonProgressRepository:
    """課程進度 Repository - 僅定義介面，不實作"""

    def save(self, lesson_progress: LessonProgress) -> None:
        raise NotImplementedError("紅燈階段：尚未實作")

    def find(self, user_id: str, lesson_id: int) -> Optional[LessonProgress]:
        raise NotImplementedError("紅燈階段：尚未實作")
```

綠燈階段會改為 dict-based 實作：

```python
# 綠燈參考（紅燈階段不實作）
class LessonProgressRepository:
    def __init__(self):
        self._data = {}  # Key: (user_id, lesson_id)

    def save(self, lesson_progress):
        key = (lesson_progress.user_id, lesson_progress.lesson_id)
        self._data[key] = lesson_progress

    def find(self, user_id, lesson_id):
        return self._data.get((user_id, lesson_id))
```

### Service 介面（紅燈：NotImplementedError）

```python
# ${PY_SERVICES_DIR}/lesson_service.py
from app.repositories.lesson_progress_repository import LessonProgressRepository

class LessonService:
    """課程服務 - 僅定義介面，不實作"""

    def __init__(self, lesson_progress_repository: LessonProgressRepository):
        self.lesson_progress_repository = lesson_progress_repository

    def update_video_progress(self, user_id: str, lesson_id: int, progress: int) -> None:
        raise NotImplementedError("紅燈階段：尚未實作")
```

## 特殊規則

1. **不需要 Docker / Testcontainers**：FakeRepository 使用 dict 儲存在記憶體中，不需要真實資料庫。
2. **不需要 HTTP / JWT**：直接呼叫 Service 方法，不透過 HTTP API，不需要認證。
3. **When 必須包裹 try-except**：所有 When（Command）步驟都需要捕獲 Exception 到 `context.last_error`，供 Then 驗證操作成功/失敗。
4. **Given（Aggregate）不透過 Service**：直接使用 `context.repos.*.save()` 建立前置資料，不呼叫 Service。
5. **context.last_error 是直接屬性**：`context.last_error = e`，不是 dict（那是 pytest-bdd 的做法）。
6. **中文狀態映射**：Gherkin 中的中文狀態（如「進行中」）必須映射為英文 enum（如 `IN_PROGRESS`）。
7. **ID 儲存**：Given 建立的實體 ID 存入 `context.ids[user_name] = user_name`（或 hash）。更新已存在資料時，ID 必須已存在於 `context.ids`，否則拋出 `KeyError`。
8. **FakeRepository 和 Service 只定義簽名不實作**：紅燈階段所有方法體都是 `raise NotImplementedError("紅燈階段：尚未實作")`。
9. **紅燈完成後移除 `@ignore` tag**：讓 feature file 可被回歸測試涵蓋。
