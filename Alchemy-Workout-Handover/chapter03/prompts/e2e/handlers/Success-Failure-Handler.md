# Success-Failure-Handler

## Trigger
Then 語句描述**操作的成功或失敗結果**（驗證 HTTP status code）

**識別規則**:
- 明確描述操作結果（成功/失敗）
- 常見句型:「操作成功」「操作失敗」「執行成功」「執行失敗」

**通用判斷**: 如果 Then 只關注操作是否成功（HTTP 2XX）或失敗（HTTP 4XX），就使用此 Handler

## Task
從 context 取得 response，驗證 HTTP status code

## E2E 特色
- 從 context["last_response"] 取得 HTTP response
- 驗證 response.status_code
- **必須嚴格參考 api.yml 中定義的精確 status code**
- **禁止列舉或猜測 status code**

---

## Pattern 1: 操作成功 (Python)

> **核心原則**：必須查閱 api.yml，使用精確的 status code，禁止列舉

```gherkin
When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
Then 操作成功
```

**強制步驟**：
1. **查閱 api.yml**：找到 `/cart/items` 的 POST method
2. **找到精確的 status code**：查看 `responses` 中定義的成功 status code（如 `'201'`）
3. **使用精確驗證**：只使用 api.yml 中明確定義的 status code

**範例 - 假設 api.yml 定義如下**：
```yaml
# api.yml
/cart/items:
  post:
    responses:
      '201':
        description: 成功加入購物車
      '400':
        description: 參數錯誤
```

**生成程式碼**：
```python
# When (已執行)
response = api_client.post(...)
context["last_response"] = response

# Then 操作成功
# 參考 api.yml: /cart/items POST → responses: '201'
response = context["last_response"]
assert response.status_code == 201, f"預期 201，實際 {response.status_code}: {response.text}"
```

**關鍵**：
- ✅ 使用精確的 `== 201`（api.yml 定義）
- ❌ 不要用 `in [200, 201, 204]`（列舉猜測）
- ❌ 不要用 `>= 200 and < 300`（範圍猜測）

---

## Pattern 2: 操作失敗 (Python)

> **核心原則**：必須查閱 api.yml，使用精確的 status code，禁止範圍驗證

```gherkin
When 用戶 "Alice" 將商品 "OUT-OF-STOCK" 加入購物車，數量為 1
Then 操作失敗
```

**強制步驟**：
1. **查閱 api.yml**：找到 `/cart/items` 的 POST method
2. **找到所有失敗的 status code**：查看 `responses` 中所有 4XX 定義
3. **根據 Gherkin 選擇精確的 code**：依據失敗原因選擇對應的 status code

**範例 - 假設 api.yml 定義如下**：
```yaml
# api.yml
/cart/items:
  post:
    responses:
      '201':
        description: 成功加入購物車
      '400':
        description: 請求參數錯誤
      '409':
        description: 商品庫存不足
```

**生成程式碼**：
```python
# When (已執行)
response = api_client.post(...)
context["last_response"] = response

# Then 操作失敗
# Gherkin: "OUT-OF-STOCK" → api.yml: '409' (商品庫存不足)
response = context["last_response"]
assert response.status_code == 409, f"預期 409，實際 {response.status_code}: {response.text}"
```

**關鍵**：
- ✅ 使用精確的 `== 409`（根據 Gherkin 和 api.yml）
- ❌ 不要用 `>= 400`（範圍猜測）
- ❌ 不要用 `in [400, 409]`（列舉猜測）

**如何判斷使用哪個失敗 status code**：
| Gherkin 失敗原因 | 查閱 api.yml | 使用的 Status Code |
|----------------|-------------|-------------------|
| 數量為 -1 | `responses['400']` | 400 (參數錯誤) |
| 商品不存在 | `responses['404']` | 404 (資源不存在) |
| 庫存不足 | `responses['409']` | 409 (業務規則衝突) |

---

## 如何確定正確的 Status Code

> **絕對原則**：100% 參考 api.yml 中的精確定義，禁止猜測、列舉、範圍驗證。

