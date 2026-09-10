# Query-Handler

## Trigger
When 語句執行**讀取操作**（Query）

**識別規則**:
- 動作不修改系統狀態，只讀取資料
- 描述「取得某些資訊」的動作
- 常見動詞（非窮舉）:「查詢」「取得」「列出」「檢視」「獲取」

**通用判斷**: 如果 When 是讀取操作且需要回傳值供 Then 驗證，就使用此 Handler

## Task
調用 HTTP GET API，將 response 存入 context

## Key Difference
- **Command**: 修改狀態，調用 HTTP POST/PUT/DELETE，不驗證 response
- **Query**: 讀取資料，調用 HTTP GET，需要驗證 response

## E2E 特色
- 從 context 取得 user ID
- 使用 jwt_helper 生成 JWT token
- 從 api.yml 讀取 API endpoint 定義
- 使用 requests 打真實的 HTTP GET API
- 將 response 存入 context 供 Then 驗證

---

## 實作流程

Query Handler 的任務是**透過 HTTP API 讀取資料**。

### 步驟

1. **從 context 取得用戶 ID**
2. **使用 jwt_helper 生成 JWT Token**
3. **參考 api.yml 構建 URL（含 path/query parameters）**
4. **執行 HTTP GET 請求**（使用 api_client）
5. **儲存 response 到 context**（供 ReadModel-Then-Handler 驗證）

---

## 關鍵概念

### 1. 從 Context 取得 ID

```python
# 識別 actor 參數
user_id = context.get("Alice.id")

if user_id is None:
    raise ValueError(f"找不到用戶 ID: Alice")
```

### 2. 產生 JWT Token

```python
# 產生 Token
token = jwt_helper.generate_token(user_id)
```

### 3. 構建 URL

**Path Parameters**：
- 在 URL 路徑中直接替換參數

```python
# api.yml: /lessons/{lessonId}/progress
lesson_id = 1
url = f"/api/lessons/{lesson_id}/progress"
```

**Query Parameters**：
- 使用 `params` 參數傳遞

```python
# api.yml: /journeys/{journeyId}/lessons?chapterId={int}
journey_id = 1
chapter_id = 2
url = f"/api/journeys/{journey_id}/lessons"
params = {"chapterId": chapter_id}
response = api_client.get(url, params=params, headers={...})
```

### 4. 執行 HTTP GET 請求

```python
response = api_client.get(
    url,
    headers={"Authorization": f"Bearer {token}"},
    params=params  # 如果有 query parameters
)
```

### 5. 儲存 response 到 context

```python
context["last_response"] = response
```

**重要**：不在 Query Handler 中驗證 response 內容，由 ReadModel-Then-Handler 處理

---

## Method Naming

**規則**:
- 單一記錄: `get_{entity}` 或 `get_{entity}_{aspect}`
- 列表: `list_{entities}` (複數形式)

| Gherkin 動作範例 | API Path 範例 |
|----------------|--------------|
| 查詢...詳情 | GET /orders/{orderId} |
| 取得...資訊 | GET /products/{productId} |
| 列出...列表 | GET /cart/items |
| 查詢...狀態 | GET /orders/{orderId}/status |

---

## Pattern Examples (Python)

### Query 單一記錄

```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
```

```python
# 1. 從 context 取得 user_id
user_id = context.get("Alice.id")
if user_id is None:
    raise ValueError("找不到用戶 ID: Alice")

# 2. 產生 Token
token = jwt_helper.generate_token(user_id)

# 3. 參考 api.yml 構建 URL
# GET /orders/{orderId}
order_id = "ORDER-123"
url = f"/api/orders/{order_id}"

# 4. 執行 HTTP GET 請求
response = api_client.get(
    url,
    headers={"Authorization": f"Bearer {token}"}
)

# 5. 儲存結果
context["last_response"] = response
```

### Query 列表（無 Query Parameters）

```gherkin
When 用戶 "Alice" 查詢購物車中的所有商品
```

```python
user_id = context.get("Alice.id")
token = jwt_helper.generate_token(user_id)

# GET /cart/items
url = f"/api/cart/items"

response = api_client.get(
    url,
    headers={"Authorization": f"Bearer {token}"}
)

context["last_response"] = response
```

### Query 列表（有 Query Parameters）

```gherkin
When 用戶 "Alice" 查詢類別為 "電子產品" 的商品列表
```

```python
user_id = context.get("Alice.id")
token = jwt_helper.generate_token(user_id)

# GET /products?category={string}
url = f"/api/products"
params = {"category": "電子產品"}

response = api_client.get(
    url,
    headers={"Authorization": f"Bearer {token}"},
    params=params
)

context["last_response"] = response
```

