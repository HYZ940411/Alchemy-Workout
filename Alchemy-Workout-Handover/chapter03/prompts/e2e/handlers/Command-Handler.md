# Command-Handler

## Trigger
Given/When 語句執行**寫入操作**（Command）

**識別規則**:
- 動作會修改系統狀態
- 描述「執行某個動作」或「已完成某個動作」
- Given 常見過去式（非窮舉）:「已訂閱」「已完成」「已建立」「已添加」「已註冊」
- When 常見現在式（非窮舉）:「更新」「提交」「建立」「刪除」「添加」「移除」

**通用判斷**: 如果語句是修改系統狀態的操作且不需要回傳值，就使用此 Handler

## Task
調用 HTTP POST/PUT/PATCH/DELETE API

## Key Difference
- **Command**: 修改狀態，調用 HTTP POST/PUT/PATCH/DELETE，不驗證 response
- **Query**: 讀取資料，調用 HTTP GET，需要驗證 response

## E2E 特色
- 從 context 取得 user ID
- 使用 jwt_helper 生成 JWT token
- 從 api.yml 讀取 API endpoint 定義
- 使用 requests 打真實的 HTTP API
- 將 response 存入 context 供 Then 驗證

---

## 實作流程

Command Handler 的任務是**透過 HTTP API 執行修改系統狀態的操作**。

### 步驟

1. **從 context 取得用戶 ID**
2. **使用 jwt_helper 生成 JWT Token**
3. **參考 api.yml 構建 Request Body**
4. **執行 HTTP POST/PUT/DELETE 請求**（使用 api_client）
5. **儲存 response 到 context**（不驗證，交給 Then）

---

## 關鍵概念

### 1. 從 Context 取得 ID

**識別 Actor 參數**：
- 智能判斷 Gherkin 步驟中的 actor 參數（通常是第一個 `{string}` 參數）
- 在此專案中，actor 通常是用戶名稱（如 "Alice"、"Bob"）
- 根據參數的語意命名來判斷（如 userName、userId、customerName 等）

**取得 ID**：
```python
# 識別 actor 參數（範例：userName, userId, customerName 等）
user_id = context.get("Alice.id")

if user_id is None:
    raise ValueError(f"找不到用戶 ID: Alice")
```

**通用模式**：`context.get("{actor}.id")`

### 2. 產生 JWT Token

```python
# 產生 Token（將 user_id 放入 sub claim）
token = jwt_helper.generate_token(user_id)
```

### 3. 參考 api.yml 構建 Request Body

**重要**：根據 `api.yml` 中對應 API Endpoint 的 `requestBody` 定義來構建

**步驟**：
1. 在 `api.yml` 中找到對應的 API Endpoint
2. 查看 `requestBody.content.application/json.schema.properties`
3. 根據定義的欄位名稱和類型構建 Request Body

**使用 dict**：
```python
request_body = {
    "lessonId": 1,        # 對應 api.yml 中的欄位（camelCase）
    "progress": 80        # 對應 api.yml 中的欄位
}
```

**欄位命名**：使用 **camelCase**，與 api.yml 中定義的欄位名稱完全一致

### 4. 執行 HTTP POST 請求

**重要**：根據 `api.yml` 中的 API Endpoint 定義來決定如何呼叫

**步驟**：
1. 在 `api.yml` 中找到對應的 API Endpoint 路徑（在 `paths` 下）
2. 確認 HTTP Method（通常是 `post`、`put`、`delete`）
3. 確認是否需要 Path Variable（路徑中的 `{variable}`）
4. 確認是否需要 Query Parameter（`parameters.in: query`）
5. 確認是否需要認證（`security: bearerAuth`）

**基本模式**：
```python
# 無 Path Variable
response = api_client.post(
    "/api/lesson-progress/update-video-progress",
    headers={"Authorization": f"Bearer {token}"},
    json=request_body
)

# 有 Path Variable
response = api_client.post(
    f"/api/orders/{order_id}/cancel",
    headers={"Authorization": f"Bearer {token}"},
    json=request_body
)
```

### 5. 儲存 response 到 context

```python
context["last_response"] = response
```

