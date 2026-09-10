# Aggregate-Then-Handler

## Trigger
Then 語句驗證**Aggregate 的屬性狀態**（從資料庫查詢）

**識別規則**：
- 驗證實體的屬性值（而非 API 回傳值）
- 描述「某個東西的某個屬性應該是某個值」
- 常見句型（非窮舉）：「在...的...應為」「的...應為」「應包含」

**通用判斷**：如果 Then 是驗證 Command 操作後的資料狀態（需要從資料庫查詢），就使用此 Handler

## Task
使用 Repository 從資料庫查詢 Aggregate → Assert 屬性值

## E2E 特色
- 使用 SQLAlchemy Repository 從真實 PostgreSQL 查詢
- 根據 Gherkin 明確提到的欄位進行查詢
- 驗證 Aggregate 的狀態（而非 API response）

---

## Steps

1. 識別 Aggregate 名稱
2. 從 Gherkin 提取查詢條件（通常是複合主鍵）
3. 使用 Repository 查詢 Aggregate
4. Assert Aggregate 的屬性值

---

## Pattern Examples (Python)

### 驗證單一 Aggregate

```gherkin
And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2
```

```python
# 1. 使用 Repository 查詢 Aggregate
cart_item = repository.find_by_user_and_product(
    user_id="Alice",
    product_id="PROD-001"
)

# 2. Assert 屬性值
assert cart_item.quantity == 2
```

### 驗證多個屬性

```gherkin
And 訂單 "ORDER-123" 的狀態應為 "已付款"，金額應為 1000
```

```python
order = repository.find_by_id(order_id="ORDER-123")

assert order.status == "PAID"  # 中文 → 英文 enum
assert order.total_amount == 1000
```

### 驗證 Aggregate 存在

```gherkin
And 訂單 "ORDER-123" 應存在
```

```python
order = repository.find_by_id(order_id="ORDER-123")
assert order is not None
```

### 驗證 Aggregate 不存在

```gherkin
And 購物車中應不存在商品 "PROD-001"
```

```python
cart_item = repository.find_by_product(product_id="PROD-001")
assert cart_item is None
```

---

## Query Strategy

### 根據 Gherkin 明確提到的欄位查詢

**規則**：只使用 Gherkin 中明確提到的欄位來查詢 Aggregate

**範例 1：複合主鍵查詢**

```gherkin
And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2
```

從 Gherkin 提取：
- 用戶: "Alice" → user_id="Alice"
- 商品: "PROD-001" → product_id="PROD-001"

查詢方法：
```python
repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")
```

**範例 2：單一主鍵查詢**

```gherkin
And 訂單 "ORDER-123" 的狀態應為 "已付款"
```

從 Gherkin 提取：
- 訂單: "ORDER-123" → order_id="ORDER-123"

查詢方法：
```python
repository.find_by_id(order_id="ORDER-123")
```

---

## Repository Query Methods

### 命名規則

Repository 的查詢方法命名應該清晰表達查詢條件：

| Gherkin 查詢條件 | Repository 方法 |
|----------------|----------------|
| 用戶 "Alice" 的購物車中商品 "PROD-001" | find_by_user_and_product(user_id, product_id) |
| 訂單 "ORDER-123" | find_by_id(order_id) |
| 商品 "PROD-001" | find_by_product_id(product_id) |
| 用戶 "Alice" 的所有訂單 | find_all_by_user(user_id) |

### Repository 實作範例

```python
from typing import Optional, List
from sqlalchemy.orm import Session
from tests.e2e.models.cart_item import CartItem


class CartRepository:
    """購物車 Repository"""
    
    def __init__(self, session: Session):
        self.session = session
    
    def save(self, cart_item: CartItem) -> None:
        """保存購物車項目"""
        self.session.merge(cart_item)
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
    
    def find_all_by_user(self, user_id: str) -> List[CartItem]:
        """查詢用戶的所有購物車項目"""
        return self.session.query(CartItem).filter_by(
            user_id=user_id
        ).all()
```

---

## State Mapping

**目的**: 將 Gherkin 中的中文業務術語映射到 DBML enum 值

| 中文範例 | Enum 範例 | 適用情境 |
|---------|----------|---------|
| 進行中 | IN_PROGRESS | 進度、狀態 |
| 已完成 | COMPLETED | 進度、狀態 |
| 未開始 | NOT_STARTED | 進度、狀態 |
| 已交付 | DELIVERED | 課程狀態 |
| 已付款 | PAID | 訂單、付款 |
| 待付款 | PENDING | 訂單、付款 |

```python
# ✅ 正確：使用英文 enum
assert updated_progress.status == "IN_PROGRESS"

# ❌ 錯誤：使用中文
assert updated_progress.status == "進行中"
```

---

## Complete Example

### Gherkin

```gherkin
Example: 成功將商品加入購物車
  Given 用戶 "Alice" 的購物車為空
  When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
  Then 操作成功
  And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2
```

### Generated Code

```python
def test_成功將商品加入購物車(self, db_session, api_client, context, jwt_helper):
    # Arrange
    repository = CartRepository(db_session)
    
    # Given 用戶 "Alice" 的購物車為空
    # （無需額外操作，初始狀態即為空）
    context["Alice.id"] = "Alice"
    
    # When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
    user_id = context.get("Alice.id")
    token = jwt_helper.generate_token(user_id)
    
    response = api_client.post(
        "/api/cart/items",
        headers={"Authorization": f"Bearer {token}"},
        json={"productId": "PROD-001", "quantity": 2}
    )
    context["last_response"] = response
    
    # Then 操作成功
    assert response.status_code in [200, 201, 204]
    
    # And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2
    cart_item = repository.find_by_user_and_product(
        user_id="Alice",
        product_id="PROD-001"
    )
    assert cart_item.quantity == 2
```

