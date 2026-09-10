# Gherkin-to-E2E-Test Translator

## Role
從 Gherkin Feature File 生成 E2E 測試樣板（純註解），識別事件風暴部位，並指引使用對應的 Handler Prompt 生成程式碼。

## Core Mapping
事件風暴 → Gherkin（已完成）→ E2E 測試程式碼註解樣板

映射規則：
- Given → Aggregate / Command / Event
- When → Command / Query / Event
- Then → 操作成功/失敗 / Aggregate / Read Model / Event

## Input
1. Feature File（Gherkin DSL-Level）
2. DBML（Aggregate 定義）
3. API Spec（api.yml）
4. Tech Stack（Python + pytest + FastAPI TestClient + SQLAlchemy + Testcontainers）

## Output
測試樣板（純註解），**放在 `tests/e2e/` 目錄下**，格式：
```python
def test_{scenario_name}():
    # Given {原始 Gherkin 語句}
    # [事件風暴部位: {部位類型} - {名稱}]
    # [生成參考 Prompt: {Handler-檔名}.md]
    
    # When {原始 Gherkin 語句}
    # [事件風暴部位: {部位類型} - {名稱}]
    # [生成參考 Prompt: {Handler-檔名}.md]
    
    # Then {原始 Gherkin 語句}
    # [生成參考 Prompt: {Handler-檔名}.md]
    
    pass
```

## E2E 測試的核心特色

**測試文件組織**：
- **正式功能測試**：放在 `tests/e2e/` 目錄下（如 `test_update_video_progress.py`）
  - 由 Feature File 透過紅燈階段產出
  - 測試真實業務場景
- **基礎建設驗證**：放在 `tests/e2e/walking_skeleton/` 目錄下（如 `test_walking_skeleton.py`）
  - 驗證測試基礎設施是否正常運作
  - 不屬於正式業務測試

**技術架構**：
- **測試對象**: HTTP API Endpoint（透過 FastAPI TestClient）
- **資料庫**: 真實 PostgreSQL (Testcontainers)
- **認證**: JWT Token in Header
- **依賴**: HTTP Client + DB Session (Fixtures)
- **API Spec**: 必須參考 api.yml

---

## Test Organization Principle

**核心原則**: 使用 Test Class（測試類別）來組織屬於同一個 Rule 的測試

**通用概念**:
- 每個 Gherkin **Rule** 對應一個 **Test Class**
- 同一個 Rule 下的所有 Example/Scenario 放在同一個 Test Class 中
- Test Class 的名稱來自 Rule 的描述

**實作方式**（Python + pytest）:

```python
class Test影片進度必須單調遞增:
    """
    對應 Gherkin Rule: 影片進度必須單調遞增
    """
    
    def test_成功增加影片進度(self):
        # ...
        pass
    
    def test_進度不可倒退(self):
        # ...
        pass


class Test進度值必須在0到100之間:
    """
    對應 Gherkin Rule: 進度值必須在 0-100% 之間
    """
    
    def test_有效範圍內的進度值可以更新(self):
        # ...
        pass
```

**命名規則**:
- 移除 Rule 描述中的標點符號和空格
- 使用 `Test` 前綴
- 使用駝峰命名或中文（Python 支援）

---

## Background Handling

**核心原則**: Gherkin 的 Background 有兩個層級，對應不同的測試範圍

### 層級 1: Feature-level Background

**定義位置**: 在 Feature 之下、所有 Rule 之前

**適用範圍**: 整個 Feature 的所有測試案例（跨所有 Rule）

**⚠️ Scope 必須使用 `function`**：
- E2E 測試一定會修改資料，必須使用 `scope="function"` 確保測試隔離
- 每個測試前都重建資料，避免測試間互相影響和外鍵錯誤

**實作方式**（Python pytest）:

```python
import pytest

# Feature-level Background
@pytest.fixture(scope="function", autouse=True)
def feature_background(db_session, api_client, context):
    """
    Feature-level Background
    適用於整個測試檔案的所有測試
    """
    # Given 用戶 "Alice" 已註冊
    # [事件風暴部位: Command - register_user]
    # [生成參考 Prompt: Command-Handler.md]
    
    # And 旅程 1 包含課程 1
    # [事件風暴部位: Aggregate - Journey]
    # [生成參考 Prompt: Aggregate-Given-Handler.md]
    
    pass


class Test影片進度必須單調遞增:
    """
    Rule: 影片進度必須單調遞增
    """
    
    def test_成功增加影片進度(
        self,
        api_client,
        context,
        jwt_helper,
        lesson_progress_repository,
    ):
        # ...
        pass
```

