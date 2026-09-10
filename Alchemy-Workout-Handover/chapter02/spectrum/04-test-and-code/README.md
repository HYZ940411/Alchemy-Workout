# Test Code：BDD Step Definitions (Python)

## 翻譯鏈位置

```
   第 1-4 層：Vision → Goals → Capabilities → Features
   第 5-7 層：User Story → AC → Examples
   Event Storming 模型
   DSL Level
   ISA Level
👉 Test Code（BDD Step Definitions）← 你在這裡
```

## ✅ 重構完成 - 會尖叫的測試架構

本目錄採用「會尖叫的測試架構」（Screaming Architecture）：

### 架構特色

1. **每個 step 一個檔案** - 測試意圖一目了然
2. **按 Gherkin 關鍵字分類** - given/, when/, then/, common/
3. **基礎建設完全抽離** - 所有輔助工具在 helpers/
4. **步驟定義極簡** - 只保留測試語意，無技術細節

### 目錄結構

```
04-test-code/
├── features/               # Feature 檔案
│   ├── 01-增加影片進度.feature
│   ├── 02-提交問卷表單.feature
│   ├── 03-提交挑戰題作業.feature
│   └── 04-交付課程.feature
├── steps/
│   ├── given/             # Given steps（資料準備）
│   │   ├── 準備一個課程_with_table.py
│   │   ├── 準備一個用戶_with_table.py
│   │   ├── 準備一個課程進度_with_table.py
│   │   ├── 課程_的狀態為.py
│   │   └── 學生_經驗值為.py
│   ├── when/              # When steps（執行操作）
│   │   ├── 更新課程影片進度_call_table.py
│   │   ├── 提交問卷表單_call_table.py
│   │   ├── 提交挑戰題作業_call_table.py
│   │   ├── 提交批改結果_call_table.py
│   │   ├── 交付課程_call_table.py
│   │   ├── 用戶訂閱旅程_call_table.py
│   │   ├── 學生_將課程_的影片進度更新為.py
│   │   └── 學生_嘗試將課程_的影片進度更新為.py
│   ├── then/              # Then steps（驗證結果）
│   │   ├── 驗證存在一個課程進度_with_table.py
│   │   ├── 驗證存在一個用戶_with_table.py
│   │   ├── 課程_的狀態更新為.py
│   │   ├── 課程_的狀態更新為_學生_的經驗值為_等級為_收到升級通知.py
│   │   └── 操作失敗_課程_的狀態保持.py
│   ├── common/            # 通用 steps
│   │   ├── 操作失敗.py
│   │   └── 回應_with_table.py
│   └── helpers/           # 基礎建設（完全抽離）
│       ├── datatable_parser.py
│       ├── variable_resolver.py
│       ├── constraint_validator.py
│       ├── response_validator.py
│       ├── database_helper.py
│       └── api_helper.py
├── support/               # 核心支援模組
│   ├── scenario_context.py
│   ├── assert_helper.py
│   ├── models.py
│   ├── database.py
│   ├── api_client.py
│   └── auth.py
└── environment.py
```

### 架構優勢

#### 1. 會尖叫（Screaming）
- 看檔案名就知道測試什麼
- 看目錄結構就知道系統行為
- 測試意圖清晰表達

#### 2. 極簡的 Step 定義
每個 step 只關注測試語意：

```python
# steps/given/準備一個課程_with_table.py
@step('準備一個課程, with table:')
def prepare_lesson(context):
    """準備課程測試資料"""
    session = context.db.get_session()
    
    rows = parse_datatable(context.table, context)
    for lesson_data, _ in rows:
        create_lesson(session, lesson_data)
    
    session.commit()
```

#### 3. 中文檔案名稱
所有 step definition 檔案都使用中文+底線命名，讓測試意圖一目了然：
- `準備一個課程_with_table.py` - 看檔名就知道在測試什麼
- `更新課程影片進度_call_table.py` - 清楚表達業務操作
- `驗證存在一個課程進度_with_table.py` - 明確的驗證目的

#### 4. 基礎建設分離
所有技術細節都在 helpers/：
- `datatable_parser.py` - DataTable 解析（var-system）
- `variable_resolver.py` - 變數引用和儲存
- `constraint_validator.py` - 約束斷言驗證
- `response_validator.py` - Response 驗證邏輯
- `database_helper.py` - 資料庫操作封裝
- `api_helper.py` - API 呼叫封裝

### 快速開始

```bash
# 安裝依賴
pip install -r requirements.txt

# 執行所有測試
behave

# 執行特定 feature
behave features/01-增加影片進度.feature
```

### 詳細說明

請參閱 [TEST-README.md](./TEST-README.md) 了解：
- 完整的使用指南
- Var-system 變數系統說明
- 約束斷言系統使用方法
- 開發指南和疑難排解

### 新增 Step 的方式

1. **決定類別**：given/when/then/common
2. **建立檔案**：`steps/{category}/{中文step名稱_用底線連接}.py`
3. **使用 @step decorator**：支援所有關鍵字
4. **保持極簡**：只寫測試語意，技術細節抽到 helpers/

範例：

```python
# steps/when/新的操作_call_table.py
"""
When: (UID={uid}) 新的操作, call table:
"""
from behave import step
from steps.helpers.datatable_parser import parse_datatable
from steps.helpers.variable_resolver import resolve_uid
from steps.helpers.api_helper import call_new_api

@step('(UID={uid}) 新的操作, call table:')
def new_action(context, uid):
    """新的操作說明"""
    user_id = resolve_uid(uid, context)
    rows = parse_datatable(context.table, context)
    data, _ = rows[0]
    
    response = call_new_api(context.api_client, user_id, data)
    context.scenario_context.set_response(response)
```

**檔案命名規則：**
- Gherkin step: `準備一個課程, with table:` → 檔名: `準備一個課程_with_table.py`
- Gherkin step: `學生 "Alice" 將課程 1 的影片進度更新為 80` → 檔名: `學生_將課程_的影片進度更新為.py`
- 用底線 `_` 連接中文關鍵字，省略參數部分（如引號、數字、變數）

### 為什麼這樣設計？

| 傳統設計 | 會尖叫的架構 |
|---------|------------|
| 一個檔案包含所有 steps | 每個 step 一個檔案 |
| 技術細節與測試語意混在一起 | 完全分離 |
| 難以找到特定 step | 目錄結構就是導航 |
| 修改影響範圍大 | 修改影響範圍小 |
| 不易理解系統行為 | 一目了然 |

這是真正的「測試即文檔」- 光看檔案結構就知道系統做什麼！
