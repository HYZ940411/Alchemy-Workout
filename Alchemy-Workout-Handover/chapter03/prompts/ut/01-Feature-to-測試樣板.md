# Gherkin-to-Test Translator

## Role
從 Gherkin Feature File 生成測試樣板（純註解），識別事件風暴部位，並指引使用對應的 Handler Prompt 生成程式碼。

## Core Mapping
事件風暴 → Gherkin（已完成）→ 測試程式碼註解樣板

映射規則：
- Given → Aggregate / Command / Event
- When → Command / Query / Event
- Then → 操作成功/失敗 / Aggregate / Read Model / Event

## Input
1. Feature File（Gherkin DSL-Level）
2. DBML（Aggregate 定義）
3. Tech Stack（預設 Python + pytest）

## Output
測試樣板（純註解），格式：
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
```

## Test Organization Principle

**核心原則**: 使用 Test Group（測試群組）來組織屬於同一個 Rule 的測試

**通用概念**:
- 每個 Gherkin **Rule** 對應一個 **Test Group**
- 同一個 Rule 下的所有 Example/Scenario 放在同一個 Test Group 中
- Test Group 的名稱來自 Rule 的描述

**實作方式**（以 Python 為例）:

```python
class Test影片進度必須單調遞增:
    """
    對應 Gherkin Rule: 影片進度必須單調遞增
    """
    
    def test_成功增加影片進度(self):
        # ...
    
    def test_進度不可倒退(self):
        # ...
    
    def test_相同進度值的更新應被接受但不改變狀態(self):
        # ...


class Test進度值必須在0到100之間:
    """
    對應 Gherkin Rule: 進度值必須在 0-100% 之間
    """
    
    def test_有效範圍內的進度值可以更新(self):
        # ...
    
    def test_超出範圍的進度值無法更新(self):
        # ...
```

**語言通用說明**:
- 不同語言有不同的測試群組機制（Python 用 class，Java/C# 用 class with annotations，Go 用 subtests）
- 無論使用何種語言，都應該將同一個 Rule 的測試組織在一起
- Test Group 名稱應該反映 Rule 的業務意義

**命名規則**:
- 移除 Rule 描述中的標點符號和空格
- 使用駝峰命名或底線分隔（依照語言慣例）
- 加上 `Test` 前綴（依照測試框架慣例）

---

## Background Handling

**核心原則**: Gherkin 的 Background 有兩個層級，對應不同的測試範圍

### 層級 1: Feature-level Background

**定義位置**: 在 Feature 之下、所有 Rule 之前

**適用範圍**: 整個 Feature 的所有測試案例（跨所有 Rule）

**實作方式**（以 Python pytest 為例）:

```python
import pytest

# Feature-level Background: 使用 module-level fixture
@pytest.fixture(scope="module", autouse=True)
def feature_background():
    """
    Feature-level Background
    在整個測試檔案執行前設置一次，所有 Test Class 共用
    """
    # Given 用戶 "Alice" 已訂閱旅程 1
    # [事件風暴部位: Command - subscribe_journey]
    # [生成參考 Prompt: Command-Handler.md]
    
    # And 旅程 1 包含課程 1
    # [事件風暴部位: Aggregate - Journey]
    # [生成參考 Prompt: Aggregate-Given-Handler.md]


class Test影片進度必須單調遞增:
    """
    Rule: 影片進度必須單調遞增
    """
    
    def test_成功增加影片進度(self):
        # ...
    
    def test_進度不可倒退(self):
        # ...


class Test進度值必須在0到100之間:
    """
    Rule: 進度值必須在 0-100% 之間
    """
    
    def test_有效範圍內的進度值可以更新(self):
        # ...
```

**重點**:
- Feature-level Background 使用**測試檔案層級的 setup**（不在 Test Class 內）
- 所有 Test Class 自動共用這個 Background
- Python pytest: 使用 `@pytest.fixture(scope="module", autouse=True)`
- 或者在檔案開頭使用 `setup_module()` / `teardown_module()`

---

### 層級 2: Rule-level Background

**定義位置**: 在特定 Rule 之下

**適用範圍**: 僅該 Rule 對應的 Test Class

**實作方式**（以 Python pytest 為例）:

```python
@pytest.fixture(scope="module", autouse=True)
def feature_background():
    """Feature-level Background"""
    # Given 用戶 "Alice" 已訂閱旅程 1
    # [事件風暴部位: Command - subscribe_journey]
    # [生成參考 Prompt: Command-Handler.md]


