# Aggregate-Given-Handler

## Trigger
Given 語句描述**Aggregate 的存在狀態**，即定義 Aggregate 的屬性值

**識別規則**：
- 語句中包含實體名詞 + 屬性描述
- 描述「某個東西的某個屬性是某個值」
- 常見句型（非窮舉）:「在...的...為」「的...為」「包含」「存在」「有」

**通用判斷**: 如果 Given 是在建立測試的初始資料狀態（而非執行動作），就使用此 Handler

## Task
創建 SQLAlchemy Model → Repository.save() → 儲存 ID 到 context

## E2E 特色
- 使用 SQLAlchemy ORM Model
- 使用 Repository Pattern（內部用 SQLAlchemy Session）
- 寫入真實的 PostgreSQL 資料庫
- 將 Aggregate 的自然鍵（natural key）和 ID 存入 context

---

## Steps

1. 識別 Aggregate 名稱
2. 從 DBML 提取: 屬性、型別、複合 Key、enum
3. 從 Gherkin 提取: Key 值、屬性值
4. 創建 SQLAlchemy Model instance
5. 使用 Repository.save() 寫入資料庫
6. 將 ID 儲存到 context（格式: `{natural_key}.id`）

---

## Pattern Examples (Python)

### 單一 Aggregate

```gherkin
Given 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量為 2
```

```python
# 1. 初始化 Repository
repository = CartRepository(db_session)

# 2. 創建 Aggregate（SQLAlchemy Model instance）
cart_item = CartItem(
    user_id="Alice",
    product_id="PROD-001",
    quantity=2
)

# 3. 儲存到資料庫
repository.save(cart_item)

# 4. 儲存 ID 到 context
context["Alice.id"] = cart_item.user_id
```

### 複合主鍵 Aggregate

```gherkin
Given 訂單 "ORDER-123" 中商品 "PROD-001" 在倉庫 "WH-01" 的數量為 5
```

```python
repository = OrderItemWarehouseRepository(db_session)

item = OrderItemWarehouse(
    order_id="ORDER-123",
    product_id="PROD-001",
    warehouse_id="WH-01",
    quantity=5
)
repository.save(item)

# 儲存所有 natural keys
context["ORDER-123.id"] = item.order_id
context["PROD-001.id"] = item.product_id
context["WH-01.id"] = item.warehouse_id
```

---

## Repository Pattern with SQLAlchemy

### Repository 結構

```python
from typing import Optional
from sqlalchemy.orm import Session
from tests.e2e.models.cart_item import CartItem


class CartRepository:
    """購物車 Repository - 使用 SQLAlchemy"""
    
    def __init__(self, session: Session):
        self.session = session
    
    def save(self, cart_item: CartItem) -> None:
        """保存購物車項目到資料庫"""
        self.session.merge(cart_item)  # 使用 merge 處理 upsert
        self.session.commit()
    
    def find_by_user_and_product(
        self, 
        user_id: str, 
        product_id: str
    ) -> Optional[CartItem]:
        """根據用戶和商品查詢購物車項目"""
        return self.session.query(CartItem).filter_by(
            user_id=user_id,
            product_id=product_id
        ).first()
```

### SQLAlchemy Model 結構

```python
from sqlalchemy import Column, String, Integer
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()


class CartItem(Base):
    """購物車項目 Aggregate - SQLAlchemy ORM Model"""
    
    __tablename__ = 'cart_items'
    
    # 複合主鍵
    user_id = Column(String, primary_key=True)
    product_id = Column(String, primary_key=True)
    
    # 屬性
    quantity = Column(Integer, nullable=False)
    
    def __init__(self, user_id: str, product_id: str, quantity: int):
        self.user_id = user_id
        self.product_id = product_id
        self.quantity = quantity
```

---

## Key Patterns

**目的**: 從 Gherkin 的關係詞推斷 DBML 中的複合主鍵結構

**規則**: Gherkin 中的關係詞通常對應實體間的多對多或一對多關係，這些關係在 DBML 中會定義為複合主鍵

