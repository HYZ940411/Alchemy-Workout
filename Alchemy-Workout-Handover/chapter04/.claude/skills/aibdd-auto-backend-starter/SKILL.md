---
name: aibdd-auto-backend-starter
description: >
  後端專案環境初始化（script-driven）。用 AskUserQuestion 詢問後端專案目錄，
  再執行 generate-skeleton.py 從 templates/ 一次性建立骨架。
  支援 Python E2E / Java E2E / Python UT 變體。
user-invocable: true
---

# 後端專案環境初始化

Script-driven 骨架產生器。一行指令建出完整後端專案結構。

## 變體路由

讀取 `arguments.yml`，從 key prefix 自動偵測技術棧（如 `PY_` → python-e2e、`JAVA_` → java-e2e）。
偵測不到 → 用 AskUserQuestion 詢問使用者技術棧。

## 執行流程

### Step 0：詢問後端專案目錄

使用 **AskUserQuestion** 詢問：

> 後端專案要建立在哪個目錄？（預設：目前工作目錄）

取得 `PROJECT_DIR` 後繼續。

### Step 1：詢問專案名稱

使用 **AskUserQuestion** 詢問：

> 專案名稱？（用於 pyproject.toml / pom.xml 的 name + Docker container 命名）

取得 `PROJECT_NAME` 後繼續。

### Step 2：執行腳本

```bash
uv run .claude/skills/aibdd-auto-backend-starter/scripts/generate-skeleton.py \
  --project-dir "${PROJECT_DIR}" \
  --project-name "${PROJECT_NAME}" \
  --variant "${VARIANT}" \
  --arguments "${ARGUMENTS_YML_PATH}"
```

腳本自動：讀 arguments.yml → 對 `templates/{variant}/` 做 `${VAR}` 替換 → 寫入目標目錄。

### Step 3：安裝依賴

依偵測到的技術棧，用該語言的套件管理工具安裝 `${PROJECT_DIR}` 中的依賴。

### Step 4：移動規格目錄並更新路徑

1. 將 `${FEATURE_SPECS_DIR}/` **整個目錄**移動到 `${PROJECT_DIR}` 內的測試目錄（含 .feature、句型.md、系統抽象.md 等所有分析產物），保留子目錄結構。
2. 更新 `arguments.yml` 中的相關路徑變數，指向移動後的位置（以 `${PROJECT_DIR}` 為基礎）。
3. 告知使用者：規格目錄已移入後端專案目錄，arguments.yml 已更新。

### Step 5：驗證

用該測試框架的 dry-run 模式執行，確認能找到所有 feature 檔案且無 import 錯誤。

## Template 命名慣例

`templates/{variant}/` 中的檔案名用 `__` 表示目錄分隔：

- `app__main.py` → `app/main.py`
- `tests__features__environment.py` → `tests/features/environment.py`
- `app____init__.py` → `app/__init__.py`（四底線 = 目錄 + __init__）

## 完成條件

- [ ] 目錄結構完整（腳本回報 N files written）
- [ ] 依賴安裝成功
- [ ] 測試框架 dry-run 可執行（找到 features，無 import 錯誤）

## 安全規則

- 不覆蓋已存在的檔案（腳本 SKIP 並回報）
- 不建立 feature-specific 程式碼（models、services、endpoints、step definitions）