class Test影片進度必須單調遞增:
    """
    Rule: 影片進度必須單調遞增
    """
    
    def setup_method(self):
        """
        Rule-level Background
        只適用於此 Test Class 的測試
        """
        # Given 用戶 "Alice" 在課程 1 的初始進度為 0%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
    
    def test_成功增加影片進度(self):
        # ...


class Test進度值必須在0到100之間:
    """
    Rule: 進度值必須在 0-100% 之間
    (此 Rule 沒有自己的 Background)
    """
    
    def test_有效範圍內的進度值可以更新(self):
        # ...
```

**重點**:
- Rule-level Background 使用 **Test Class 層級的 Before Each Hook**
- 只出現在對應的 Test Class 中
- Python pytest: 使用 `setup_method(self)`

### 重要提醒

- **Feature-level Background**: 通常執行一次或在每個 Test Class 執行前執行，取決於測試框架
- **Rule-level Background**: 在每個測試方法執行前都會執行
- 確保 Background 不會產生副作用或相互干擾
---

## Decision Rules

### Rule 1: Given 語句識別

#### Pattern 1.1: Given + Aggregate
**識別規則**：
- 語句中包含實體名詞 + 屬性描述
- 描述"某個東西的某個屬性是某個值"
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
- 描述"已經執行完某個動作"
- 常見過去式（非窮舉）：「已訂閱」「已完成」「已建立」「已添加」

**通用判斷**：如果 Given 描述已完成的寫入操作（用於建立前置條件），就使用此 Handler

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
- 描述"執行某個動作"
- 常見現在式（非窮舉）：「更新」「提交」「建立」「刪除」「添加」「移除」

**通用判斷**：如果 When 是修改系統狀態的操作且不需要回傳值，就使用此 Handler

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
- 描述"取得某些資訊"的動作
- 常見動詞（非窮舉）：「查詢」「取得」「列出」「檢視」「獲取」

**通用判斷**：如果 When 是讀取操作且需要回傳值供 Then 驗證，就使用此 Handler

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

**通用判斷**：如果 Then 只關注操作是否成功（不拋出異常），就使用此 Handler

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

**通用判斷**：如果 Then 只關注操作是否拋出異常（而非驗證具體資料），就使用此 Handler

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
- 驗證實體的屬性值（而非查詢回傳值）
- 描述"某個東西的某個屬性應該是某個值"
- 常見句型（非窮舉）：「在...的...應為」「的...應為」「應包含」

**通用判斷**：如果 Then 是驗證 Command 操作後的資料狀態（需要從 repository 重新查詢），就使用此 Handler

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
- 前提：When 是 Query 操作（已接收 result）
- 驗證的是查詢回傳值（而非 repository 中的狀態）
- 常見句型（非窮舉）：「查詢結果應」「回應應」「應返回」「結果包含」

**通用判斷**：如果 Then 是驗證 Query 操作的回傳值，就使用此 Handler

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
  已完成的寫入操作（建立前置條件）？
    → Command-Handler.md
  模擬事件輸入（標註「事件：」）？
    → Event-Handler.md (進階)

When:
  讀取操作（需要回傳值供 Then 驗證）？
    → Query-Handler.md
  寫入操作（修改系統狀態，無回傳值）？
    → Command-Handler.md
  模擬外部事件觸發（標註「事件：」）？
    → Event-Handler.md (進階)

Then:
  只關注操作成功或失敗（不驗證具體資料）？
    → Success-Failure-Handler.md
  驗證 Command 操作後的資料狀態（從 repository 查詢）？
    → Aggregate-Then-Handler.md
  驗證 Query 操作的回傳值（使用 When 的 result）？
    → ReadModel-Then-Handler.md
  驗證事件是否被發布？
    → Event-Then-Handler.md

And:
  繼承前一個 Then 的判斷規則
```

---

## Handler Prompt 映射表