**重要**：不驗證 Response（不使用 `assert`），由 Then 步驟處理

---

## Pattern Examples (Python)

### Given + Command (已完成的動作)

```gherkin
Given 用戶 "Alice" 已註冊，email 為 "alice@test.com"，密碼為 "Password123"
```

```python
# 參考 api.yml 找到註冊 API
# POST /api/auth/register
# requestBody: { email: string, password: string, name: string }

response = api_client.post(
    "/api/auth/register",
    json={
        "email": "alice@test.com",
        "password": "Password123",
        "name": "Alice"
    }
)
context["last_response"] = response

# 從 response 中取得 user_id 並存入 context（如果 API 有回傳）
if response.status_code == 200:
    data = response.json()
    context["Alice.id"] = data.get("user", {}).get("id", "Alice")
```

### When + Command (現在執行的動作)

```gherkin
When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
```

```python
# 1. 從 context 取得 user_id
user_id = context.get("Alice.id")
if user_id is None:
    raise ValueError("找不到用戶 ID: Alice")

# 2. 產生 Token
token = jwt_helper.generate_token(user_id)

# 3. 參考 api.yml 構建 Request Body
# POST /api/cart/items
# requestBody: { productId: string, quantity: integer }
request_body = {
    "productId": "PROD-001",
    "quantity": 2
}

# 4. 執行 HTTP 請求
response = api_client.post(
    "/api/cart/items",
    headers={"Authorization": f"Bearer {token}"},
    json=request_body
)

# 5. 儲存結果
context["last_response"] = response
```

### 多參數 Command

```gherkin
When 用戶 "Alice" 建立訂單，配送地址為 "台北市信義區"，付款方式為 "信用卡"
```

```python
user_id = context.get("Alice.id")
token = jwt_helper.generate_token(user_id)

# 參考 api.yml
# POST /api/orders/create
# requestBody: { shippingAddress: string, paymentMethod: string }
request_body = {
    "shippingAddress": "台北市信義區",
    "paymentMethod": "信用卡"
}

response = api_client.post(
    "/api/orders/create",
    headers={"Authorization": f"Bearer {token}"},
    json=request_body
)

context["last_response"] = response
```

### 有 Path Variable 的 Command

```gherkin
When 用戶 "Alice" 取消訂單 "ORDER-123"
```

```python
user_id = context.get("Alice.id")
token = jwt_helper.generate_token(user_id)

# 參考 api.yml
# DELETE /api/orders/{orderId}
order_id = "ORDER-123"

response = api_client.delete(
    f"/api/orders/{order_id}",
    headers={"Authorization": f"Bearer {token}"}
)

context["last_response"] = response
```

---

## API Spec Reference Strategy

### 如何從 api.yml 找到對應的 API

1. **識別動作關鍵字**：從 Gherkin 的動詞（更新、提交、建立、刪除）判斷
2. **識別目標物件**：從 Gherkin 的名詞（課程進度、作業、訂單）判斷
3. **在 api.yml 中搜尋**：
   - 搜尋 `paths` 下的路徑
   - 搜尋 `summary` 欄位（通常包含中文描述）
   - 確認 HTTP method（通常 Command 是 POST/PUT/DELETE）

### 範例：從 Gherkin 到 api.yml

**Gherkin**：
```gherkin
When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
```

**在 api.yml 中搜尋**：
1. 搜尋關鍵字「加入」「購物車」
2. 找到對應的 endpoint：

```yaml
/cart/items:
  post:
    summary: 用戶 {string} 將商品 {string} 加入購物車，數量為 {int}
    security:
      - bearerAuth: []
    requestBody:
      required: true
      content:
        application/json:
          schema:
            properties:
              productId:
                type: string
              quantity:
                type: integer
```

**生成程式碼**：
```python
response = api_client.post(
    "/api/cart/items",
    headers={"Authorization": f"Bearer {token}"},
    json={
        "productId": "PROD-001",  # 從 api.yml 得知欄位名稱是 productId（camelCase）
        "quantity": 2             # 從 api.yml 得知欄位名稱是 quantity
    }
)
```

---

## Method Naming & Parameter Extraction

### 從 Gherkin 提取參數