**重點**:
- 必須使用 `scope="function"` 確保測試隔離
- 所有 Test Class 自動共用這個 Background

---

### 層級 2: Rule-level Background

**定義位置**: 在特定 Rule 之下

**適用範圍**: 僅該 Rule 對應的 Test Class

**實作方式**（Python pytest）:

```python
# Feature-level Background
@pytest.fixture(scope="function", autouse=True)
def feature_background(db_session, api_client, context):
    """Feature-level Background"""
    # Given 用戶 "Alice" 已註冊
    # [事件風暴部位: Command - register_user]
    # [生成參考 Prompt: Command-Handler.md]
    
    pass


class Test影片進度必須單調遞增:
    """
    Rule: 影片進度必須單調遞增
    """
    
    @pytest.fixture(autouse=True)
    def setup(self, db_session, context):
        """
        Rule-level Background
        只適用於此 Test Class 的測試
        每個測試方法執行前都會執行（預設 scope="function"）
        """
        # Given 用戶 "Alice" 在課程 1 的初始進度為 0%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
        
        pass
    
    def test_成功增加影片進度(
        self,
        api_client,
        context,
        jwt_helper,
        lesson_progress_repository,
    ):
        # ...
        pass


class Test進度值必須在0到100之間:
    """
    Rule: 進度值必須在 0-100% 之間
    (此 Rule 沒有自己的 Background)
    """
    
    def test_有效範圍內的進度值可以更新(
        self,
        api_client,
        context,
        jwt_helper,
        lesson_progress_repository,
    ):
        # ...
        pass
```

**重點**:
- Rule-level Background 使用 class 內的 `@pytest.fixture(autouse=True)`
- 預設 `scope="function"`，確保測試隔離
- 只出現在對應的 Test Class 中
- 在每個測試方法執行前都會執行

---

## Decision Rules

### Rule 1: Given 語句識別

#### Pattern 1.1: Given + Aggregate
**識別規則**：
- 語句中包含實體名詞 + 屬性描述
- 描述「某個東西的某個屬性是某個值」
- 常見句型（非窮舉）：「在...的...為」「的...為」「包含」「存在」「有」

**通用判斷**：如果 Given 是在建立測試的初始資料狀態（而非執行動作），就使用此 Handler

**範例**：
```gherkin
Given 學生 "Alice" 在課程 1 的進度為 80%，狀態為 "進行中"
```

**輸出**：
```python
# Given 學生 "Alice" 在課程 1 的進度為 80%，狀態為 "進行中"
# [事件風暴部位: Aggregate - LessonProgress]
# [生成參考 Prompt: Aggregate-Given-Handler.md]
```

#### Pattern 1.2: Given + Command
**識別規則**：
- 動作會修改系統狀態（已完成的動作）
- 描述「已經執行完某個動作」
- 常見過去式（非窮舉）：「已訂閱」「已完成」「已建立」「已添加」「已註冊」

**通用判斷**：如果 Given 描述已完成的寫入操作（用於建立前置條件），就使用此 Handler

**E2E 特色**：Given + Command 會實際調用 API 來建立前置條件

**範例**：
```gherkin
Given 用戶 "Alice" 已訂閱旅程 1
```

**輸出**：
```python
# Given 用戶 "Alice" 已訂閱旅程 1
# [事件風暴部位: Command - subscribe_journey]
# [生成參考 Prompt: Command-Handler.md]
```

#### Pattern 1.3: Given + Event
**識別規則**：
- 語句明確標註「事件：」
- 用於 CQRS/微服務架構
- 描述外部事件輸入或已發生的領域事件

**通用判斷**：如果 Given 是模擬事件輸入（用於建立前置條件），就使用此 Handler

**注意**：此為進階用法，需要 Event Handler 支援

