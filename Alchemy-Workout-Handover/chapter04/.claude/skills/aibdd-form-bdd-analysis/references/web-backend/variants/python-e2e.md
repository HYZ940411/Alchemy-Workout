# Red Variant: python-e2e

## 測試框架

- **語言**：Python 3.11+
- **BDD 框架**：Behave
- **HTTP Client**：FastAPI TestClient (`from fastapi.testclient import TestClient`)
- **ORM**：SQLAlchemy 2.0
- **資料庫**：PostgreSQL 16（透過 Testcontainers 啟動）
- **認證**：JWT Token（自訂 JwtHelper）
- **測試執行**：`behave ${PY_TEST_FEATURES_DIR}/{feature_file}`
- **紅燈失敗原因**：HTTP 404 Not Found（後端 API 尚未實作）

## 檔案結構

```
${PY_APP_DIR}/
├── models/                    # SQLAlchemy ORM Models（生產環境）
│   ├── __init__.py            # 包含 Base = declarative_base()
│   └── {aggregate}.py
├── repositories/              # SQLAlchemy Repositories（生產環境）
│   ├── __init__.py
│   └── {aggregate}_repository.py
├── services/                  # Services（紅燈不實作）
├── api/                       # FastAPI endpoints（紅燈不實作）
└── main.py                    # FastAPI app

${PY_TEST_FEATURES_DIR}/
├── environment.py             # hooks：Testcontainers + PostgreSQL + context 初始化
├── helpers/                   # JWT Helper 等輔助工具
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
def before_scenario(context, scenario):
    # 狀態
    context.last_error = None
    context.last_response = None     # HTTP Response
    context.query_result = None
    context.ids = {}                 # 名稱 -> ID 映射
    context.memo = {}

    # 依賴
    context.db_session = _SessionLocal()     # SQLAlchemy Session
    context.api_client = TestClient(app)     # FastAPI TestClient
    context.jwt_helper = JwtHelper()         # JWT Token 生成器
    context.repos = SimpleNamespace()        # Repositories
    context.services = SimpleNamespace()     # Services
```

### Step Definition 範例

函數簽名：第一個參數必須是 `context`，後接 pattern 解析的參數。不使用 fixtures。

```python
from behave import given

@given('用戶 "{user_name}" 在課程 {lesson_id:d} 的進度為 {progress:d}%，狀態為 "{status}"')
def step_impl(context, user_name, lesson_id, progress, status):
    db_session = context.db_session
    repository = LessonProgressRepository(db_session)
    # ...
```

Behave 參數類型標記：
- `{param}` — 字串（預設）
- `{param:d}` — 整數
- `{param:f}` — 浮點數
- `"{param}"` — 帶引號的字串

### Handler 實作範例

#### Aggregate-Given（建立前置資料 — 寫入 DB）

```python
from behave import given
from app.models.cart_item import CartItem
from app.repositories.cart_repository import CartRepository

@given('用戶 "{user_name}" 的購物車中商品 "{product_id}" 的數量為 {quantity:d}')
def step_impl(context, user_name, product_id, quantity):
    db_session = context.db_session
    repository = CartRepository(db_session)

    if user_name not in context.ids:
        raise KeyError(f"找不到用戶 '{user_name}' 的 ID，請先建立用戶")
    user_id = context.ids[user_name]

    cart_item = CartItem(
        user_id=user_id,
        product_id=product_id,
        quantity=quantity
    )
    repository.save(cart_item)
```

DataTable 版本：

```python
@given('系統中有以下用戶：')
def step_impl(context):
    db_session = context.db_session
    repository = UserRepository(db_session)

    for row in context.table:
        user = User(
            id=int(row['userId']),
            name=row['name'],
            email=row['email']
        )
        repository.save(user)
        context.ids[row['name']] = user.id
```

#### Command（執行 HTTP API）

```python
from behave import when

@when('用戶 "{user_name}" 更新課程 {lesson_id:d} 的影片進度為 {progress:d}%')
def step_impl(context, user_name, lesson_id, progress):
    if user_name not in context.ids:
        raise KeyError(f"找不到用戶 '{user_name}' 的 ID")
    user_id = context.ids[user_name]

    token = context.jwt_helper.generate_token(user_id)

    request_body = {
        "lesson_id": lesson_id,
        "progress": progress
    }

    response = context.api_client.post(
        "/api/v1/lesson-progress/update-video-progress",
        headers={"Authorization": f"Bearer {token}"},
        json=request_body
    )
    context.last_response = response
```

#### Query（執行 HTTP GET API）

```python
from behave import when

@when('用戶 "{user_name}" 查詢課程 {lesson_id:d} 的進度')
def step_impl(context, user_name, lesson_id):
    if user_name not in context.ids:
        raise KeyError(f"找不到用戶 '{user_name}' 的 ID")
    user_id = context.ids[user_name]

    token = context.jwt_helper.generate_token(user_id)
    url = f"/api/v1/lessons/{lesson_id}/progress"

    response = context.api_client.get(
        url,
        headers={"Authorization": f"Bearer {token}"}
    )
    context.last_response = response
```

有 Query Parameters 時使用 `params` 參數：