| 關係詞 | Gherkin 範例 | 複合 Key |
|-------|------------|---------|
| 在 | 用戶 "Alice" 在課程 1 | (user_id, lesson_id) |
| 對 | 用戶 "Alice" 對訂單 "ORDER-123" | (user_id, order_id) |
| 與 | 用戶 "Alice" 與用戶 "Bob" | (user_id_a, user_id_b) |
| 於 | 商品 "MacBook" 於商店 "台北店" | (product_id, store_id) |
| 中...在 | 訂單中商品在倉庫 | (order_id, product_id, warehouse_id) |

---

## State Mapping

**目的**: 將 Gherkin 中的中文業務術語映射到 DBML enum 值

**規則**: 
1. 查詢 DBML 中對應欄位的 `note` 定義（如: `status varchar [note: 'IN_PROGRESS, COMPLETED']`）
2. 根據語意將 Gherkin 的中文描述映射到 DBML enum 值
3. 下表僅為常見範例，實際應從 DBML 提取

| 中文範例 | Enum 範例 | 適用情境 |
|---------|----------|---------|
| 進行中 | IN_PROGRESS | 進度、狀態 |
| 已完成 | COMPLETED | 進度、狀態 |
| 未開始 | NOT_STARTED | 進度、狀態 |
| 已付款 | PAID | 訂單、付款 |
| 待付款 | PENDING | 訂單、付款 |
| 上架中 | ACTIVE | 商品、服務 |

---

## Context ID Storage

### 儲存規則

將 Aggregate 的自然鍵（natural key）儲存到 context，格式：`{natural_key}.id`

**為什麼要這樣？**
- Command/Query Handler 需要知道哪個用戶在執行操作
- 自然鍵（如 "Alice"）更易讀，但系統內部可能使用 ID
- 在 E2E 測試中，自然鍵通常就是 ID

### 範例

```python
# 單一主鍵
cart_item = CartItem(user_id="Alice", product_id="PROD-001", ...)
context["Alice.id"] = cart_item.user_id

# 複合主鍵 - 儲存所有相關的 natural keys
order_item = OrderItem(order_id="ORDER-123", product_id="PROD-001", ...)
context["ORDER-123.id"] = order_item.order_id
context["PROD-001.id"] = order_item.product_id
```

### 使用時機

在 Command-Handler 和 Query-Handler 中取用：

```python
# Command-Handler 中使用
user_id = context["Alice.id"]
token = jwt_helper.generate_token(user_id)
response = api_client.post(...)
```

---

## Complete Example

### Gherkin

```gherkin
Given 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量為 2
And 用戶 "Bob" 的購物車中商品 "PROD-002" 的數量為 1
```

### Generated Code

```python
def test_example(self, db_session, api_client, context, jwt_helper):
    # 初始化 Repository
    repository = CartRepository(db_session)
    
    # Given 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量為 2
    cart_item_alice = CartItem(
        user_id="Alice",
        product_id="PROD-001",
        quantity=2
    )
    repository.save(cart_item_alice)
    context["Alice.id"] = cart_item_alice.user_id
    
    # And 用戶 "Bob" 的購物車中商品 "PROD-002" 的數量為 1
    cart_item_bob = CartItem(
        user_id="Bob",
        product_id="PROD-002",
        quantity=1
    )
    repository.save(cart_item_bob)
    context["Bob.id"] = cart_item_bob.user_id
```

---

## SQLAlchemy Model Definition Guidelines

### 必須包含的元素

1. **繼承 Base**
   ```python
   from sqlalchemy.ext.declarative import declarative_base
   Base = declarative_base()
   
   class LessonProgress(Base):
       ...
   ```

2. **定義 `__tablename__`**
   ```python
   __tablename__ = 'cart_items'
   ```

3. **定義所有欄位（使用 Column）**
   ```python
   user_id = Column(String, primary_key=True)
   product_id = Column(String, primary_key=True)
   quantity = Column(Integer, nullable=False)
   ```

4. **定義 `__init__` 方法**
   ```python
   def __init__(self, user_id: str, product_id: str, quantity: int):
       self.user_id = user_id
       self.product_id = product_id
       self.quantity = quantity
   ```