**範例**：
```gherkin
Given 事件：學生 "Alice" 已提交挑戰題作業，課程 ID 為 1
```

**輸出**：
```python
# Given 事件：學生 "Alice" 已提交挑戰題作業，課程 ID 為 1
# [事件風暴部位: Event - ChallengeSubmittedEvent]
# [生成參考 Prompt: Event-Handler.md]
```

---

### Rule 2: When 語句識別

#### Pattern 2.1: When + Command
**識別規則**：
- 動作會修改系統狀態
- 描述「執行某個動作」
- 常見現在式（非窮舉）：「更新」「提交」「建立」「刪除」「添加」「移除」

**通用判斷**：如果 When 是修改系統狀態的操作且不需要回傳值，就使用此 Handler

**E2E 特色**：When + Command 會調用 HTTP POST/PUT/DELETE API

**範例**：
```gherkin
When 學生 "Alice" 更新課程 1 的影片進度為 80%
```

**輸出**：
```python
# When 學生 "Alice" 更新課程 1 的影片進度為 80%
# [事件風暴部位: Command - update_video_progress]
# [生成參考 Prompt: Command-Handler.md]
```

#### Pattern 2.2: When + Query
**識別規則**：
- 動作不修改系統狀態，只讀取資料
- 描述「取得某些資訊」的動作
- 常見動詞（非窮舉）：「查詢」「取得」「列出」「檢視」「獲取」

**通用判斷**：如果 When 是讀取操作且需要回傳值供 Then 驗證，就使用此 Handler

**E2E 特色**：When + Query 會調用 HTTP GET API

**範例**：
```gherkin
When 學生 "Alice" 查詢課程 1 的進度
```

**輸出**：
```python
# When 學生 "Alice" 查詢課程 1 的進度
# [事件風暴部位: Query - get_lesson_progress]
# [生成參考 Prompt: Query-Handler.md]
```

#### Pattern 2.3: When + Event
**識別規則**：
- 語句明確標註「事件：」
- 用於 CQRS/微服務架構
- 描述外部系統觸發的事件

**通用判斷**：如果 When 是模擬外部事件觸發（用於測試事件處理），就使用此 Handler

**注意**：此為進階用法，需要 Event Handler 支援

**範例**：
```gherkin
When 事件：第三方金流已完成支付，訂單編號為 "ORDER-123"
```

**輸出**：
```python
# When 事件：第三方金流已完成支付，訂單編號為 "ORDER-123"
# [事件風暴部位: Event - PaymentCompletedEvent]
# [生成參考 Prompt: Event-Handler.md]
```

---

### Rule 3: Then 語句識別

#### Pattern 3.1: Then 操作成功
**識別規則**：
- 明確描述操作成功
- 常見句型：「操作成功」「執行成功」

**通用判斷**：如果 Then 只關注操作是否成功（HTTP 2XX），就使用此 Handler

**E2E 特色**：驗證 HTTP response status code 是否為 2XX

**範例**：
```gherkin
Then 操作成功
```

**輸出**：
```python
# Then 操作成功
# [生成參考 Prompt: Success-Failure-Handler.md]
```

#### Pattern 3.2: Then 操作失敗
**識別規則**：
- 明確描述操作失敗
- 常見句型：「操作失敗」「執行失敗」

**通用判斷**：如果 Then 只關注操作是否失敗（HTTP 4XX），就使用此 Handler

**E2E 特色**：驗證 HTTP response status code 是否為 4XX

**範例**：
```gherkin
Then 操作失敗
```

**輸出**：
```python
# Then 操作失敗
# [生成參考 Prompt: Success-Failure-Handler.md]
```

#### Pattern 3.3: Then + Aggregate
**識別規則**：
- 驗證實體的屬性值（而非 API 回傳值）
- 描述「某個東西的某個屬性應該是某個值」
- 常見句型（非窮舉）：「在...的...應為」「的...應為」「應包含」

**通用判斷**：如果 Then 是驗證 Command 操作後的資料狀態（需要從資料庫查詢），就使用此 Handler

**E2E 特色**：使用 SQLAlchemy 從真實 PostgreSQL 查詢資料

**範例**：
```gherkin
And 學生 "Alice" 在課程 1 的進度應為 90%
```

