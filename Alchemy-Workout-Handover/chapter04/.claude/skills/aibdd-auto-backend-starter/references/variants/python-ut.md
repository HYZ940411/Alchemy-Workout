# Starter Variant: Python Unit Test

技術棧：Behave + FakeRepository（純 Python，無 DB、無 HTTP、無 Docker）

---

## 目錄結構

```
${PROJECT_ROOT}/
├── ${PY_APP_DIR}/                        # 應用程式主目錄（例：app/）
│   ├── __init__.py
│   ├── exceptions.py                     # 自定義例外類別
│   ├── models/
│   │   └── __init__.py                   # （空，由 automation skill 產出）
│   ├── repositories/
│   │   └── __init__.py                   # （空，FakeRepository 放這裡）
│   └── services/
│       └── __init__.py                   # （空，由 automation skill 產出）
├── ${PY_TEST_FEATURES_DIR}/              # 測試目錄（例：tests/features/）
│   ├── environment.py                    # Behave 環境：FakeRepository 初始化
│   └── steps/
│       ├── __init__.py                   # step import 統一入口
│       └── common_then/
│           ├── __init__.py
│           ├── success.py                # @then('操作成功')
│           ├── failure.py                # @then('操作失敗')
│           ├── failure_with_reason.py    # @then('操作失敗，原因為 "{reason}"')
│           └── error_message.py          # @then('錯誤訊息應為 "{message}"')
└── ${SPECS_ROOT_DIR}/                    # 規格檔案（例：specs/）
    ├── activities/
    ├── features/
    └── clarify/
```

---

## 依賴安裝（pip）

### requirements.txt

```
# BDD Testing
behave>=1.2.6

# Core Testing (optional, for development)
pytest>=7.0.0

# Type hints
typing-extensions>=4.0.0

# Development
black>=23.0.0
isort>=5.0.0
mypy>=1.0.0
```

注意：相較 E2E 版本，**不需要** FastAPI、SQLAlchemy、Alembic、Testcontainers、httpx、PyJWT。

### pyproject.toml

```toml
[project]
name = "{{PROJECT_NAME}}"
version = "1.0.0"
description = "{{PROJECT_DESCRIPTION}}"
requires-python = ">=3.11"
dependencies = [
    "behave>=1.2.6",
    "typing-extensions>=4.0.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0.0",
    "black>=23.0.0",
    "isort>=5.0.0",
    "mypy>=1.0.0",
]

[tool.black]
line-length = 100
target-version = ['py311']

[tool.isort]
profile = "black"
line_length = 100

[tool.mypy]
python_version = "3.11"
warn_return_any = true
warn_unused_configs = true

[tool.behave]
format = ["pretty"]
color = true
```

安裝指令：`pip install -r requirements.txt`

---

## 設定檔說明

### behave.ini

```ini
[behave]
paths = {{PY_TEST_FEATURES_DIR}}
format = pretty
color = true
```

---

## 測試框架設定（Behave + FakeRepository）

### environment.py 生命週期

```python
"""Behave 環境設定 - Unit Testing with FakeRepository。

此檔案管理 Unit Test 的整個生命週期：
- before_scenario: 初始化 context 狀態、FakeRepository、Services
- after_scenario: 清理狀態
"""

import os
import sys
from types import SimpleNamespace

project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if project_root not in sys.path:
    sys.path.insert(0, project_root)


def before_scenario(context, scenario):
    """每個 Scenario 執行前初始化。"""
    context.last_error = None
    context.query_result = None
    context.ids = {}
    context.memo = {}

    # 初始化 Repositories（使用 FakeRepository）
    context.repos = SimpleNamespace()
    # 範例：
    # from {{PY_APP_MODULE}}.repositories.fake_some_repository import FakeSomeRepository
    # context.repos.some = FakeSomeRepository()

    # 初始化 Services
    context.services = SimpleNamespace()
    # 範例：
    # from {{PY_APP_MODULE}}.services.some_service import SomeService
    # context.services.some = SomeService(context.repos.some)


def after_scenario(context, scenario):
    """每個 Scenario 執行後清理。"""
    context.last_error = None
    context.query_result = None
    context.ids.clear()
    context.memo.clear()
```

