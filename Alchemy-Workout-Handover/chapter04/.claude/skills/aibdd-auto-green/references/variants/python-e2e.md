# Green Variant: python-e2e

## 測試命令

```bash
# 開發階段：執行特定 Feature 檔案（快速迭代）
behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature

# 開發階段：執行特定 Scenario（最快）
behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature --name "成功增加影片進度"

# 完成階段：執行所有已完成紅燈的測試（總回歸測試）
behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore
```

**為什麼使用 `--tags=~@ignore`？**
- 只執行已完成紅燈實作的 features（已移除 `@ignore` 標籤）
- 避免執行尚未實作的 features 造成混淆
- 確保回歸測試的範圍清晰明確

## 實作模式

### 實作目標

FastAPI Schemas → Services → Controllers → Route 註冊

### 實作順序

根據測試錯誤訊息逐步實作：

1. 執行測試 → `behave ${PY_TEST_FEATURES_DIR}/xxx.feature`
2. 看錯誤訊息（HTTP 404? 500? 400?）
3. 根據錯誤補充最少的程式碼（schemas → services → controllers → 註冊路由）
4. 再次執行測試
5. 循環直到特定測試通過
6. 執行總回歸測試 → `behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore`

### 最小增量範例

```python
# 做太多了（測試沒要求）
@router.post("/lesson-progress/update-video-progress")
def update_video_progress(request):
    validate_inventory()      # 沒測試
    send_email_notification() # 沒測試
    log_audit_trail()        # 沒測試
    return update_progress_logic(request)

# 剛好夠（只實作測試要求的）
@router.post("/lesson-progress/update-video-progress")
def update_video_progress(request):
    return update_progress_logic(request)
```

## 框架 API

### FastAPI Router 建立

```python
# ${PY_API_DIR}/lesson_progress.py
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ${PY_CORE_DIR.replace('/', '.')}.deps import get_db

router = APIRouter()

@router.post("/lesson-progress/update-video-progress")
def update_video_progress(request: UpdateVideoProgressRequest, db: Session = Depends(get_db)):
    # 實作業務邏輯
    pass
```

### 路由註冊

```python
# ${PY_MAIN_FILE}
from ${PY_API_DIR.replace('/', '.')}.lesson_progress import router as lesson_progress_router
app.include_router(lesson_progress_router, prefix="/api/v1")
```

### 檔案建立順序

```
步驟 1: 建立 schemas（如果需要）
→ ${PY_SCHEMAS_DIR}/order.py
→ 定義 Request/Response 的 Pydantic models

步驟 2: 建立 services
→ ${PY_SERVICES_DIR}/order_service.py
→ 實作業務邏輯

步驟 3: 建立 API endpoints
→ ${PY_API_DIR}/orders.py
→ 定義路由和 HTTP 處理

步驟 4: 在 main.py 中註冊路由
→ ${PY_MAIN_FILE}
→ 將 API router 加入 FastAPI app
```

## 常見錯誤修復

### HTTP 404 Not Found
**原因**：API Endpoint 不存在
**修復**：
1. 在 `${PY_API_DIR}/` 中創建 router
2. 在 `${PY_MAIN_FILE}` 中註冊 router

### HTTP 500 Internal Server Error
**原因**：後端程式碼有錯誤
**修復**：
1. 檢查錯誤訊息
2. 修正 Service/Repository 的邏輯

### HTTP 400 Bad Request
**原因**：業務規則驗證失敗
**修復**：
1. 確認業務規則正確實作
2. 調整驗證邏輯

### HTTP 401 Unauthorized
**原因**：JWT Token 驗證失敗
**修復**：
1. 確認 `${PY_CORE_DIR}/deps.py` 中的 `get_current_user_id` 實作正確
2. 確認 JWT 密鑰與測試用的 JwtHelper 一致

## 迭代策略

### 開發循環（快速迭代）

```
1. 執行特定測試 → behave ${PY_TEST_FEATURES_DIR}/xxx.feature
2. 看錯誤訊息 → 理解失敗原因
3. 寫最少的程式碼修正這個錯誤
4. 再次執行特定測試 → behave ${PY_TEST_FEATURES_DIR}/xxx.feature
5. 還有錯誤？回到步驟 2
6. 特定測試通過？進入完成驗證
```

### 完成驗證（回歸測試）

```
7. 執行所有已完成紅燈的測試 → behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore
8. 所有測試通過？完成綠燈！
9. 有測試失敗？回到步驟 2，修復破壞的測試
```

### 範例執行流程

```
開發階段（快速迭代）：
→ behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature
  FAILED: HTTP 404 Not Found

→ 建立 API endpoint
→ behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature
  FAILED: HTTP 500 Internal Server Error

→ 修正 Service 邏輯
→ behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature
  FAILED: HTTP 400 Bad Request (進度不可倒退)

→ 調整業務規則驗證
→ behave ${PY_TEST_FEATURES_DIR}/01-增加影片進度.feature
  PASSED（特定測試通過）

完成驗證（回歸測試）：
→ behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore
  2 features passed, 5 scenarios passed（所有測試通過，真正完成！）
```

### 完成判定標準

```
特定測試通過 → 功能開發完成
                |
         執行總回歸測試
                |
  behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore
                |
   所有已完成紅燈的測試通過
                |
         真正完成綠燈！
```

## Docker / 環境

### 執行前確認

```bash
# 1. 確認 Docker Desktop 是否在運行
docker ps

# 如果未啟動，在 macOS 執行：
open -a Docker

# 2. 確認 Docker Daemon 正常響應
docker info
```

### 常見錯誤訊息與解法

| 錯誤訊息 | 原因 | 解法 |
|---------|------|------|
| `DockerException: Error while fetching server API version` | Docker Desktop 未啟動 | 執行 `open -a Docker`（macOS）或啟動 Docker Desktop |
| `Error response from daemon: pull access denied` | 無法下載 PostgreSQL image | 確認網路連線，或執行 `docker pull postgres:16` |
| `ConnectionRefusedError: [Errno 111] Connection refused` | Testcontainers 初始化失敗 | 確認 Docker Desktop 已啟動，重新執行測試 |
| `testcontainers.core.exceptions.DockerException` | Docker Socket 無法存取 | 確認 `/var/run/docker.sock` 或 `~/.docker/run/docker.sock` 存在 |

### 診斷步驟

```
錯誤 → testcontainers.exceptions.DockerException
  └→ 執行 `docker ps`
       ├→ 成功：Docker 正常，問題在其他地方（查看完整 stack trace）
       └→ 失敗：啟動 Docker Desktop，再重新執行測試
```

### 完成條件

- [ ] 執行特定測試 `behave ${PY_TEST_FEATURES_DIR}/xxx.feature` 通過
- [ ] 執行總回歸測試 `behave ${PY_TEST_FEATURES_DIR}/ --tags=~@ignore` 所有測試通過
- [ ] 沒有破壞既有功能
- [ ] 程式碼簡單直接
- [ ] 未引入任何測試未要求的功能