**規則**: 從 Gherkin 的名詞片段和數值推斷參數名稱和值

**推斷原則**:
- 實體名詞 → {entity}_id
- 屬性 → {attribute}
- 字串用引號，數字不用引號
- **最終欄位命名以 api.yml 為準**

| Gherkin 片段範例 | 參數範例 | api.yml 欄位 |
|----------------|---------|------------|
| 用戶 "Alice" | user_id="Alice" | 通常不在 body，從 token 取得 |
| 商品 "PROD-001" | product_id="PROD-001" | productId: "PROD-001" |
| 數量為 2 | quantity=2 | quantity: 2 |
| 配送地址為 "台北市" | address="台北市" | shippingAddress: "台北市" |

---

## Given vs When Command

### 差異說明

**Given + Command (已完成的動作)**:
- 用於建立測試前置條件
- 描述過去已經發生的動作
- 常用過去式：「已訂閱」「已完成」「已建立」「已註冊」

**When + Command (現在執行的動作)**:
- 用於執行被測試的動作
- 描述現在要執行的動作
- 常用現在式：「更新」「提交」「建立」

### 範例對比

```gherkin
# Given: 建立前置條件
Given 用戶 "Alice" 已註冊

# When: 執行被測試動作
When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
```

```python
# Given: 調用 API 建立前置條件
response = api_client.post("/api/auth/register", json={...})
context["last_response"] = response
if response.status_code == 200:
    context["Alice.id"] = response.json()["user"]["id"]

# When: 調用 API 執行被測試動作
user_id = context["Alice.id"]
token = jwt_helper.generate_token(user_id)
response = api_client.post(
    "/api/cart/items",
    headers={"Authorization": f"Bearer {token}"},
    json={...}
)
context["last_response"] = response
```

**關鍵**: Given 和 When 的 Command 在程式碼層面類似，都是調用 HTTP API，但 Given 可能需要從 response 中提取 ID

---

## Complete Example

### Gherkin

```gherkin
Feature: 購物車管理

Background:
  Given 用戶 "Alice" 已註冊，email 為 "alice@test.com"，密碼為 "Password123"

Example: 成功將商品加入購物車
  Given 用戶 "Alice" 的購物車為空
  When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
  Then 操作成功
  And 用戶 "Alice" 的購物車應包含商品 "PROD-001"，數量為 2
```

### Generated Code

```python
import pytest
from tests.e2e.repositories.cart_repository import CartRepository
from tests.e2e.models.cart_item import CartItem


@pytest.fixture(scope="module", autouse=True)
def feature_background(api_client, context):
    """Feature-level Background"""
    # Given 用戶 "Alice" 已註冊
    response = api_client.post(
        "/api/auth/register",
        json={
            "email": "alice@test.com",
            "password": "Password123",
            "name": "Alice"
        }
    )
    context["last_response"] = response
    
    if response.status_code == 200:
        data = response.json()
        context["Alice.id"] = data.get("user", {}).get("id", "Alice")


class Test將商品加入購物車:
    """測試購物車管理"""
    
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
            json={
                "productId": "PROD-001",
                "quantity": 2
            }
        )
        context["last_response"] = response
        
        # Then 操作成功
        assert response.status_code in [200, 201, 204]
        
        # And 用戶 "Alice" 的購物車應包含商品 "PROD-001"，數量為 2
        cart_item = repository.find_by_user_and_product(
            user_id="Alice", 
            product_id="PROD-001"
        )
        assert cart_item.quantity == 2
```

---

## Critical Rules

### R1: Command 不驗證 Response
在 Command Handler 中只執行請求，不驗證 response（除非是從 response 提取 ID）。

```python
# ✅ 正確：不驗證，只儲存
response = api_client.post(...)
context["last_response"] = response

# ❌ 錯誤：在 Command 中驗證
response = api_client.post(...)
assert response.status_code == 200  # 應該在 Then 中驗證
```

### R2: 參數名稱使用 camelCase（以 api.yml 為準）
Request body 的欄位名稱必須與 api.yml 完全一致，通常是 camelCase。