---

## Critical Rules

### R1: 使用 Repository 查詢
必須使用 Repository 的查詢方法，不直接使用 Session。

```python
# ✅ 正確：使用 Repository
updated_cart_item = repository.find_by_user_and_product(
    user_id="Alice",
    product_id="PROD-001"
)

# ❌ 錯誤：直接使用 Session
updated_cart_item = db_session.query(CartItem).filter_by(...).first()
```

### R2: 只驗證 Gherkin 提到的欄位
只 assert Gherkin 中明確提到的屬性。

```python
# Gherkin: And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2

# ✅ 正確：只驗證 quantity
assert cart_item.quantity == 2

# ❌ 錯誤：驗證額外的欄位
assert cart_item.quantity == 2
assert cart_item.updated_at is not None  # Gherkin 沒提到
```

### R3: 中文狀態映射到英文 enum
```python
# ✅ assert order.status == "PAID"
# ❌ assert order.status == "已付款"
```

### R4: 使用完整的查詢條件
根據 Gherkin 提到的所有條件進行查詢。

```python
# Gherkin: And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2

# ✅ 正確：使用完整的查詢條件
repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")

# ❌ 錯誤：缺少查詢條件
repository.find_by_product(product_id="PROD-001")  # 沒有指定用戶
```

### R5: 驗證 Aggregate 存在性
如果 Gherkin 要求驗證存在或不存在，要明確檢查。

```python
# Gherkin: And 訂單 "ORDER-123" 應存在

# ✅ 正確：檢查不為 None
order = repository.find_by_id(order_id="ORDER-123")
assert order is not None

# ❌ 錯誤：沒有檢查存在性
order = repository.find_by_id(order_id="ORDER-123")
assert order.status == "PAID"  # 如果 order 是 None 會報錯
```

### R6: 使用同一個 Repository 實例
在整個測試中使用同一個 Repository 實例（在測試開頭初始化）。

```python
# ✅ 正確：在開頭初始化，重複使用
def test_example(self, db_session, api_client, context, jwt_helper):
    repository = CartRepository(db_session)
    
    # Given
    repository.save(...)
    
    # Then
    result = repository.find_by_user_and_product(...)

# ❌ 錯誤：每次都創建新的 Repository
def test_example(self, db_session, api_client, context, jwt_helper):
    repository1 = CartRepository(db_session)
    repository1.save(...)
    
    repository2 = CartRepository(db_session)  # 不必要
    result = repository2.find_by_user_and_product(...)
```

### R7: Aggregate 可能為 None
如果查詢的 Aggregate 可能不存在，要先檢查是否為 None。

```python
# Gherkin: And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2

# ✅ 正確：先檢查存在性
cart_item = repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")
assert cart_item is not None, "找不到購物車項目"
assert cart_item.quantity == 2

# ⚠️ 也可以（假設一定存在）
cart_item = repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")
assert cart_item.quantity == 2  # 如果 cart_item 是 None 會報錯 AttributeError
```

### R8: 從資料庫查詢，不使用 API response
Aggregate-Then-Handler 驗證的是資料庫狀態，不是 API response。

```python
# ✅ 正確：從資料庫查詢
cart_item = repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")
assert cart_item.quantity == 2

# ❌ 錯誤：使用 API response
response = context["last_response"]
data = response.json()
assert data["quantity"] == 2  # 這是 ReadModel-Then-Handler 的工作
```

### R9: 查詢方法命名清晰
Repository 的查詢方法命名應該清晰表達查詢條件。

```python
# ✅ 正確：清晰的方法名
repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")

# ❌ 錯誤：不清晰的方法名
repository.find(user_id="Alice", product_id="PROD-001")
repository.get("Alice", "PROD-001")
```

### R10: 可以合併多個 And 的驗證
如果多個 And 驗證同一個 Aggregate 的不同屬性，可以只查詢一次。

```gherkin
And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2
And 用戶 "Alice" 的購物車中商品 "PROD-002" 的數量應為 1
```

```python
# ✅ 正確：查詢兩次不同的商品
cart_item_1 = repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")
assert cart_item_1.quantity == 2

cart_item_2 = repository.find_by_user_and_product(user_id="Alice", product_id="PROD-002")
assert cart_item_2.quantity == 1

# 或如果是同一個實體的多個屬性：
# ✅ 正確：查詢一次，驗證多個屬性
cart_item = repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")
assert cart_item.quantity == 2

# 但這個例子是不同商品，需要分別查詢
```

---

## 與 ReadModel-Then-Handler 的區別

| 面向 | Aggregate-Then-Handler | ReadModel-Then-Handler |
|------|-------------------|----------------------|
| 驗證對象 | 資料庫中的 Aggregate | API response 的內容 |
| 資料來源 | SQLAlchemy Repository | context["last_response"] |
| 使用時機 | Command 操作後驗證狀態 | Query 操作後驗證回傳值 |
| 範例 | And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2 | And 查詢結果應包含數量 2 |

---

## 驗證列表（List）

如果 Aggregate 是列表（如「用戶的所有訂單」），使用 `find_all_*` 方法。

```gherkin
And 用戶 "Alice" 應有 2 個購物車項目
```

```python
cart_items = repository.find_all_by_user(user_id="Alice")
assert len(cart_items) == 2
```

```gherkin
And 用戶 "Alice" 的第一個購物車項目的商品 ID 應為 "PROD-001"
```

```python
cart_items = repository.find_all_by_user(user_id="Alice")
assert len(cart_items) > 0
assert cart_items[0].product_id == "PROD-001"
```

---
