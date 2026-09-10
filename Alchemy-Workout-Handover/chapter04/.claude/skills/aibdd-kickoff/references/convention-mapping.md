# Convention 對照表

## 共用參數（所有技術堆疊都包含）

| 參數 | 預設值 |
|------|--------|
| SPECS_ROOT_DIR | specs |
| CLARIFY_DIR | ${SPECS_ROOT_DIR}/clarify |
| MAX_QUESTIONS_PER_ROUND | 10 |
| ACTIVITIES_DIR | ${SPECS_ROOT_DIR}/activities |
| FEATURE_SPECS_DIR | ${SPECS_ROOT_DIR}/features |
| API_SPECS_DIR | ${SPECS_ROOT_DIR} |
| ENTITY_SPECS_DIR | ${SPECS_ROOT_DIR} |

## Python E2E

| 參數 | 預設值 |
|------|--------|
| PY_APP_DIR | app |
| PY_MODELS_DIR | ${PY_APP_DIR}/models |
| PY_REPOSITORIES_DIR | ${PY_APP_DIR}/repositories |
| PY_SERVICES_DIR | ${PY_APP_DIR}/services |
| PY_API_DIR | ${PY_APP_DIR}/api |
| PY_CORE_DIR | ${PY_APP_DIR}/core |
| PY_SCHEMAS_DIR | ${PY_APP_DIR}/schemas |
| PY_MAIN_FILE | ${PY_APP_DIR}/main.py |
| PY_TEST_FEATURES_DIR | tests/features |
| PY_STEPS_DIR | ${PY_TEST_FEATURES_DIR}/steps |
| PY_ENV_FILE | ${PY_TEST_FEATURES_DIR}/environment.py |
| ALEMBIC_VERSIONS_DIR | alembic/versions |

## Python Unit Test

與 Python E2E 相同的路徑，差別在測試策略。產出的 arguments.yml 完全一樣，只是後續呼叫的 automation skill 不同（`python.ut.*` vs `python.e2e.*`）。

## Java E2E

| 參數 | 預設值 |
|------|--------|
| GROUP_ID | com.example |
| ARTIFACT_ID | app |
| BASE_PACKAGE | ${GROUP_ID}.${ARTIFACT_ID} |
| JAVA_APP_DIR | src/main/java/${BASE_PACKAGE_PATH} |
| JAVA_MODEL_DIR | ${JAVA_APP_DIR}/model |
| JAVA_REPOSITORY_DIR | ${JAVA_APP_DIR}/repository |
| JAVA_SERVICE_DIR | ${JAVA_APP_DIR}/service |
| JAVA_CONTROLLER_DIR | ${JAVA_APP_DIR}/controller |
| JAVA_SECURITY_DIR | ${JAVA_APP_DIR}/security |
| JAVA_TEST_DIR | src/test/java/${BASE_PACKAGE_PATH} |
| JAVA_TEST_FEATURES_DIR | src/test/resources/features |
| JAVA_STEPS_DIR | ${JAVA_TEST_DIR}/steps |
| JAVA_CUCUMBER_DIR | ${JAVA_TEST_DIR}/cucumber |
| FLYWAY_MIGRATION_DIR | src/main/resources/db/migration |

其中 `BASE_PACKAGE_PATH` = BASE_PACKAGE 中 `.` 換成 `/`（例：`com.example.app` → `com/example/app`）。

**注意**：Java 的 package 路徑需要額外確認。Q&A 中若選擇 Java，追加一題詢問 base package（預設 `com.example.app`）。

## TypeScript E2E

| 參數 | 預設值 |
|------|--------|
| TS_APP_DIR | src |
| TS_ENTITIES_DIR | ${TS_APP_DIR}/entities |
| TS_MODULES_DIR | ${TS_APP_DIR}/modules |
| TS_MIGRATIONS_DIR | ${TS_APP_DIR}/migrations |
| TS_DATASOURCE_FILE | ${TS_APP_DIR}/data-source.ts |
| TS_TEST_FEATURES_DIR | features |
| TS_STEPS_DIR | ${TS_TEST_FEATURES_DIR}/steps |
| TS_SUPPORT_DIR | ${TS_TEST_FEATURES_DIR}/support |