```python
response = context.api_client.get(
    "/api/v1/journeys/1/lessons",
    params={"chapter_id": 2},
    headers={"Authorization": f"Bearer {token}"}
)
```

#### Aggregate-Then（驗證 DB 狀態）

```python
from behave import then
from app.repositories.lesson_progress_repository import LessonProgressRepository

@then('用戶 "{user_name}" 在課程 {lesson_id:d} 的進度應為 {progress:d}%')
def step_impl(context, user_name, lesson_id, progress):
    db_session = context.db_session
    repository = LessonProgressRepository(db_session)

    if user_name not in context.ids:
        raise KeyError(f"找不到用戶 '{user_name}' 的 ID")
    user_id = context.ids[user_name]

    progress_entity = repository.find_by_user_and_lesson(
        user_id=user_id,
        lesson_id=lesson_id
    )

    assert progress_entity is not None, f"找不到課程進度"
    assert progress_entity.progress == progress, \
        f"預期進度 {progress}%，實際 {progress_entity.progress}%"
```

#### ReadModel-Then（驗證 HTTP Response）

```python
from behave import then

@then('查詢結果應包含進度 {progress:d}，狀態為 "{status}"')
def step_impl(context, progress, status):
    response = context.last_response
    data = response.json()

    status_mapping = {
        "進行中": "IN_PROGRESS",
        "已完成": "COMPLETED",
        "未開始": "NOT_STARTED",
    }
    expected_status = status_mapping.get(status, status)

    assert data["progress"] == progress, f"預期進度 {progress}，實際 {data['progress']}"
    assert data["status"] == expected_status, f"預期狀態 {expected_status}，實際 {data['status']}"
```

#### Success-Failure（驗證 HTTP Status Code）

```python
from behave import then

@then("操作成功")
def step_impl(context):
    response = context.last_response
    assert response.status_code in [200, 201, 204], \
        f"預期成功（2XX），實際 {response.status_code}"

@then("操作失敗")
def step_impl(context):
    response = context.last_response
    assert response.status_code >= 400, \
        f"預期失敗（4XX+），實際 {response.status_code}"
```

## API 呼叫模式

- **HTTP Client**：`context.api_client`（FastAPI TestClient）
- **認證**：`context.jwt_helper.generate_token(user_id)` 產生 JWT，放在 `Authorization: Bearer {token}` header
- **Command**：`context.api_client.post()` / `.put()` / `.patch()` / `.delete()`，response 存入 `context.last_response`
- **Query**：`context.api_client.get()`，response 存入 `context.last_response`
- **Path Parameters**：使用 f-string（`f"/api/v1/lessons/{lesson_id}/progress"`）
- **Query Parameters**：使用 `params` 參數（`params={"category": "電子產品"}`）

## 基礎設施定義

### SQLAlchemy Model

```python
# ${PY_MODELS_DIR}/cart_item.py
from sqlalchemy import Column, String, Integer
from app.models import Base

class CartItem(Base):
    __tablename__ = 'cart_items'
    user_id = Column(String, primary_key=True)
    product_id = Column(String, primary_key=True)
    quantity = Column(Integer, nullable=False)
```

### Repository

```python
# ${PY_REPOSITORIES_DIR}/cart_repository.py
from typing import Optional
from sqlalchemy.orm import Session
from app.models.cart_item import CartItem

class CartRepository:
    def __init__(self, session: Session):
        self.session = session

    def save(self, cart_item: CartItem) -> None:
        self.session.merge(cart_item)  # 使用 merge 支援 upsert
        self.session.commit()

    def find_by_user_and_product(self, user_id: str, product_id: str) -> Optional[CartItem]:
        return self.session.query(CartItem).filter_by(
            user_id=user_id,
            product_id=product_id
        ).first()
```

## 特殊規則

1. **API JSON 欄位命名**：必須與 `api.yml` schema 定義一致（api.yml 是 SSOT）。若 api.yml 定義 `newLeadsThisMonth`，測試中必須用 `newLeadsThisMonth`，不可改為 `new_leads_this_month`。
2. **API Endpoint Path**：必須嚴格遵循 `specs/api.yml`，透過 `summary` 欄位與 Gherkin 語句對應找到正確的 path 和 HTTP method。
3. **Repository 使用 `merge` 而非 `add`**：Repository.save() 使用 `session.merge()` 支援 upsert 語意。
4. **中文狀態映射**：Gherkin 中的中文狀態（如「進行中」）必須映射為英文 enum（如 `IN_PROGRESS`）。
5. **ID 儲存**：Given 建立的實體 ID 必須存入 `context.ids[natural_key]`，後續 Command/Query 透過 `context.ids` 取得。
6. **不驗證 Response（Command）**：Command Handler 只儲存 response，不做 assert，驗證交給 Then。
7. **不重新呼叫 API（ReadModel-Then）**：使用 When 中儲存的 `context.last_response`，不重新發請求。
8. **Testcontainers 環境**：執行前需確認 Docker Desktop 已啟動。
9. **紅燈完成後移除 `@ignore` tag**：讓 feature file 可被回歸測試涵蓋。
