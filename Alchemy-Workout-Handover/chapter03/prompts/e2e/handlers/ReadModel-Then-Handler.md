# ReadModel-Then-Handler

## Trigger
Then 語句驗證**Query 的 API 回傳結果**

**識別規則**:
- 前提: When 是 Query 操作（已接收 response）
- 驗證的是 API 回傳值（而非資料庫中的狀態）
- 常見句型（非窮舉）:「查詢結果應」「回應應」「應返回」「結果包含」

**通用判斷**: 如果 Then 是驗證 Query 操作的回傳值，就使用此 Handler

## Task
從 context 取得 response → assert response.json() 的內容

## E2E 特色
- 從 context["last_response"] 取得 HTTP response
- 使用 response.json() 解析回傳的 JSON
- 參考 api.yml 的 response schema 驗證欄位
- 驗證 API 回傳值（而非資料庫狀態）

## Critical Rule
不重新調用 API，使用 When 中儲存的 response

---

## Pattern Examples (Python)

### 驗證單一記錄

```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
Then 操作成功
And 查詢結果應包含訂單 ID 為 "ORDER-123"，狀態為 "已付款"，金額為 1000
```

```python
# When (已執行)
response = api_client.get(...)
context["last_response"] = response

# Then
response = context["last_response"]
data = response.json()

assert data["orderId"] == "ORDER-123"
assert data["status"] == "已付款"  # API response 可能回傳中文
assert data["totalAmount"] == 1000
```

### 驗證列表

```gherkin
When 用戶 "Alice" 查詢購物車中的所有商品
Then 操作成功
And 查詢結果應包含 2 個商品
And 第一個商品的 ID 應為 "PROD-001"，數量為 2
And 第二個商品的 ID 應為 "PROD-002"，數量為 1
```

```python
response = context["last_response"]
data = response.json()

# 驗證列表長度
items = data["items"]
assert len(items) == 2

# 驗證第一筆
assert items[0]["productId"] == "PROD-001"
assert items[0]["quantity"] == 2

# 驗證第二筆
assert items[1]["productId"] == "PROD-002"
assert items[1]["quantity"] == 1
```

### 驗證嵌套結構

```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
And 查詢結果應包含用戶名稱為 "Alice"
And 查詢結果應包含訂單狀態為 "已付款"
And 查詢結果應包含金額 1000
```

```python
response = context["last_response"]
data = response.json()

assert data["userName"] == "Alice"
assert data["status"] == "已付款"
assert data["totalAmount"] == 1000
```

### 驗證空結果

```gherkin
When 用戶 "Bob" 查詢購物車中的所有商品
Then 操作成功
And 查詢結果應為空列表
```

```python
response = context["last_response"]
data = response.json()

assert data["items"] == []
# 或
assert len(data["items"]) == 0
```

---

## API Response Structure

### 參考 api.yml 的 response schema

**重要**：必須參考 api.yml 中定義的 response schema 來驗證欄位

**步驟**：
1. 在 api.yml 中找到對應的 API endpoint
2. 查看 `responses['200'].content.application/json.schema`
3. 根據 schema 中的欄位名稱和類型驗證

### 範例：從 api.yml 到驗證程式碼

**api.yml**：
```yaml
/orders/{orderId}:
  get:
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
                userName:
                  type: string
                status:
                  type: string
                totalAmount:
                  type: number
```

**Generated Code**：
```python
response = context["last_response"]
data = response.json()

# 根據 api.yml schema 驗證
assert data["orderId"] == "ORDER-123"
assert data["userId"] == "Alice"
assert data["userName"] == "Alice"
assert data["status"] == "已付款"
assert data["totalAmount"] == 1000
```

---

## Nested Structure

### 驗證嵌套物件

```gherkin
And 查詢結果的配送資訊應包含地址為 "台北市"，收件人為 "Alice"
```

```python
response = context["last_response"]
data = response.json()

shipping = data["shipping"]
assert shipping["address"] == "台北市"
assert shipping["recipient"] == "Alice"
```

### 驗證列表中的物件