| 事件風暴部位 | 位置 | 識別規則 | Handler Prompt |
|------------|------|---------|---------------|
| Aggregate | Given | 建立初始資料狀態（實體屬性值） | Aggregate-Given-Handler.md |
| Command | Given/When | 寫入操作（已完成/現在執行，無回傳值） | Command-Handler.md |
| Query | When | 讀取操作（需要回傳值） | Query-Handler.md |
| Event | Given/When | 事件輸入（標註「事件：」，進階） | Event-Handler.md |
| 操作成功/失敗 | Then | 只驗證成功或失敗（不驗證資料） | Success-Failure-Handler.md |
| Aggregate | Then | 驗證實體狀態（從 repository 查詢） | Aggregate-Then-Handler.md |
| Read Model | Then | 驗證查詢結果（使用 When 的 result） | ReadModel-Then-Handler.md |
| Event | Then | 驗證事件觸發 | Event-Then-Handler.md |

---

## Complete Example

**Input** (同時包含 Feature-level 和 Rule-level Background):
```gherkin
Feature: 課程平台 - 增加影片進度

Background:
  Given 用戶 "Alice" 已訂閱旅程 1
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
@pytest.fixture(scope="module", autouse=True)
def feature_background():
    """
    Feature-level Background
    適用於整個測試檔案的所有測試
    """
    # Given 用戶 "Alice" 已訂閱旅程 1
    # [事件風暴部位: Command - subscribe_journey]
    # [生成參考 Prompt: Command-Handler.md]
    
    # And 旅程 1 包含課程 1
    # [事件風暴部位: Aggregate - Journey]
    # [生成參考 Prompt: Aggregate-Given-Handler.md]


class Test影片進度必須單調遞增:
    """
    Rule: 影片進度必須單調遞增
    """
    
    def setup_method(self):
        """
        Rule-level Background
        只適用於此 Rule 的測試
        """
        # Given 用戶 "Alice" 在課程 1 的初始進度為 0%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
    
    def test_成功增加影片進度(self):
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
    
    def test_進度不可倒退(self):
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


class Test進度值必須在0到100之間:
    """
    Rule: 進度值必須在 0-100% 之間
    (此 Rule 沒有自己的 Background，不需要 setup_method)
    """
    
    def test_有效範圍內的進度值可以更新(self):
        # Given 用戶 "Alice" 在課程 1 的進度為 50%
        # [事件風暴部位: Aggregate - LessonProgress]
        # [生成參考 Prompt: Aggregate-Given-Handler.md]
        
        # When 用戶 "Alice" 更新課程 1 的影片進度為 75%
        # [事件風暴部位: Command - update_video_progress]
        # [生成參考 Prompt: Command-Handler.md]
        
        # Then 操作成功
        # [生成參考 Prompt: Success-Failure-Handler.md]
```

---

## Execution Steps

1. 讀取 Feature File 的 **Feature-level Background** 區塊（如果存在）
2. 讀取 Feature File 的每個 **Rule**
3. 讀取 Rule 的 **Rule-level Background** 區塊（如果存在）
4. **為每個 Rule 建立 Test Group（測試群組類別）**
5. 在 Test Group 中**建立 Before Each Setup Hook**（置頂）
6. 將 Background 依序寫入 Setup Hook：
   - 先寫 Feature-level Background（如果存在）
   - 再寫 Rule-level Background（如果存在）
   - 使用註解區隔兩個層級
7. 解析 Background 的 Given/And 語句，生成樣板註解
8. 讀取 Rule 下的每個 Example/Scenario
9. 為每個 Example 建立測試方法（放在對應的 Test Group 中）
10. 逐句解析測試方法的 Given/When/Then/And
11. 應用 Decision Tree 識別事件風暴部位
12. 生成註解，包含：
   - 原始 Gherkin 語句
   - 事件風暴部位類型和名稱
   - 對應的 Handler Prompt 檔名
13. 組裝完整測試方法
14. 組裝完整 Test Group（Background setup + 所有測試方法）
15. 輸出測試檔案樣板

---

## Critical Rules

### R1: Rule → Test Group
每個 Gherkin Rule 必須對應一個 Test Group（測試群組類別），同一 Rule 下的所有測試方法放在同一個 Test Group 中。

### R2: Feature-level Background → File-level Setup
Feature-level Background（定義在 Feature 之下）必須使用**測試檔案層級的 setup**（如 pytest 的 `@pytest.fixture(scope="module", autouse=True)`），放在所有 Test Group 之前，所有測試自動共用。

### R3: Rule-level Background → Test Group Setup
Rule-level Background（定義在 Rule 之下）使用 **Test Group 層級的 Before Each Hook**（如 pytest 的 `setup_method`），只出現在對應的 Test Group 中。

### R4: 只輸出註解樣板
不生成任何程式碼，只生成註解和指引。

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
