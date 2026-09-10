# Python 程式碼品質規範

供重構階段嚴格遵守。涵蓋 SOLID、Step Definition 組織、Meta 清理、日誌實踐、程式架構、程式碼品質。

---

## 1. SOLID 設計原則

### S — 單一職責

每個類別/函式只負責一件事。

```python
# ❌ Service 做太多事
class AssignmentService:
    def submit_assignment(self, user_id, content):
        self._check_permission(user_id)
        self.repository.save(...)
        self._send_email(user_id)

# ✅ 職責分離
class AssignmentService:
    def __init__(self, assignment_repo, permission_validator, notification_service):
        self.assignment_repo = assignment_repo
        self.permission_validator = permission_validator
        self.notification_service = notification_service

    def submit_assignment(self, user_id, content):
        self.permission_validator.validate(user_id)
        assignment = Assignment(user_id=user_id, content=content)
        self.assignment_repo.save(assignment)
        self.notification_service.notify(user_id)
```

### O — 開放封閉

對擴展開放，對修改封閉。新增功能時透過擴展而非修改現有程式碼。

### L — 里氏替換

子類別可安全替換父類別。

### I — 介面隔離

不強迫實作不需要的方法。

### D — 依賴反轉

高層模組不依賴低層模組。Service 透過建構子注入 Repository。

```python
# ✅ DI
class LessonProgressService:
    def __init__(self, lesson_progress_repo, journey_subscription_repo):
        self.lesson_progress_repo = lesson_progress_repo
        self.journey_subscription_repo = journey_subscription_repo
```

---

## 2. Step Definition 組織規範

### 組織原則

- 一個 Step Pattern 對應一個 Python module
- 使用目錄分類（`aggregate_given/`, `commands/`, `query/` 等）
- 語意化檔名（避免 `steps.py` 大雜燴）

### 目錄結構

```
tests/features/steps/
├── __init__.py              # 匯入所有 step modules
├── aggregate_given/
│   ├── __init__.py
│   ├── lesson_progress.py
│   └── user.py
├── commands/
│   ├── __init__.py
│   └── update_video_progress.py
├── query/
│   ├── __init__.py
│   └── get_lesson_progress.py
├── aggregate_then/
│   ├── __init__.py
│   └── lesson_progress.py
├── readmodel_then/
│   ├── __init__.py
│   └── progress_result.py
├── common_then/
│   ├── __init__.py
│   ├── success.py
│   └── failure.py
└── helpers/
    ├── __init__.py
    ├── status_mapping.py
    └── context_helpers.py
```

### `__init__.py` 匯入

`tests/features/steps/__init__.py` 必須匯入所有 step modules，否則 Behave 找不到。
同名模組（如 aggregate_given 和 aggregate_then 的 lesson_progress）需使用別名。

### 共用邏輯

```python
# helpers/status_mapping.py
STATUS_MAPPING = {
    "進行中": "IN_PROGRESS",
    "已完成": "COMPLETED",
    "未開始": "NOT_STARTED",
}

def map_status(chinese_status: str) -> str:
    return STATUS_MAPPING.get(chinese_status, chinese_status)
```

```python
# helpers/context_helpers.py
def get_user_id(context, user_name: str) -> str:
    if user_name not in context.ids:
        raise KeyError(f"找不到用戶 '{user_name}' 的 ID")
    return context.ids[user_name]
```

---

## 3. Meta 註記清理

### 刪除

- `# TODO: [事件風暴部位: ...]`
- `# TODO: 參考 xxx-Handler.md 實作`
- `# [生成參考 Prompt: ...]`
- 其他開發過程臨時標記

### 保留

- 必要的業務邏輯註解
- 必要的技術註解

### 範例

```python
# 重構前
def step_impl(context, user_name, lesson_id, progress, status):
    """
    TODO: [事件風暴部位: Aggregate - LessonProgress]
    TODO: 參考 Aggregate-Given-Handler.md 實作
    """
    # ...

# 重構後
def step_impl(context, user_name, lesson_id, progress, status):
    """建立用戶的課程進度初始狀態"""
    # ...
```

---

## 4. 日誌實踐

### 框架

使用 Python 標準庫 `logging`，每個模組頂部宣告 logger。

```python
import logging
logger = logging.getLogger(__name__)
```

### 等級規則