## Frontend Only

| 參數 | 預設值 |
|------|--------|
| SRC_DIR | src |
| API_SPEC_FILE | ${API_SPECS_DIR}/api.yml |
| ENTITY_SPEC_FILE | ${ENTITY_SPECS_DIR}/erm.dbml |
| TYPES_DIR | ${SRC_DIR}/lib/types |
| API_CLIENT_DIR | ${SRC_DIR}/lib/api |
| MSW_DIR | ${SRC_DIR}/mocks |
| HANDLERS_DIR | ${MSW_DIR}/handlers |
| FRONTEND_FEATURES_DIR | features |
| PAGE_OBJECTS_DIR | page-objects |
| STEPS_DIR | steps |

## arguments.yml 範例（Python E2E）

```yaml
# ── 共用 ──────────────────────────────────────────────

# 所有規格產出物的根目錄
SPECS_ROOT_DIR: specs

# 澄清紀錄目錄（所有 prompt 共用，見 shared/clarify-loop.md）
CLARIFY_DIR: ${SPECS_ROOT_DIR}/clarify

# 每回合最多提問數（Sub-question 不計入）
MAX_QUESTIONS_PER_ROUND: 10

# ── discovery 用 ────────────────────────────────────

# Activity 檔案的存放目錄
ACTIVITIES_DIR: ${SPECS_ROOT_DIR}/activities

# Feature 檔案的存放目錄
FEATURE_SPECS_DIR: ${SPECS_ROOT_DIR}/features

# api.yml 的存放目錄
API_SPECS_DIR: ${SPECS_ROOT_DIR}

# erm.dbml 的存放目錄
ENTITY_SPECS_DIR: ${SPECS_ROOT_DIR}

# ── python automation 共用 ─────────────────────────────

# Python 應用程式根目錄
PY_APP_DIR: app

# ORM Models
PY_MODELS_DIR: ${PY_APP_DIR}/models

# Repository 層
PY_REPOSITORIES_DIR: ${PY_APP_DIR}/repositories

# Service 層
PY_SERVICES_DIR: ${PY_APP_DIR}/services

# API Endpoints（FastAPI routers）
PY_API_DIR: ${PY_APP_DIR}/api

# Core（config, dependencies）
PY_CORE_DIR: ${PY_APP_DIR}/core

# Pydantic Schemas
PY_SCHEMAS_DIR: ${PY_APP_DIR}/schemas

# FastAPI 主程式
PY_MAIN_FILE: ${PY_APP_DIR}/main.py

# Behave 測試 Feature 檔案目錄
PY_TEST_FEATURES_DIR: tests/features

# Step Definitions 目錄
PY_STEPS_DIR: ${PY_TEST_FEATURES_DIR}/steps

# Behave environment.py
PY_ENV_FILE: ${PY_TEST_FEATURES_DIR}/environment.py

# Alembic 遷移目錄
ALEMBIC_VERSIONS_DIR: alembic/versions
```

## Starter Skill 對照表

### 後端 Starter

| 技術堆疊 + 測試策略 | Starter Skill |
|---------------------|---------------|
| Python + E2E Test | `/aibdd-auto-python-e2e-starter` |
| Python + Unit Test | `/aibdd-auto-python-ut-starter` |
| Java + E2E Test | `/aibdd-auto-java-e2e-starter` |
| TypeScript + E2E Test | （尚未建立） |

### 前端 Starter

| Starter Skill |
|---------------|
| `/aibdd-auto-frontend-apifirst-msw-starter` |

前端 starter 永遠顯示，不受 Q1 技術堆疊選擇影響。
specformula Phase 03（Frontend Engineering）需要前端骨架已就位。