### 步驟 1: 找到對應的 API Endpoint

在 api.yml 的 `paths` 下找到對應的路徑和 HTTP method：

```yaml
# api.yml 範例
/cart/items:
  post:
    summary: 將商品加入購物車
    responses:
      '201':
        description: 成功加入購物車
      '400':
        description: 請求參數錯誤
      '409':
        description: 商品庫存不足
```

### 步驟 2: 查看 responses 定義

- **成功情況**：查看 `2XX` 的 response（如 `'200'`, `'201'`, `'204'`）
- **失敗情況**：查看 `4XX` 的 response（如 `'400'`, `'404'`, `'409'`）

### 步驟 3: 根據 Gherkin 選擇對應的 Status Code

根據 Gherkin 描述的情境，選擇最符合的 status code：

| Gherkin 情境 | 查閱 api.yml | 使用的 Status Code |
|------------|-------------|-------------------|
| 操作成功 | `responses['200']` 或 `'201'` | 200 或 201 |
| 參數錯誤（數量為 -1） | `responses['400']` | 400 |
| 資源不存在 | `responses['404']` | 404 |
| 業務規則衝突（庫存不足） | `responses['409']` | 409 |

### 範例：參考 api.yml 決定 Status Code

**Gherkin**：
```gherkin
When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 -1
Then 操作失敗
```

**查閱 api.yml**：
```yaml
/cart/items:
  post:
    responses:
      '201':
        description: 成功
      '400':
        description: 參數錯誤（數量必須為正數）
      '409':
        description: 商品庫存不足
```

**生成程式碼**：
```python
# 參考 api.yml: /cart/items POST → responses: '400' (參數錯誤)
assert response.status_code == 400, f"預期 400，實際 {response.status_code}: {response.text}"
```

---

## Error Message Verification

除了驗證 status code，還可以驗證錯誤訊息：

```gherkin
When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
Then 操作失敗
And 錯誤訊息應為 "訂單不存在"
```

**步驟**：
1. 查閱 api.yml 找到精確的失敗 status code（如 404）
2. 查閱 api.yml 的 error response schema 結構
3. 使用精確的欄位名稱驗證錯誤訊息

**假設 api.yml 定義**：
```yaml
# api.yml
/orders/{orderId}:
  get:
    responses:
      '200':
        description: 成功取得訂單
      '404':
        description: 訂單不存在
        content:
          application/json:
            schema:
              properties:
                message:
                  type: string
```

**生成程式碼**：
```python
# Then 操作失敗
# 參考 api.yml: /orders/{orderId} GET → responses: '404'
response = context["last_response"]
assert response.status_code == 404, f"預期 404，實際 {response.status_code}: {response.text}"

# And 驗證錯誤訊息
# 參考 api.yml error schema: message 欄位
data = response.json()
assert data["message"] == "訂單不存在"
```

---

## Complete Example

### Example 1: 成功場景

**Gherkin**：
```gherkin
Example: 成功將商品加入購物車
  Given 用戶 "Alice" 的購物車為空
  When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 2
  Then 操作成功
  And 用戶 "Alice" 的購物車中商品 "PROD-001" 的數量應為 2
```

**假設 api.yml 定義**：
```yaml
# api.yml
/cart/items:
  post:
    responses:
      '201':
        description: 成功加入購物車
```

**Generated Code**：
```python
def test_成功將商品加入購物車(self, api_client, context, jwt_helper, cart_repository):
    # Given（購物車為空，無需額外操作）
    context["Alice.id"] = "Alice"
    
    # When
    user_id = context.get("Alice.id")
    token = jwt_helper.generate_token(user_id)
    
    response = api_client.post(
        f"{context['api_base_url']}/api/cart/items",
        headers={"Authorization": f"Bearer {token}"},
        json={"product_id": "PROD-001", "quantity": 2}
    )
    context["last_response"] = response
    
    # Then 操作成功
    # 參考 api.yml: /cart/items POST → responses: '201'
    assert response.status_code == 201, f"預期 201，實際 {response.status_code}: {response.text}"
    
    # And 驗證資料狀態
    cart_item = cart_repository.find_by_user_and_product(
        user_id="Alice",
        product_id="PROD-001"
    )
    assert cart_item.quantity == 2
```