| 等級 | 用途 | 範例 |
|------|------|------|
| ERROR | 未預期錯誤，含 stack trace | `logger.error("Unexpected: %s", ex, exc_info=True)` |
| WARNING | 認證失敗、權限不足 | `logger.warning("Expired JWT for %s %s", method, path)` |
| INFO | 業務關鍵操作（寫入完成） | `logger.info("Order created: orderNumber=%s, userId=%s", ...)` |
| DEBUG | 詳細流程、查詢結果數量 | `logger.debug("Fetching order=%s for userId=%s", ...)` |

### 各層策略

- **API 層**：`logger.info` 記錄請求進入（含 userId + 關鍵參數）
- **Service 層**：`logger.info` 寫入操作完成；`logger.debug` 查詢結果
- **Security 層**：`logger.warning` 認證失敗

### 格式規則

- 使用 `%s`/`%d` 佔位符（logging 延遲格式化），**不用 f-string**
- 使用 `key=value` 格式（方便 grep 搜尋）
- 訊息前加事件描述（`Order created:`, `Payment submitted:`）

### 禁止

- ❌ `print()` 取代 `logging`
- ❌ f-string 格式化（`logger.info(f"msg {var}")`）
- ❌ 在迴圈中用 `logger.info`
- ❌ 記錄敏感資訊（密碼、JWT token 全文）

### 配置

```python
# app/core/logging_config.py
import logging

def setup_logging():
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s [%(threadName)s] %(levelname)-5s %(name)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    logging.getLogger("uvicorn").setLevel(logging.INFO)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)
```

---

## 5. 程式架構規範

### 分層

```
app/
├── api/           # API Endpoints（HTTP 轉換）
├── services/      # Business Logic
├── repositories/  # Data Access（SQLAlchemy）
├── models/        # ORM Models
├── schemas/       # Request/Response（Pydantic）
├── core/          # config, deps, security
└── main.py
```

### 各層職責

| 層 | 負責 | 不負責 |
|----|------|--------|
| API | 路由、解析 Request、構建 Response、認證 | 業務邏輯、資料存取 |
| Service | 業務規則、協調 Repository、拋業務異常 | HTTP 處理、直接操作 DB |
| Repository | SQLAlchemy CRUD、封裝查詢 | 業務規則 |

### 依賴注入

Service 透過建構子接收 Repository，讓測試和生產環境可切換。

```python
class OrderService:
    def __init__(self, order_repo: OrderRepository, product_repo: ProductRepository):
        self.order_repo = order_repo
        self.product_repo = product_repo
```

### 常見錯誤

- ❌ 業務邏輯寫在 Controller
- ❌ Service 直接操作資料庫（繞過 Repository）
- ❌ Domain 程式碼放在 `walking_skeleton/`

---

## 6. 程式碼品質

### Early Return

```python
# ❌ 深層巢狀
def process(data):
    if data:
        if data.is_valid():
            return process_data(data)

# ✅ Guard Clause
def process(data):
    if not data:
        raise DataError()
    if not data.is_valid():
        raise ValueError()
    return process_data(data)
```

### 靜態屬性

```python
# ❌ 每次調用都創建
def process(self, status):
    mapping = {"A": "狀態A", "B": "狀態B"}
    return mapping.get(status)

# ✅ 類別屬性
STATUS_MAPPING = {"A": "狀態A", "B": "狀態B"}

def process(self, status):
    return self.STATUS_MAPPING.get(status)
```

### DRY

重複 3+ 次的邏輯提取共用方法。

```python
# ✅ 提取共用驗證
def _validate_subscription(self, user_id):
    subscription = self.journey_subscription_repo.find_by_user(user_id)
    if not subscription:
        raise SubscriptionNotFoundError()
    return subscription
```

### 命名

- 函數名表達意圖（`update_video_progress` 而非 `process`）
- 布林變數用 `is_`/`has_`/`can_` 開頭

---

## 檢查清單

- [ ] 每個類別/函式只負責一件事（SRP）
- [ ] Service 透過建構子注入 Repository（DIP）
- [ ] 一個 Step Pattern 一個 module
- [ ] `__init__.py` 匯入所有 step modules
- [ ] 所有 TODO/META 標記已清除
- [ ] 所有模組宣告 `logger = logging.getLogger(__name__)`
- [ ] 日誌使用 `%s` 佔位符 + key=value 格式
- [ ] Controllers/Services/Repositories 在正確的 `app/` 子目錄
- [ ] 使用 Early Return 減少巢狀
- [ ] 重複資料提升為類別屬性
- [ ] 命名清晰表達用途
