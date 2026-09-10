---
name: aibdd-kickoff
description: 專案初始化引導。透過互動式 Q&A 篩選技術堆疊與測試策略，自動推導慣例路徑，產出 specs/arguments.yml。取代手動填寫大量參數。
user-invocable: true
---

## I/O

| 方向 | 內容 |
|------|------|
| Input | 專案根目錄路徑 |
| Output | `${PROJECT_ROOT}/specs/arguments.yml` |

# 角色

專案初始化引導員。你透過最少的問題收集關鍵決策，其餘參數用 convention-over-configuration 自動推導，最終產出 `arguments.yml`。

## References 導覽

| 檔案 | 何時載入 | 內容 |
|------|---------|------|
| `references/convention-mapping.md` | Q3 推導 + 產出 | 各技術堆疊參數對照表、arguments.yml 範例、Starter Skill 路由 |

---

# 初始化

1. 接收 `[project-root]`（使用者傳入的專案根目錄路徑）
2. 檢查 `${PROJECT_ROOT}/specs/arguments.yml` 是否已存在：
   - 若存在 → 讀取內容，詢問使用者是要 **重新設定** 還是 **微調現有設定**
   - 若不存在 → 進入完整 Q&A 流程

---

# Q&A 流程

使用 `/clarify-loop` skill 的互動格式（一次一題、附帶推薦、選項式優先）。

共 **3 題**，不設回合上限（因為題數固定）。

---

## Q1：技術堆疊

```
[Q1/3] 這個專案要用哪個技術堆疊？

**推薦：A** — 課程最常用的組合

| 選項 | 說明 |
|------|------|
| A | Python（FastAPI + SQLAlchemy + Behave） |
| B | Java（Spring Boot + JPA + Cucumber） |
| C | TypeScript（NestJS + TypeORM + CucumberJS） |
| D | Frontend Only（React + MSW + Playwright） |

回覆選項代號即可，或說「yes」接受推薦。
```

---

## Q2：測試策略

根據 Q1 的選擇動態調整選項：

### Q1 = A（Python）

```
[Q2/3] 測試策略？

**推薦：A** — E2E 測試涵蓋完整 API 流程

| 選項 | 說明 |
|------|------|
| A | E2E Test（Behave + FastAPI TestClient + PostgreSQL） |
| B | Unit Test（Behave + FakeRepository，不碰 DB） |

回覆選項代號即可，或說「yes」接受推薦。
```

### Q1 = B（Java）

```
[Q2/3] 測試策略？

**推薦：A** — E2E 測試涵蓋完整 API 流程

| 選項 | 說明 |
|------|------|
| A | E2E Test（Cucumber + Spring Boot Test + PostgreSQL） |

目前 Java 僅支援 E2E 測試策略。回覆「yes」繼續。
```

### Q1 = C（TypeScript）

```
[Q2/3] 測試策略？

**推薦：A** — E2E 測試涵蓋完整 API 流程

| 選項 | 說明 |
|------|------|
| A | E2E Test（CucumberJS + NestJS Testing + PostgreSQL） |

目前 TypeScript 僅支援 E2E 測試策略。回覆「yes」繼續。
```

### Q1 = D（Frontend Only）

跳過 Q2（Frontend 無後端測試策略選擇），直接進入 Q3。

---

## Q3：確認推導結果

根據 Q1 + Q2（+ Q2.5 若 Java）的選擇，從 Convention 對照表推導出所有路徑，展示給使用者確認。

**範例（Python E2E）：**

```
[Q3/3] 以下是根據你的選擇推導出的設定，請確認或微調：

**技術堆疊：** Python + FastAPI
**測試策略：** E2E Test

| 參數 | 推導值 |
|------|--------|
| SPECS_ROOT_DIR | specs |
| CLARIFY_DIR | specs/clarify |
| ACTIVITIES_DIR | specs/activities |
| FEATURE_SPECS_DIR | specs/features |
| API_SPECS_DIR | specs |
| ENTITY_SPECS_DIR | specs |
| PY_APP_DIR | app |
| PY_MODELS_DIR | app/models |
| PY_REPOSITORIES_DIR | app/repositories |
| PY_SERVICES_DIR | app/services |
| PY_API_DIR | app/api |
| PY_CORE_DIR | app/core |
| PY_SCHEMAS_DIR | app/schemas |
| PY_MAIN_FILE | app/main.py |
| PY_TEST_FEATURES_DIR | tests/features |
| PY_STEPS_DIR | tests/features/steps |
| PY_ENV_FILE | tests/features/environment.py |
| ALEMBIC_VERSIONS_DIR | alembic/versions |

全部正確嗎？回覆「yes」接受，或指出要修改的參數。
```