### Example 2: 失敗場景

**Gherkin**：
```gherkin
Example: 數量不可為負數
  Given 用戶 "Alice" 的購物車為空
  When 用戶 "Alice" 將商品 "PROD-001" 加入購物車，數量為 -1
  Then 操作失敗
  And 用戶 "Alice" 的購物車應為空
```

**假設 api.yml 定義**：
```yaml
# api.yml
/cart/items:
  post:
    responses:
      '201':
        description: 成功加入購物車
      '400':
        description: 請求參數錯誤（數量必須為正數）
```

**Generated Code**：
```python
def test_數量不可為負數(self, api_client, context, jwt_helper, cart_repository):
    # Given
    context["Alice.id"] = "Alice"
    
    # When
    user_id = context.get("Alice.id")
    token = jwt_helper.generate_token(user_id)
    
    response = api_client.post(
        f"{context['api_base_url']}/api/cart/items",
        headers={"Authorization": f"Bearer {token}"},
        json={"product_id": "PROD-001", "quantity": -1}
    )
    context["last_response"] = response
    
    # Then 操作失敗
    # Gherkin: "數量為 -1" → api.yml: /cart/items POST → responses: '400' (參數錯誤)
    assert response.status_code == 400, f"預期 400，實際 {response.status_code}: {response.text}"
    
    # And 用戶 "Alice" 的購物車應為空（資料狀態未改變）
    cart_items = cart_repository.find_all_by_user(user_id="Alice")
    assert len(cart_items) == 0
```

---

## Critical Rules

### R1: 必須使用精確的 status code（禁止列舉和範圍驗證）

**絕對原則**：
1. 查閱 api.yml 找到該 API endpoint 的 responses 定義
2. 使用精確的 status code（`==`）
3. 禁止列舉（`in [...]`）和範圍驗證（`>=`、`<`）

```python
# ✅ 正確：查閱 api.yml，使用精確的 status code
# api.yml: /cart/items POST → responses: '201'
response = context["last_response"]
assert response.status_code == 201, f"預期 201，實際 {response.status_code}: {response.text}"

# ❌ 錯誤：列舉（猜測可能的值）
assert response.status_code in [200, 201, 204]

# ❌ 錯誤：範圍驗證（不精確）
assert response.status_code >= 200 and response.status_code < 300

# ❌ 錯誤：只驗證成功但沒有精確 code
assert response.status_code // 100 == 2
```

### R2: 從 context 取得 response
不重新調用 API，使用 context 中儲存的 response。

```python
# ✅ 正確：從 context 取得
response = context["last_response"]
assert response.status_code == 200

# ❌ 錯誤：重新調用 API
response = api_client.post(...)
assert response.status_code == 200
```

### R3: 永遠使用精確驗證（即使 api.yml 定義多個 status code）

**即使 api.yml 定義多個可能的 status code，也要根據 Gherkin 情境選擇精確的一個。**

```python
# 假設 api.yml 定義：
# /cart/items POST:
#   responses:
#     '200': 更新現有商品數量
#     '201': 新增商品到購物車

# ✅ 正確：根據 Gherkin 情境選擇精確的 code
# Gherkin: "購物車為空" → 應該是新增 → 201
assert response.status_code == 201, f"預期 201，實際 {response.status_code}: {response.text}"

# ❌ 錯誤：列舉所有可能的 code
assert response.status_code in [200, 201]
```

### R4: 失敗時必須選擇精確的 Status Code（禁止範圍驗證）

根據 api.yml 定義和 Gherkin 的失敗原因，選擇精確的 status code。