```gherkin
And 查詢結果應包含 2 個商品
And 第一個商品的 ID 為 "PROD-001"，數量為 2
And 第二個商品的 ID 為 "PROD-002"，數量為 1
```

```python
response = context["last_response"]
data = response.json()

items = data["items"]
assert len(items) == 2

# 第一筆
assert items[0]["productId"] == "PROD-001"
assert items[0]["quantity"] == 2

# 第二筆
assert items[1]["productId"] == "PROD-002"
assert items[1]["quantity"] == 1
```

---

## Query Failure (Python)

```gherkin
Given 學生 "Alice" 未訂閱課程 1
When 學生 "Alice" 查詢課程 1 的進度
Then 操作失敗
And 錯誤訊息應為 "無權限查詢此課程"
```

```python
# When
response = api_client.get(...)
context["last_response"] = response

# Then
response = context["last_response"]
assert response.status_code >= 400

# And 驗證錯誤訊息
data = response.json()
assert data.get("message") == "無權限查詢此課程"
# 或根據 api.yml 的 error response schema
```

---

## Complete Example

### Gherkin

```gherkin
Feature: 查詢訂單詳情

Example: 成功查詢訂單詳情
  Given 訂單 "ORDER-123" 的狀態為 "已付款"，金額為 1000
  When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
  Then 操作成功
  And 查詢結果應包含用戶名稱為 "Alice"
  And 查詢結果應包含訂單 ID 為 "ORDER-123"
  And 查詢結果應包含狀態為 "已付款"
  And 查詢結果應包含金額 1000
```

### Generated Code

```python
def test_成功查詢訂單詳情(self, db_session, api_client, context, jwt_helper):
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
    
    # And 查詢結果應包含用戶名稱為 "Alice"
    data = response.json()
    assert data["userName"] == "Alice"
    
    # And 查詢結果應包含訂單 ID 為 "ORDER-123"
    assert data["orderId"] == "ORDER-123"
    
    # And 查詢結果應包含狀態為 "已付款"
    assert data["status"] == "已付款"
    
    # And 查詢結果應包含金額 1000
    assert data["totalAmount"] == 1000
```

---

## Critical Rules

### R1: 使用 When 中的 response
不重新調用 API，使用 context 中儲存的 response。

```python
# ✅ 正確：使用 context 中的 response
response = context["last_response"]
data = response.json()
assert data["progress"] == 80

# ❌ 錯誤：重新調用 API
response = api_client.get(...)  # 不應該重新調用
data = response.json()
```

### R2: 只驗證 Gherkin 提到的欄位
只 assert Gherkin 中明確提到的欄位。

```python
# Gherkin: And 查詢結果應包含訂單 ID 為 "ORDER-123"

# ✅ 正確：只驗證訂單 ID
assert data["orderId"] == "ORDER-123"

# ❌ 錯誤：驗證額外的欄位
assert data["orderId"] == "ORDER-123"
assert data["createdAt"] is not None  # Gherkin 沒提到
```

### R3: 欄位名稱使用 camelCase（以 api.yml 為準）
Response 的欄位名稱必須與 api.yml 完全一致，通常是 camelCase。

```python
# ✅ 正確：使用 camelCase（參考 api.yml）
assert data["orderId"] == "ORDER-123"
assert data["userName"] == "Alice"

# ❌ 錯誤：使用 snake_case
assert data["order_id"] == "ORDER-123"
assert data["user_name"] == "Alice"
```

### R4: API response 的狀態值可能是中文
與 Aggregate 不同，API response 的狀態值可能是中文（取決於後端實作）。

```python
# API response 可能回傳中文
assert data["status"] == "進行中"

# 或英文 enum（取決於 api.yml 的定義）
assert data["status"] == "IN_PROGRESS"

# 要參考 api.yml 的 response schema
```

### R5: 列表索引從 0 開始
```python
# ✅ 第一筆是 lessons[0]
assert lessons[0]["lessonId"] == 1

# ❌ 第一筆不是 lessons[1]
```

### R6: 驗證列表長度
在驗證列表元素之前，先驗證長度。