| Hook | 行為 |
|------|------|
| `before_scenario` | 初始化 `context.last_error/query_result/ids/memo` → 建立 `context.repos`（FakeRepository）→ 建立 `context.services`（注入 FakeRepository） |
| `after_scenario` | 清理所有 context 狀態 |

注意：**沒有** `before_all` / `after_all`（不需要啟動/關閉容器）。

### Context 物件結構

```python
context.last_error       # str | None — 最近一次操作錯誤
context.query_result     # Any — 查詢結果
context.ids              # dict — 儲存建立的實體 ID（如 {"小明": 1}）
context.memo             # dict — 通用暫存
context.repos            # SimpleNamespace — 各 FakeRepository 實例
context.services         # SimpleNamespace — 各 Service 實例
```

注意：**沒有** `context.last_response`、`context.api_client`、`context.db_session`、`context.jwt_helper`。

---

## 通用步驟定義

### success.py

```python
@then('操作成功')
def step_impl(context):
    """驗證前一個操作執行成功。"""
    assert context.last_error is None, \
        f"預期操作成功，但發生錯誤: {context.last_error}"
```

### failure.py

```python
@then('操作失敗')
def step_impl(context):
    """驗證前一個操作執行失敗。"""
    assert context.last_error is not None, \
        "預期操作失敗，但操作成功了"
```

### failure_with_reason.py

```python
@then('操作失敗，原因為 "{reason}"')
def step_impl(context, reason):
    assert context.last_error is not None, "預期操作失敗，但操作成功了"
    assert reason in str(context.last_error), \
        f"預期錯誤原因包含 '{reason}'，實際錯誤: {context.last_error}"
```

### error_message.py

```python
@then('錯誤訊息應為 "{message}"')
def step_impl(context, message):
    error = context.last_error
    assert error is not None, "預期操作失敗，但沒有發生錯誤"
    assert message in str(error), \
        f"預期錯誤訊息包含 '{message}'，實際為 '{str(error)}'"
```

注意：Unit Test 版本的 Common Then **只檢查 `context.last_error`**，不涉及 HTTP response。

### app/exceptions.py

```python
class BusinessError(Exception):
    """業務規則例外 - 業務規則違反時拋出"""
    def __init__(self, message: str):
        self.message = message
        super().__init__(message)

class InvalidStateError(Exception):     # 無效狀態
class InvalidArgumentError(Exception):  # 無效參數
class NotFoundError(Exception):         # 資源不存在
class UnauthorizedError(Exception):     # 未授權
class DuplicateError(Exception):        # 重複操作
```

注意：E2E 版本的 `BusinessError` 多一個 `status_code` 參數，Unit Test 版本不需要。

---

## 與 E2E 的差異

| 項目 | E2E | Unit Test |
|------|-----|-----------|
| DB | PostgreSQL（Testcontainers） | **無**（FakeRepository，dict-based） |
| HTTP | FastAPI TestClient | **無**（直接呼叫 Service） |
| Alembic | 有 | **無** |
| Docker | 有（docker-compose.yml） | **無** |
| JWT | 有（jwt_helper.py） | **無** |
| app/core/ | 有（config, deps） | **無** |
| app/api/ | 有（FastAPI routers） | **無** |
| app/schemas/ | 有 | **無** |
| context.last_response | 有（HTTP response） | **無** |
| context.api_client | 有（TestClient） | **無** |
| context.db_session | 有（SQLAlchemy Session） | **無** |
| before_all / after_all | 有（容器生命週期） | **無** |
| 依賴數量 | 約 15 個套件 | 約 7 個套件 |
| helpers/ 目錄 | 有（jwt_helper.py） | **無** |

### 核心架構差異

- **E2E**：透過 HTTP API 測試完整流程（API → Service → Repository → DB）
- **Unit Test**：直接呼叫 Service 層，Repository 使用 FakeRepository（記憶體中的 dict），完全不碰 DB 和網路