### 從 DBML 映射到 SQLAlchemy

| DBML 型別 | SQLAlchemy Column 型別 |
|----------|----------------------|
| varchar | String |
| int | Integer |
| boolean | Boolean |
| timestamp | DateTime |
| decimal | Numeric |

---

## Critical Rules

### R1: 必須查詢 DBML
在實作 Aggregate 的時候不能憑空猜測屬性名稱和型別。必須從 DBML 讀取完整的 Aggregate 定義。

### R2: 使用 SQLAlchemy ORM
必須使用 SQLAlchemy Model，不能使用字典或普通類別。

```python
# ✅ 正確：使用 SQLAlchemy Model
cart_item = CartItem(user_id="Alice", product_id="PROD-001", quantity=2)

# ❌ 錯誤：使用字典
cart_item = {"user_id": "Alice", "product_id": "PROD-001", "quantity": 2}
```

### R3: 使用 Repository Pattern
必須透過 Repository 來操作資料庫，Repository 內部使用 SQLAlchemy Session。

```python
# ✅ 正確：使用 Repository
repository = CartRepository(db_session)
repository.save(cart_item)

# ❌ 錯誤：直接使用 Session
db_session.add(cart_item)
db_session.commit()
```

### R4: 中文狀態映射到英文 enum
```python
# ✅ status="PENDING"
# ❌ status="待處理"
```

### R5: 提供完整的複合 Key
```python
# ✅ CartItem(user_id="Alice", product_id="PROD-001", ...)
# ❌ CartItem(product_id="PROD-001", ...)
```

### R6: 儲存 ID 到 context
每個 Given 中創建的 Aggregate 都要將其 natural key 儲存到 context。

```python
# ✅ 正確：儲存到 context
context["Alice.id"] = cart_item.user_id

# ❌ 錯誤：沒有儲存
repository.save(cart_item)
```

### R7: Repository 使用 db_session fixture
Repository 必須接收 db_session 作為參數。

```python
# ✅ 正確：注入 db_session
repository = LessonProgressRepository(db_session)

# ❌ 錯誤：自己創建 session
repository = LessonProgressRepository(Session())
```

### R8: 使用 merge 而非 add
Repository.save() 應使用 `session.merge()` 而非 `session.add()`，以支援 upsert 語意。

```python
# ✅ 正確：使用 merge
def save(self, entity):
    self.session.merge(entity)
    self.session.commit()

# ❌ 錯誤：使用 add（可能重複插入失敗）
def save(self, entity):
    self.session.add(entity)
    self.session.commit()
```

### R9: 初始化 Repository 在測試開頭
在測試方法的最開始初始化 Repository，並在整個測試中重複使用同一個 Repository instance。

```python
# ✅ 正確：在開頭初始化
def test_example(self, db_session, api_client, context, jwt_helper):
    repository = CartRepository(db_session)
    
    # Given
    cart_item = CartItem(...)
    repository.save(cart_item)
    
    # When
    # ...
    
    # Then
    result = repository.find_by_user_and_product(...)

# ❌ 錯誤：每次都創建新的 Repository
def test_example(self, db_session, api_client, context, jwt_helper):
    # Given
    repository1 = CartRepository(db_session)
    repository1.save(...)
    
    # Then
    repository2 = CartRepository(db_session)  # 不必要
    repository2.find_by_user_and_product(...)
```

### R10: 測試檔案需要 import 所有相關模組
測試檔案開頭必須 import Repository 和 Model。

```python
# ✅ 正確：完整的 imports
from tests.e2e.repositories.cart_repository import CartRepository
from tests.e2e.models.cart_item import CartItem

# ❌ 錯誤：缺少 imports
# （沒有 import 就無法使用）
```

---

## File Organization

### 建議的檔案結構

```
tests/e2e/
├── conftest.py              # Fixtures 定義
├── models/                  # SQLAlchemy Models
│   ├── __init__.py
│   ├── cart_item.py
│   └── order.py
├── repositories/            # Repository 實作
│   ├── __init__.py
│   ├── cart_repository.py
│   └── order_repository.py
└── test_01_加入購物車.py  # 測試檔案
```

---