**輸出**：
```python
# And 學生 "Alice" 在課程 1 的進度應為 90%
# [事件風暴部位: Aggregate - LessonProgress]
# [生成參考 Prompt: Aggregate-Then-Handler.md]
```

#### Pattern 3.4: Then + Read Model
**識別規則**：
- 前提：When 是 Query 操作（已接收 response）
- 驗證的是 API 回傳值（而非資料庫中的狀態）
- 常見句型（非窮舉）：「查詢結果應」「回應應」「應返回」「結果包含」

**通用判斷**：如果 Then 是驗證 Query 操作的回傳值，就使用此 Handler

**E2E 特色**：驗證 HTTP response.json() 的內容

**範例**：
```gherkin
And 查詢結果應包含進度 80，狀態為 "進行中"
```

**輸出**：
```python
# And 查詢結果應包含進度 80，狀態為 "進行中"
# [事件風暴部位: Read Model]
# [生成參考 Prompt: ReadModel-Then-Handler.md]
```

#### Pattern 3.5: Then + Event
**識別規則**：
- 驗證事件的觸發（而非資料狀態）
- 常見句型（非窮舉）：「事件應被觸發」「應發布事件」「應產生事件」

**前提**：系統需要 Event Store/Queue 來記錄事件

**通用判斷**：如果 Then 是驗證某個事件是否被發布，就使用此 Handler

**範例**：
```gherkin
And VideoProgressUpdated 事件應被觸發，課程 ID 為 1
```

**輸出**：
```python
# And VideoProgressUpdated 事件應被觸發，課程 ID 為 1
# [事件風暴部位: Event - VideoProgressUpdated]
# [生成參考 Prompt: Event-Then-Handler.md]
```

---

## Decision Tree

```
讀取 Gherkin 語句
↓
判斷位置（Given/When/Then/And）

Given:
  建立測試的初始資料狀態（實體屬性值）？
    → Aggregate-Given-Handler.md
  已完成的寫入操作（建立前置條件，調用 API）？
    → Command-Handler.md
  模擬事件輸入（標註「事件：」）？
    → Event-Handler.md (進階)

When:
  讀取操作（調用 HTTP GET API）？
    → Query-Handler.md
  寫入操作（調用 HTTP POST/PUT/DELETE API）？
    → Command-Handler.md
  模擬外部事件觸發（標註「事件：」）？
    → Event-Handler.md (進階)

Then:
  只關注操作成功或失敗（HTTP status code）？
    → Success-Failure-Handler.md
  驗證 Command 操作後的資料狀態（從資料庫查詢）？
    → Aggregate-Then-Handler.md
  驗證 Query 操作的 API 回傳值（response.json()）？
    → ReadModel-Then-Handler.md
  驗證事件是否被發布？
    → Event-Then-Handler.md

And:
  繼承前一個 Then 的判斷規則
```

---

## Handler Prompt 映射表

| 事件風暴部位 | 位置 | 識別規則 | Handler Prompt | E2E 特色 |
|------------|------|---------|---------------|---------|
| Aggregate | Given | 建立初始資料狀態（實體屬性值） | Aggregate-Given-Handler.md | 用 SQLAlchemy 寫入 DB |
| Command | Given/When | 寫入操作（已完成/現在執行） | Command-Handler.md | 調用 HTTP POST API |
| Query | When | 讀取操作（需要回傳值） | Query-Handler.md | 調用 HTTP GET API |
| Event | Given/When | 事件輸入（標註「事件：」，進階） | Event-Handler.md | 模擬事件發布 |
| 操作成功/失敗 | Then | 只驗證成功或失敗 | Success-Failure-Handler.md | 驗證 HTTP status code |
| Aggregate | Then | 驗證實體狀態（從資料庫查詢） | Aggregate-Then-Handler.md | 用 SQLAlchemy 查詢 DB |
| Read Model | Then | 驗證 API 回傳值 | ReadModel-Then-Handler.md | 驗證 response.json() |
| Event | Then | 驗證事件觸發 | Event-Then-Handler.md | 查詢 Event Store |

---

## Complete Example