```python
# ✅ 正確：根據 api.yml 和 Gherkin，使用精確的 code
# Gherkin: "數量為 -1" → api.yml: '400' (參數錯誤)
assert response.status_code == 400, f"預期 400，實際 {response.status_code}: {response.text}"

# Gherkin: "商品不存在" → api.yml: '404' (資源不存在)
assert response.status_code == 404, f"預期 404，實際 {response.status_code}: {response.text}"

# Gherkin: "商品已下架" → api.yml: '409' (業務規則衝突)
assert response.status_code == 409, f"預期 409，實際 {response.status_code}: {response.text}"

# ❌ 錯誤：範圍驗證（不精確）
assert response.status_code >= 400

# ❌ 錯誤：列舉猜測
assert response.status_code in [400, 404, 409]
```

### R5: 不同 HTTP Method 的 Status Code 必須分別查閱 api.yml

不同的 HTTP Method 在 api.yml 中**必定**定義不同的成功 status code，**禁止假設**。

**強制步驟**：
1. 在 api.yml 中找到對應的 path 和 method（`get`, `post`, `put`, `patch`, `delete`）
2. 查看**該 method** 的 `responses` 定義
3. 使用該 method 定義的精確 status code

```python
# 範例 1: GET method
# api.yml: /users/{id} get → responses: '200'
assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"

# 範例 2: POST method (創建資源)
# api.yml: /users post → responses: '201'
assert response.status_code == 201, f"預期 201，實際 {response.status_code}: {response.text}"

# 範例 3: PUT method (完整更新)
# api.yml: /users/{id} put → responses: '200'
assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"

# 範例 4: PATCH method (部分更新)
# api.yml: /users/{id} patch → responses: '200'
assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"

# 範例 5: DELETE method
# api.yml: /users/{id} delete → responses: '204'
assert response.status_code == 204, f"預期 204，實際 {response.status_code}: {response.text}"
```

**關鍵**：
- ✅ 每個 method 單獨查閱 api.yml
- ❌ 不要假設「POST 一定是 201」
- ❌ 不要假設「DELETE 一定是 204」

### R7: 不在 Success-Failure-Handler 中驗證 response 內容
只驗證 status code，不驗證 response body。

```python
# ✅ 正確：只驗證 status code
# api.yml: /lesson-progress/update-video-progress POST → responses: '200'
response = context["last_response"]
assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"

# ❌ 錯誤：驗證 response 內容
response = context["last_response"]
assert response.status_code == 200
data = response.json()
assert data["progress"] == 80  # 這是 ReadModel-Then-Handler 的工作
```

### R8: 失敗時資料狀態不應改變
失敗場景中，通常需要驗證資料狀態未被修改。

```python
# Then 操作失敗
# api.yml: /cart/items POST → responses: '400' (參數錯誤)
assert response.status_code == 400, f"預期 400，實際 {response.status_code}: {response.text}"

# And 資料狀態未改變
cart_item = repository.find_by_user_and_product(user_id="Alice", product_id="PROD-001")
assert cart_item.quantity == 2  # 保持原值
```

### R9: 錯誤訊息驗證是選填的
驗證錯誤訊息不是必須的，取決於 Gherkin 是否明確要求。

```gherkin
# 沒有要求驗證錯誤訊息
Then 操作失敗
```
```python
# api.yml: /cart/items POST → responses: '400'
assert response.status_code == 400, f"預期 400，實際 {response.status_code}: {response.text}"
```

```gherkin
# 要求驗證錯誤訊息
Then 操作失敗
And 錯誤訊息應為 "數量不可為負數"
```
```python
# api.yml: /cart/items POST → responses: '400'
assert response.status_code == 400, f"預期 400，實際 {response.status_code}: {response.text}"

# 查閱 api.yml error response schema
data = response.json()
assert data["message"] == "數量不可為負數"
```

### R10: 必須為每個 Status Code 添加詳細註解

**強制要求**：每個 status code 驗證都必須包含：
1. 註解說明查閱的 api.yml endpoint
2. 錯誤訊息包含預期和實際值