---

## arguments.yml 變數對照

| Placeholder | 來源 | 說明 | 範例 |
|-------------|------|------|------|
| `{{PROJECT_NAME}}` | 詢問使用者 | 專案顯示名稱 | `課程平台` |
| `{{PROJECT_DESCRIPTION}}` | 詢問使用者 | 專案描述 | `BDD Workshop - Python Unit Test` |
| `{{PY_APP_DIR}}` | arguments.yml | 應用程式目錄名 | `app` |
| `{{PY_APP_MODULE}}` | 從 PY_APP_DIR 推導 | Python module 路徑（`.` 分隔） | `app` |
| `{{PY_TEST_MODULE}}` | 從 PY_TEST_FEATURES_DIR 推導 | 測試 module 路徑 | `tests.features` |
| `{{PY_TEST_FEATURES_DIR}}` | arguments.yml | 測試 features 目錄路徑 | `tests/features` |
| `{{SPECS_ROOT_DIR}}` | arguments.yml | 規格檔案根目錄 | `specs` |

注意：相較 E2E 版本，**不需要** `{{PROJECT_SLUG}}`（因為沒有 Docker 容器名稱和 DB 名稱）。

推導規則：
- `PY_APP_MODULE` = PY_APP_DIR 中 `/` 換成 `.`
- `PY_TEST_MODULE` = PY_TEST_FEATURES_DIR 中 `/` 換成 `.`

---

## 環境需求

- **Python**: 3.11+
- **Docker**: **不需要**
- **PostgreSQL**: **不需要**
- **額外服務**: **不需要**

Unit Test 策略的最大優勢是零外部依賴，只需要 Python 本身。

---

## Template 檔案對照表

| Template 檔名（`__` = `/`） | 輸出路徑 |
|------------------------------|----------|
| `requirements.txt` | `requirements.txt` |
| `pyproject.toml` | `pyproject.toml` |
| `behave.ini` | `behave.ini` |
| `app__init__.py` | `${PY_APP_DIR}/__init__.py` |
| `app__exceptions.py` | `${PY_APP_DIR}/exceptions.py` |
| `tests__features__environment.py` | `${PY_TEST_FEATURES_DIR}/environment.py` |
| `tests__features__steps__init__.py` | `${PY_TEST_FEATURES_DIR}/steps/__init__.py` |
| `tests__features__steps__common_then__init__.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/__init__.py` |
| `tests__features__steps__common_then__success.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/success.py` |
| `tests__features__steps__common_then__failure.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/failure.py` |
| `tests__features__steps__common_then__failure_with_reason.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/failure_with_reason.py` |
| `tests__features__steps__common_then__error_message.py` | `${PY_TEST_FEATURES_DIR}/steps/common_then/error_message.py` |

額外建立的空 `__init__.py`（無 template）：
- `${PY_APP_DIR}/models/__init__.py`
- `${PY_APP_DIR}/repositories/__init__.py`
- `${PY_APP_DIR}/services/__init__.py`

---

## 驗證步驟

完成骨架建立後，確認以下事項：

1. **檔案完整性**：所有 template 對照表中的檔案都已寫入目標路徑
2. **Placeholder 替換**：專案中不應殘留任何 `{{...}}` 字串
3. **目錄結構**：所有空 `__init__.py` 都已建立（models、repositories、services）
4. **安裝測試**：`pip install -r requirements.txt` 能正常完成
5. **Behave 可執行**：`behave --dry-run` 不報錯（無 feature 檔案時會顯示 0 scenarios）

---

## 安全規則

- 不覆蓋已存在的檔案（跳過並回報）
- 不建立 feature-specific 程式碼（models、repositories、services、step definitions）
- 不執行 `pip install`

---

## 完成後引導

```
Walking skeleton 已建立完成。

下一步：
1. cd ${PROJECT_ROOT} && pip install -r requirements.txt
2. /aibdd-discovery — 開始需求探索
```