---

## API Spec Reference Strategy

### 如何從 api.yml 找到對應的 API

1. **識別動作關鍵字**：從 Gherkin 的動詞（查詢、取得、列出）判斷
2. **識別目標物件**：從 Gherkin 的名詞（課程進度、課程清單、訂單詳情）判斷
3. **在 api.yml 中搜尋**：
   - 搜尋 `paths` 下的路徑
   - 搜尋 `summary` 欄位（通常包含中文描述）
   - 確認 HTTP method 是 GET

### 範例：從 Gherkin 到 api.yml

**Gherkin**：
```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
```

**在 api.yml 中搜尋**：
1. 搜尋關鍵字「查詢」「訂單」「詳情」
2. 找到對應的 endpoint：

```yaml
/orders/{orderId}:
  get:
    summary: 用戶 {string} 查詢訂單 {string} 的詳情
    security:
      - bearerAuth: []
    parameters:
      - name: orderId
        in: path
        required: true
        schema:
          type: string
    responses:
      '200':
        content:
          application/json:
            schema:
              properties:
                orderId:
                  type: string
                userId:
                  type: string
                status:
                  type: string
                totalAmount:
                  type: number
```

**生成程式碼**：
```python
user_id = context.get("Alice.id")
token = jwt_helper.generate_token(user_id)

# Path parameter: orderId
order_id = "ORDER-123"
url = f"/api/orders/{order_id}"

response = api_client.get(
    url,
    headers={"Authorization": f"Bearer {token}"}
)

context["last_response"] = response
```

---

## Parameter Extraction

### Path Parameters

從 Gherkin 提取數值，替換到 URL 路徑中：

| Gherkin 片段範例 | Path Parameter | URL 範例 |
|----------------|---------------|---------|
| 訂單 "ORDER-123" | orderId="ORDER-123" | /orders/ORDER-123 |
| 商品 "PROD-001" | productId="PROD-001" | /products/PROD-001 |
| 用戶 "Alice" | userId="Alice" | /users/Alice |

### Query Parameters

從 Gherkin 提取選填參數，放在 `params` dict 中：

| Gherkin 片段範例 | Query Parameter | params 範例 |
|----------------|----------------|------------|
| 類別為 "電子產品" | category="電子產品" | {"category": "電子產品"} |
| 狀態為 "已付款" | status="PAID" | {"status": "PAID"} |
| 頁碼 1，每頁 10 筆 | page=1, pageSize=10 | {"page": 1, "pageSize": 10} |

---

## Complete Example

### Gherkin

```gherkin
Feature: 查詢訂單詳情

Background:
  Given 用戶 "Alice" 已註冊

Example: 查詢訂單詳情
  Given 訂單 "ORDER-123" 的狀態為 "已付款"，金額為 1000
  When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
  Then 操作成功
  And 查詢結果應包含訂單 ID 為 "ORDER-123"，狀態為 "已付款"，金額為 1000
```

### Generated Code

```python
import pytest
from tests.e2e.repositories.order_repository import OrderRepository
from tests.e2e.models.order import Order


class Test查詢訂單詳情:
    """測試查詢訂單詳情"""
    
    def test_查詢訂單詳情(self, db_session, api_client, context, jwt_helper):
        # Arrange
        repository = OrderRepository(db_session)
        
        # Given 訂單 "ORDER-123" 的狀態為 "已付款"，金額為 1000
        order = Order(
            order_id="ORDER-123",
            user_id="Alice",
            status="PAID",
            total_amount=1000
        )
        repository.save(order)
        context["Alice.id"] = order.user_id
        
        # When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
        user_id = context.get("Alice.id")
        token = jwt_helper.generate_token(user_id)
        
        order_id = "ORDER-123"
        url = f"/api/orders/{order_id}"
        
        response = api_client.get(
            url,
            headers={"Authorization": f"Bearer {token}"}
        )
        context["last_response"] = response
        
        # Then 操作成功
        assert response.status_code == 200
        
        # And 查詢結果應包含訂單 ID 為 "ORDER-123"，狀態為 "已付款"，金額為 1000
        data = response.json()
        assert data["orderId"] == "ORDER-123"
        assert data["status"] == "已付款"
        assert data["totalAmount"] == 1000
```

---

## Critical Rules

### R1: Query 必須儲存 response 到 context
Query 的 response 會在 ReadModel-Then-Handler 中被使用。