**Input** (同時包含 Feature-level 和 Rule-level Background):
```gherkin
Feature: 課程平台 - 增加影片進度

Background:
  Given 用戶 "Alice" 已註冊，email 為 "alice@test.com"
  And 旅程 1 包含課程 1

Rule: 影片進度必須單調遞增
  
  Background:
    Given 用戶 "Alice" 在課程 1 的初始進度為 0%
  
  Example: 成功增加影片進度
    Given 用戶 "Alice" 在課程 1 的進度為 70%，狀態為 "進行中"
    When 用戶 "Alice" 更新課程 1 的影片進度為 80%
    Then 操作成功
    And 用戶 "Alice" 在課程 1 的進度應為 80%
  
  Example: 進度不可倒退
    Given 用戶 "Alice" 在課程 1 的進度為 70%，狀態為 "進行中"
    When 用戶 "Alice" 更新課程 1 的影片進度為 60%
    Then 操作失敗
    And 用戶 "Alice" 在課程 1 的進度應為 70%

Rule: 進度值必須在0到100之間
  
  Example: 有效範圍內的進度值可以更新
    Given 用戶 "Alice" 在課程 1 的進度為 50%
    When 用戶 "Alice" 更新課程 1 的影片進度為 75%
    Then 操作成功
```

**Output**:
```python
import pytest

# Feature-level Background
@pytest.fixture(scope="function", autouse=True)
def feature_background(db_session, api_client, context):
    """
    Feature-level Background
    適用於整個測試檔案的所有測試
    """
    # Given 用戶 "Alice" 已註冊，email 為 "alice@test.com"
    # [事件風暴部位: Command - register_user]
    # [生成參考 Prompt: Command-Handler.md]
    
    # And 旅程 1 包含課程 1
    # [事件風暴部位: Aggregate - Journey]
    # [生成參考 Prompt: Aggregate-Given-Handler.md]
    
    pass


class Test影片進度必須單調遞增:
    """
    Rule: 影片進度必須單調遞增
    """
    
    @pytest.fixture(autouse=True)
    def setup(self, db_session, context):
        """
        Rule-level Background
        只適用於此 Rule 的測試
        """
        # Given 用戶 "Alice" 在課程 1 的初始進度為 0%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
        
        pass
    
    def test_成功增加影片進度(
        self,
        api_client,
        context,
        jwt_helper,
        lesson_progress_repository,
    ):
        # Given 用戶 "Alice" 在課程 1 的進度為 70%，狀態為 "進行中"
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
        
        # When 用戶 "Alice" 更新課程 1 的影片進度為 80%
        # [事件風暴部位: Command - update_video_progress]
        # [生成參考 Prompt: Command-Handler.md]
        
        # Then 操作成功
        # [生成參考 Prompt: Success-Failure-Handler.md]
        
        # And 用戶 "Alice" 在課程 1 的進度應為 80%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Then-Handler.md]
        
        pass
    
    def test_進度不可倒退(
        self,
        api_client,
        context,
        jwt_helper,
        lesson_progress_repository,
    ):
        # Given 用戶 "Alice" 在課程 1 的進度為 70%，狀態為 "進行中"
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
        
        # When 用戶 "Alice" 更新課程 1 的影片進度為 60%
        # [事件風暴部位: Command - update_video_progress]
        # [生成參考 Prompt: Command-Handler.md]
        
        # Then 操作失敗
        # [生成參考 Prompt: Success-Failure-Handler.md]
        
        # And 用戶 "Alice" 在課程 1 的進度應為 70%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Then-Handler.md]
        
        pass


class Test進度值必須在0到100之間:
    """
    Rule: 進度值必須在 0-100% 之間
    (此 Rule 沒有自己的 Background)
    """
    
    def test_有效範圍內的進度值可以更新(
        self,
        api_client,
        context,
        jwt_helper,
        lesson_progress_repository,
    ):
        # Given 用戶 "Alice" 在課程 1 的進度為 50%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
        
        # When 用戶 "Alice" 更新課程 1 的影片進度為 75%
        # [事件風暴部位: Command - update_video_progress]
        # [生成參考 Prompt: Command-Handler.md]
        
        # Then 操作成功
        # [生成參考 Prompt: Success-Failure-Handler.md]
        
        pass
```

---

## Execution Steps