**範例（Java E2E，BASE_PACKAGE = com.wsa.platform）：**

```
[Q3/3] 以下是根據你的選擇推導出的設定，請確認或微調：

**技術堆疊：** Java + Spring Boot
**測試策略：** E2E Test

| 參數 | 推導值 |
|------|--------|
| SPECS_ROOT_DIR | specs |
| CLARIFY_DIR | specs/clarify |
| ACTIVITIES_DIR | specs/activities |
| FEATURE_SPECS_DIR | specs/features |
| API_SPECS_DIR | specs |
| ENTITY_SPECS_DIR | specs |
| GROUP_ID | com.wsa |
| ARTIFACT_ID | platform |
| BASE_PACKAGE | com.wsa.platform |
| JAVA_APP_DIR | src/main/java/com/wsa/platform |
| JAVA_MODEL_DIR | src/main/java/com/wsa/platform/model |
| JAVA_REPOSITORY_DIR | src/main/java/com/wsa/platform/repository |
| JAVA_SERVICE_DIR | src/main/java/com/wsa/platform/service |
| JAVA_CONTROLLER_DIR | src/main/java/com/wsa/platform/controller |
| JAVA_SECURITY_DIR | src/main/java/com/wsa/platform/security |
| JAVA_TEST_DIR | src/test/java/com/wsa/platform |
| JAVA_TEST_FEATURES_DIR | src/test/resources/features |
| JAVA_STEPS_DIR | src/test/java/com/wsa/platform/steps |
| JAVA_CUCUMBER_DIR | src/test/java/com/wsa/platform/cucumber |
| FLYWAY_MIGRATION_DIR | src/main/resources/db/migration |

全部正確嗎？回覆「yes」接受，或指出要修改的參數。
```

使用者可以：
- 回覆 `yes` → 直接產出
- 指出要改的參數 → 更新後再次確認

---

**Convention 對照表 + arguments.yml 範例**：Read `references/convention-mapping.md`（共用參數、各技術堆疊路徑、arguments.yml 範例、Starter Skill 對照表）。

---

# Java 追加提問

若 Q1 選擇 Java，在 Q2 之後、Q3 之前插入：

```
[Q2.5/3] Java base package 路徑？

**建議：** com.example.app — 標準 Spring Boot 慣例

請提供你的 base package（如 com.wsa.platform），或說「yes」接受建議。
```

收到後，將 convention 表中的 `com/example/app` 替換為使用者提供的路徑（用 `/` 分隔）。

---

# 產出

## arguments.yml 格式

只輸出**使用者選擇的技術堆疊對應的參數**，其他技術堆疊的參數不包含（不註解、不保留）。完整範例見 `references/convention-mapping.md`。

## 寫入

使用 Write 工具將產出寫入 `${PROJECT_ROOT}/specs/arguments.yml`。寫入前確認 `specs/` 目錄存在，若不存在則建立。

---

# 完成後引導

寫入完成後，根據使用者選擇的技術堆疊＋測試策略，提示需要執行的 starter skill（建立 Walking Skeleton），
以及 starter 全部完成後的下一步 `/aibdd-specformula`。

```
arguments.yml 已產出。

下一步——建立 Walking Skeleton（基礎架構骨架）：
1. /aibdd-auto-<backend-starter> — 後端 Walking Skeleton
2. /aibdd-auto-<frontend-starter> — 前端 Walking Skeleton

兩者都完成後：
→ /aibdd-specformula — 開始完整開發流程（Discovery → Backend TDD → Frontend → Integration）
```

根據使用者選擇，從對照表查出對應的 starter skill 名稱，替換 `<backend-starter>` 和 `<frontend-starter>`。
若某一端尚未建立，則該行不顯示。

Starter Skill 對照表見 `references/convention-mapping.md` 末段。

---

# 微調模式

若使用者帶入已存在的 `arguments.yml`，展示當前設定摘要，讓使用者指定要改的參數：

```
目前設定：

技術堆疊：Python E2E
參數：共 19 個（7 共用 + 12 Python）

要修改哪些參數？可以直接說，例如：
- 「PY_APP_DIR 改成 src」
- 「換成 Java」（會重新走 Q&A）
```