```python
# ✅ 正確：使用 camelCase（參考 api.yml）
json={"productId": "PROD-001", "quantity": 2}

# ❌ 錯誤：使用 snake_case
json={"product_id": "PROD-001", "quantity": 2}
```

### R3: 必須從 context 取得 user_id
Command 需要認證時，必須從 context 取得 user_id。

```python
# ✅ 正確：從 context 取得
user_id = context.get("Alice.id")
token = jwt_helper.generate_token(user_id)

# ❌ 錯誤：寫死 user_id
token = jwt_helper.generate_token("Alice")
```

### R4: 必須產生 JWT Token（如果 API 需要認證）
如果 api.yml 中的 endpoint 有 `security: bearerAuth`，必須產生 token。

```python
# ✅ 正確：產生 token 並放在 header
token = jwt_helper.generate_token(user_id)
response = api_client.post(
    "/api/...",
    headers={"Authorization": f"Bearer {token}"},
    json={...}
)

# ❌ 錯誤：沒有 token
response = api_client.post("/api/...", json={...})
```

### R5: 必須儲存 response 到 context
每個 Command 執行後都要儲存 response 到 context。

```python
# ✅ 正確：儲存 response
context["last_response"] = response

# ❌ 錯誤：沒有儲存
response = api_client.post(...)
# 沒有存入 context，Then 無法驗證
```

### R6: Given + Command 可能需要從 response 提取 ID
當 Given 是「已註冊」等動作時，可能需要從 API response 中提取 user ID。

```python
# ✅ 正確：從 response 提取並存入 context
response = api_client.post("/api/auth/register", json={...})
if response.status_code == 200:
    data = response.json()
    context["Alice.id"] = data.get("user", {}).get("id")

# ❌ 錯誤：沒有提取 ID，後續步驟會失敗
response = api_client.post("/api/auth/register", json={...})
context["last_response"] = response
```

### R7: 必須參考 api.yml 構建 Request
不能憑空猜測 API 的路徑和參數，必須參考 api.yml。

```python
# ✅ 正確：參考 api.yml
# 在 api.yml 找到：POST /api/cart/items
response = api_client.post(
    "/api/cart/items",
    json={"productId": "PROD-001", "quantity": 2}
)

# ❌ 錯誤：自己猜測 API 路徑
response = api_client.post(
    "/api/add-to-cart",  # 路徑錯誤
    json={"product": "PROD-001", "amount": 2}  # 欄位錯誤
)
```

### R8: 使用 api_client fixture
必須使用注入的 api_client fixture，不自己創建 requests.Session。

```python
# ✅ 正確：使用 fixture
def test_example(self, api_client, jwt_helper, context):
    response = api_client.post(...)

# ❌ 錯誤：自己創建 session
def test_example(self):
    session = requests.Session()
    response = session.post(...)
```

### R9: 檢查 user_id 是否存在
在從 context 取得 user_id 後，應檢查是否為 None。

```python
# ✅ 正確：檢查是否存在
user_id = context.get("Alice.id")
if user_id is None:
    raise ValueError("找不到用戶 ID: Alice")
token = jwt_helper.generate_token(user_id)

# ⚠️ 也可以（簡化版）
user_id = context["Alice.id"]  # 如果不存在會直接報錯 KeyError
```

### R10: HTTP Method 選擇
根據 api.yml 的定義選擇正確的 HTTP method。

```python
# ✅ 正確：根據 api.yml
# api.yml: POST /api/cart/items
response = api_client.post("/api/cart/items", ...)

# ❌ 錯誤：使用錯誤的 method
response = api_client.get("/api/cart/items", ...)
```

---

## 不需要認證的 API

有些 API 不需要認證（如註冊、登入），在 api.yml 中沒有 `security: bearerAuth`。

```gherkin
Given 用戶 "Alice" 已註冊，email 為 "alice@test.com"
```

```python
# 不需要 token
response = api_client.post(
    "/api/auth/register",
    json={
        "email": "alice@test.com",
        "password": "Password123",
        "name": "Alice"
    }
)
context["last_response"] = response

# 從 response 提取 user_id
if response.status_code == 200:
    data = response.json()
    context["Alice.id"] = data.get("user", {}).get("id", "Alice")
```

---