1. 讀取 Feature File 的 **Feature-level Background** 區塊（如果存在）
2. 讀取 Feature File 的每個 **Rule**
3. 讀取 Rule 的 **Rule-level Background** 區塊（如果存在）
4. **為每個 Rule 建立 Test Class（測試類別）**
5. 如果有 Rule-level Background，在 Test Class 中**建立 Setup Fixture**（使用 `@pytest.fixture(autouse=True)`，預設 scope="function"）
6. 將 Background 依序寫入：
   - **Feature-level Background**：使用 `@pytest.fixture(scope="function", autouse=True)`
   - **Rule-level Background**：使用 `@pytest.fixture(autouse=True)`（預設 scope="function"）
7. 解析 Background 的 Given/And 語句，生成樣板註解
8. 讀取 Rule 下的每個 Example/Scenario
9. 為每個 Example 建立測試方法（放在對應的 Test Class 中）
10. 在測試方法簽名中注入**直接使用**的 fixtures：
   - `api_client` - HTTP Client
   - `context` - 測試上下文
   - `jwt_helper` - JWT Token 生成器
   - `*_repository` - 對應的 Repository（如 `lesson_progress_repository`）
   - **不注入** `db_session`（Repository 內部已包含）
11. 逐句解析測試方法的 Given/When/Then/And
12. 應用 Decision Tree 識別事件風暴部位
13. 生成註解，包含：
   - 原始 Gherkin 語句
   - 事件風暴部位類型和名稱
   - 對應的 Handler Prompt 檔名
14. 組裝完整測試方法
15. 組裝完整 Test Class（Background setup + 所有測試方法）
16. 輸出測試檔案樣板

---

## Critical Rules

### R1: Rule → Test Class
每個 Gherkin Rule 必須對應一個 Test Class，同一 Rule 下的所有測試方法放在同一個 Test Class 中。

### R2: Feature-level Background 使用 Function Scope
Feature-level Background（定義在 Feature 之下）必須使用 `@pytest.fixture(scope="function", autouse=True)`，放在所有 Test Class 之前，所有測試自動共用。確保每個測試都有乾淨的資料，避免測試間互相影響。

### R3: Rule-level Background → Class-level Setup Fixture
Rule-level Background（定義在 Rule 之下）使用 class 內的 `@pytest.fixture(autouse=True)`，預設 `scope="function"`，只出現在對應的 Test Class 中。

### R4: 只輸出註解樣板
不生成任何程式碼，只生成註解和指引。所有函數和方法最後須加上 `pass` 語句以確保語法正確。

### R5: 保留完整 Gherkin 語句
註解中必須包含原始 Gherkin 語句，方便閱讀。

### R6: 明確標註事件風暴部位
每個語句都要識別出對應的事件風暴部位。

### R7: 指引正確的 Handler
根據 Decision Tree 指引使用正確的 Handler Prompt。

### R8: 處理 And 語句
And 語句繼承前一個 Then 的判斷邏輯。

### R9: Background 使用相同註解格式
所有 Background（Feature-level 和 Rule-level）內部必須使用與測試方法相同的樣板註解格式（事件風暴部位 + Handler Prompt）。

### R10: 注入必要的 E2E Fixtures
每個測試方法簽名必須包含必要的 fixtures：
- `api_client` - HTTP Client (requests.Session)
- `context` - 測試上下文 (dict)
- `jwt_helper` - JWT Token 生成器
- `*_repository` - 對應的 Repository（如 `lesson_progress_repository`）

### R11: 只注入直接使用的 Fixtures
測試方法只應注入**直接使用**的 fixtures，不注入間接依賴。

**正確做法**：
- 測試方法注入 `lesson_progress_repository`（直接使用）
- Repository 透過 conftest.py 注入 `db_session`（間接依賴）

```python
# ✅ 正確：只注入直接使用的 fixtures
def test_example(
    self,
    api_client,
    context,
    jwt_helper,
    lesson_progress_repository,  # 直接使用
):
    # db_session 已在 repository 內部
    lesson_progress_repository.save(...)
    pass
```

**為什麼不注入 db_session?**
- Repository fixtures 已經包含 db_session
- 測試方法從不直接使用 db_session
- 保持測試簽名簡潔清晰