```python
# ✅ 正確：儲存 response
response = api_client.get(...)
context["last_response"] = response

# ❌ 錯誤：沒有儲存
response = api_client.get(...)
# 沒有存入 context，ReadModel-Then-Handler 無法驗證
```

### R2: 使用 HTTP GET method
Query 操作必須使用 GET method。

```python
# ✅ 正確：使用 GET
response = api_client.get(url, ...)

# ❌ 錯誤：使用 POST
response = api_client.post(url, ...)
```

### R3: 參數名稱清晰
Path parameters 和 query parameters 必須清晰且符合 api.yml 定義。

```python
# ✅ 正確：使用正確的參數名稱（參考 api.yml）
url = f"/api/orders/{order_id}"
params = {"category": "電子產品"}

# ❌ 錯誤：使用錯誤的參數名稱
url = f"/api/orders/{id}"  # 變數名不清晰
params = {"cat": "電子產品"}  # 參數名錯誤
```

### R4: 必須從 context 取得 user_id
Query 需要認證時，必須從 context 取得 user_id。

```python
# ✅ 正確：從 context 取得
user_id = context.get("Alice.id")
token = jwt_helper.generate_token(user_id)

# ❌ 錯誤：寫死 user_id
token = jwt_helper.generate_token("Alice")
```

### R5: 必須產生 JWT Token（如果 API 需要認證）
如果 api.yml 中的 endpoint 有 `security: bearerAuth`，必須產生 token。

```python
# ✅ 正確：產生 token 並放在 header
token = jwt_helper.generate_token(user_id)
response = api_client.get(
    url,
    headers={"Authorization": f"Bearer {token}"}
)

# ❌ 錯誤：沒有 token
response = api_client.get(url)
```

### R6: 不在 Query Handler 中驗證 response 內容
Query Handler 只負責執行請求並儲存，不驗證 response 的內容。

```python
# ✅ 正確：不驗證內容
response = api_client.get(...)
context["last_response"] = response

# ❌ 錯誤：在 Query Handler 中驗證
response = api_client.get(...)
data = response.json()
assert data["progress"] == 80  # 應該在 ReadModel-Then-Handler 中驗證
```

### R7: 可以驗證 status code（Success-Failure-Handler 會做）
Query 的 status code 驗證交給 Success-Failure-Handler。

```python
# ✅ 正確：不在 Query Handler 中驗證 status code
response = api_client.get(...)
context["last_response"] = response

# 在 Success-Failure-Handler 中驗證：
# assert response.status_code == 200
```

### R8: Query Parameters 使用 params 參數
如果有 query parameters，使用 `params` 參數傳遞。

```python
# ✅ 正確：使用 params 參數
response = api_client.get(
    "/api/journeys/1/lessons",
    params={"chapterId": 2},
    headers={...}
)

# ❌ 錯誤：手動拼接 URL
response = api_client.get(
    "/api/journeys/1/lessons?chapterId=2",
    headers={...}
)
```

### R9: Path Parameters 使用 f-string
Path parameters 應該使用 f-string 嵌入 URL。

```python
# ✅ 正確：使用 f-string
lesson_id = 1
url = f"/api/lessons/{lesson_id}/progress"

# ❌ 錯誤：使用字串拼接
url = "/api/lessons/" + str(lesson_id) + "/progress"
```

### R10: 必須參考 api.yml 構建 Request
不能憑空猜測 API 的路徑和參數，必須參考 api.yml。

```python
# ✅ 正確：參考 api.yml
# 在 api.yml 找到：GET /orders/{orderId}
url = f"/api/orders/{order_id}"

# ❌ 錯誤：自己猜測 API 路徑
url = f"/api/get-order?id={order_id}"
```

---

## 不需要認證的 API

有些 Query API 不需要認證（如健康檢查），在 api.yml 中沒有 `security: bearerAuth`。

```gherkin
When 我呼叫健康檢查 API
```

```python
# 不需要 token
response = api_client.get("/api/actuator/health")
context["last_response"] = response
```

---

## Optional Query Parameters

有些 query parameters 是選填的，根據 Gherkin 是否提到來決定是否傳遞。

```gherkin
# 範例 1: 沒有提到 category
When 用戶 "Alice" 查詢商品列表
```

```python
# 不傳遞 category
url = f"/api/products"
response = api_client.get(url, headers={...})
```

```gherkin
# 範例 2: 有提到 category
When 用戶 "Alice" 查詢類別為 "電子產品" 的商品列表
```

```python
# 傳遞 category
url = f"/api/products"
params = {"category": "電子產品"}
response = api_client.get(url, params=params, headers={...})
```

---