```python
# ✅ 正確：完整的註解和錯誤訊息
# 參考 api.yml: /cart/items POST → responses: '201' (成功加入購物車)
assert response.status_code == 201, f"預期 201，實際 {response.status_code}: {response.text}"

# ❌ 錯誤：沒有註解
assert response.status_code == 201

# ❌ 錯誤：沒有錯誤訊息
assert response.status_code == 201, "status code 錯誤"
```

### R11: Error Schema 也必須從 api.yml 查閱

如果要驗證 error response，必須查閱 api.yml 中定義的 schema。

```yaml
# api.yml 範例
/cart/items:
  post:
    responses:
      '201':
        description: 成功加入購物車
      '400':
        description: 參數錯誤
        content:
          application/json:
            schema:
              properties:
                message:
                  type: string
                code:
                  type: string
```

```python
# ✅ 正確：根據 api.yml 驗證
# 參考 api.yml: /cart/items POST → responses: '400' (參數錯誤)
assert response.status_code == 400, f"預期 400，實際 {response.status_code}: {response.text}"

# 參考 api.yml error schema: message, code 欄位
data = response.json()
assert data["message"] == "參數錯誤"
assert data["code"] == "INVALID_PARAMETER"

# ❌ 錯誤：猜測 error schema 結構
data = response.json()
assert data["error"] == "參數錯誤"  # api.yml 沒有定義 "error" 欄位
```

---

## 重要提醒

### 絕對禁止猜測 Status Code

> **鐵律**：100% 參考 api.yml，0% 猜測。

**禁止的行為**：
- ❌ 列舉可能的值：`in [200, 201, 204]`
- ❌ 範圍驗證：`>= 200`, `< 300`
- ❌ 假設慣例：「POST 一定是 201」
- ❌ 模糊驗證：`// 100 == 2`

**強制的行為**：
- ✅ 查閱 api.yml 找到精確的 endpoint 和 method
- ✅ 使用精確的 status code：`== 201`
- ✅ 添加詳細註解說明來源
- ✅ 包含完整的錯誤訊息

### 查閱流程（強制執行）

```
1. 讀取 Gherkin When 語句，識別 API 操作
   ↓
2. 打開 api.yml，找到對應的 path 和 HTTP method
   ↓
3. 查看該 method 的 responses 定義（列出所有 status code）
   ↓
4. 根據 Then 語句（成功/失敗）和 Gherkin 情境選擇精確的 status code
   ↓
5. 生成程式碼：
   # 參考 api.yml: <path> <method> → responses: '<code>'
   assert response.status_code == <code>, f"預期 <code>，實際 {response.status_code}: {response.text}"
```

### 範例：完整的查閱流程

**Gherkin**：
```gherkin
When 用戶 "Alice" 更新課程 1 的影片進度為 80%
Then 操作成功
```

**步驟 1**：識別 API 操作 → 更新影片進度

**步驟 2**：查閱 api.yml
```yaml
# api.yml
/lesson-progress/update-video-progress:
  post:
    responses:
      '200':
        description: 成功更新影片進度
      '400':
        description: 請求參數錯誤
      '404':
        description: 課程不存在
```

**步驟 3**：根據 Then 語句選擇 → 操作成功 → '200'

**步驟 4**：生成程式碼
```python
# Then 操作成功
# 參考 api.yml: /lesson-progress/update-video-progress POST → responses: '200' (成功更新影片進度)
assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"
```

---

## 不需要 Success-Failure-Handler 的情況

有些測試不需要明確的「操作成功」或「操作失敗」，而是直接驗證資料或回傳值：

```gherkin
# 不需要「Then 操作成功」
Example: 查詢訂單詳情
  Given 訂單 "ORDER-123" 的狀態為 "已付款"
  When 用戶 "Alice" 查詢訂單 "ORDER-123" 的詳情
  And 查詢結果應包含訂單 ID 為 "ORDER-123"
```

在這種情況下，ReadModel-Then-Handler 會隱含地驗證成功（因為如果失敗，response.json() 會報錯）。

---