```python
# ✅ 正確：先驗證長度
lessons = data["lessons"]
assert len(lessons) == 2
assert lessons[0]["lessonId"] == 1

# ❌ 錯誤：沒有驗證長度（可能 IndexError）
lessons = data["lessons"]
assert lessons[0]["lessonId"] == 1  # 如果 lessons 是空的會報錯
```

### R7: 可以合併多個 And 的驗證
如果多個 And 驗證同一個 response 的不同欄位，可以一次取得 response。

```gherkin
And 查詢結果應包含訂單 ID 為 "ORDER-123"
And 查詢結果應包含狀態為 "已付款"
```

```python
# ✅ 正確：取得一次 response，驗證多個欄位
response = context["last_response"]
data = response.json()
assert data["orderId"] == "ORDER-123"
assert data["status"] == "已付款"

# ❌ 錯誤：重複取得 response（不必要）
response1 = context["last_response"]
data1 = response1.json()
assert data1["orderId"] == "ORDER-123"

response2 = context["last_response"]
data2 = response2.json()
assert data2["status"] == "已付款"
```

### R8: 使用 response.json() 解析 JSON
必須使用 response.json() 方法解析 JSON 回傳值。

```python
# ✅ 正確：使用 response.json()
data = response.json()
assert data["progress"] == 80

# ❌ 錯誤：使用其他方式
data = json.loads(response.text)
```

### R9: 從 API response 驗證，不查詢資料庫
ReadModel-Then-Handler 驗證的是 API response，不是資料庫狀態。

```python
# ✅ 正確：驗證 API response
response = context["last_response"]
data = response.json()
assert data["totalAmount"] == 1000

# ❌ 錯誤：查詢資料庫
order = repository.find_by_id(...)  # 這是 Aggregate-Then-Handler 的工作
assert order.total_amount == 1000
```

### R10: 必須參考 api.yml 的 response schema
不能憑空猜測 response 的欄位名稱，必須參考 api.yml。

```python
# ✅ 正確：參考 api.yml
# 在 api.yml 中找到 response schema 定義: { orderId: string, totalAmount: number }
assert data["orderId"] == "ORDER-123"
assert data["totalAmount"] == 1000

# ❌ 錯誤：自己猜測欄位名稱
assert data["order"] == "ORDER-123"  # 欄位名稱錯誤
assert data["amount"] == 1000  # 欄位名稱錯誤
```

---

## 與 Aggregate-Then-Handler 的區別

| 面向 | ReadModel-Then-Handler | Aggregate-Then-Handler |
|------|----------------------|-------------------|
| 驗證對象 | API response 的內容 | 資料庫中的 Aggregate |
| 資料來源 | context["last_response"] | SQLAlchemy Repository |
| 使用時機 | Query 操作後驗證回傳值 | Command 操作後驗證狀態 |
| 範例 | And 查詢結果應包含金額 1000 | And 訂單 "ORDER-123" 的金額應為 1000 |
| 狀態值 | 可能是中文或英文（參考 api.yml） | 必須是英文 enum |

---

## 驗證錯誤 Response

當 Query 失敗時，也可以驗證錯誤 response。

```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-999" 的詳情
Then 操作失敗
And 錯誤訊息應為 "訂單不存在"
```

```python
# When
response = api_client.get(...)
context["last_response"] = response

# Then
response = context["last_response"]
assert response.status_code == 404

# And 驗證錯誤訊息
data = response.json()
assert data.get("message") == "訂單不存在"
# 或根據 api.yml 的 error response schema
assert data.get("error") == "訂單不存在"
```

---

## 驗證表格資料（DataTable）

```gherkin
And 查詢結果應包含:
  | 用戶名稱 | 訂單ID      | 金額 | 狀態   |
  | Alice    | ORDER-123   | 1000 | 已付款 |
```

```python
response = context["last_response"]
data = response.json()

assert data["userName"] == "Alice"
assert data["orderId"] == "ORDER-123"
assert data["totalAmount"] == 1000
assert data["status"] == "已付款"
```

---
