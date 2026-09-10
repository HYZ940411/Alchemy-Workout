# Green Variant: python-ut

## 測試命令

```bash
# 開發階段：執行特定 Feature 檔案
behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature

# 開發階段：執行特定 Scenario
behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature --name "成功增加影片進度"

# 完成階段：執行所有已完成紅燈的測試（總回歸測試）
behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore
```

## 實作模式

### 實作目標

FakeRepository 方法體 → Service 業務邏輯

### 實作順序

根據測試錯誤訊息逐步實作：

1. 執行測試 → `behave ${PY_TEST_FEATURES_DIR}/xxx.feature`
2. 看錯誤訊息（NotImplementedError? AssertionError?）
3. 根據錯誤補充最少的程式碼
4. 再次執行測試
5. 循環直到通過

### 最小增量範例

```python
# 做太多了（測試沒要求）
def update_video_progress(self, user_id, lesson_id, progress):
    self._validate_user(user_id)           # 沒測試
    self._send_notification(user_id)        # 沒測試
    self._update_progress(user_id, lesson_id, progress)

# 剛好夠
def update_video_progress(self, user_id, lesson_id, progress):
    self._update_progress(user_id, lesson_id, progress)
```

## 框架 API

### FakeRepository 實作（綠燈）

紅燈階段的 `raise NotImplementedError` → 綠燈改為 dict-based 實作：

```python
# ${PY_REPOSITORIES_DIR}/lesson_progress_repository.py
from typing import Optional
from app.models.lesson_progress import LessonProgress

class LessonProgressRepository:
    def __init__(self):
        self._data = {}  # Key: (user_id, lesson_id)

    def save(self, lesson_progress: LessonProgress) -> None:
        key = (lesson_progress.user_id, lesson_progress.lesson_id)
        self._data[key] = lesson_progress

    def find(self, user_id: str, lesson_id: int) -> Optional[LessonProgress]:
        return self._data.get((user_id, lesson_id))
```

### Service 實作（綠燈）

紅燈階段的 `raise NotImplementedError` → 綠燈實作業務邏輯：

```python
# ${PY_SERVICES_DIR}/lesson_service.py
from app.exceptions import BusinessError

class LessonService:
    def __init__(self, lesson_progress_repository):
        self.lesson_progress_repository = lesson_progress_repository

    def update_video_progress(self, user_id: str, lesson_id: int, progress: int) -> None:
        existing = self.lesson_progress_repository.find(user_id, lesson_id)
        if existing and progress <= existing.progress:
            raise BusinessError("進度不可倒退")
        # ... 實作更新邏輯
```

## 迭代策略

### 開發循環

```
1. 執行測試 → behave xxx.feature
2. 看到 NotImplementedError → 實作對應的 FakeRepo/Service 方法
3. 看到 AssertionError → 修正業務邏輯
4. 通過 → 下一個 Scenario
```

### 常見失敗模式

| 失敗模式 | 原因 | 修復 |
|---------|------|------|
| NotImplementedError | FakeRepo/Service 方法未實作 | 實作方法體 |
| AssertionError | 業務邏輯不正確 | 修正邏輯 |
| KeyError (context.ids) | Given 未建立前置資料 | 檢查 Given 步驟 |
| AttributeError | context.repos/services 缺少成員 | 更新 environment.py |

## Docker / 環境

**不需要 Docker / Testcontainers / 真實 DB。**

所有資料儲存在 FakeRepository 的 dict 中，每個 Scenario 前重新初始化。

## 完成條件

- [ ] 所有 FakeRepository 方法體已實作（dict-based）
- [ ] 所有 Service 業務邏輯已實作
- [ ] 測試命令全數通過（零失敗）
- [ ] 未引入任何測試未要求的功能
