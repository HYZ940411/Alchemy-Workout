---
name: aibdd-auto-frontend-apifirst-msw-starter
description: Frontend API-First Walking Skeleton 初始化。從 templates/ 讀取所有樣板檔案，填入專案參數後輸出到專案目錄，建立 Next.js 14 + MSW + Cucumber + Playwright 的前端骨架。
user-invocable: true
---

## I/O

| 方向 | 內容 |
|------|------|
| Input | 專案根目錄路徑 + `arguments.yml` 參數 |
| Output | 完整的 Frontend Walking Skeleton（可直接 `npm install` + `npm run dev`） |

# 角色

Walking Skeleton 建構器。你從 templates/ 讀取樣板，替換 placeholder，寫入專案目錄。

---

# Placeholder 說明

| Placeholder | 來源 | 說明 | 範例 |
|-------------|------|------|------|
| `{{PROJECT_NAME}}` | 詢問使用者 | 專案顯示名稱 | `課程平台` |
| `{{PROJECT_SLUG}}` | 從 PROJECT_NAME 推導 | URL-safe slug | `walking-skeleton` |
| `{{SRC_DIR}}` | arguments.yml | 前端原始碼根目錄 | `src` |
| `{{TYPES_DIR}}` | arguments.yml | Zod schemas + 型別目錄 | `src/lib/types` |
| `{{API_CLIENT_DIR}}` | arguments.yml | API 客戶端函式目錄 | `src/lib/api` |
| `{{MSW_DIR}}` | arguments.yml | MSW mock 根目錄 | `src/mocks` |
| `{{HANDLERS_DIR}}` | arguments.yml | MSW handlers 目錄 | `src/mocks/handlers` |
| `{{FRONTEND_FEATURES_DIR}}` | arguments.yml | Cucumber features 目錄 | `features` |
| `{{PAGE_OBJECTS_DIR}}` | arguments.yml | Page Object 目錄 | `page-objects` |
| `{{STEPS_DIR}}` | arguments.yml | Step Definitions 目錄 | `steps` |

---

# 執行流程

## Step 1：收集參數

1. 讀取 `${PROJECT_ROOT}/specs/arguments.yml`（若不存在，讀取上層目錄的 `specs/arguments.yml`）
2. 詢問使用者：PROJECT_NAME
3. 推導：PROJECT_SLUG（kebab-case，預設 `walking-skeleton`）

## Step 2：建立目錄結構

```
${PROJECT_ROOT}/
├── public/
├── ${SRC_DIR}/
│   ├── app/
│   │   ├── (protected)/
│   │   └── (public)/
│   ├── components/
│   ├── lib/
│   │   ├── api/
│   │   └── types/
│   └── mocks/
│       └── handlers/
├── ${FRONTEND_FEATURES_DIR}/          # Cucumber feature files（由後續 worker 填入）
├── ${PAGE_OBJECTS_DIR}/               # Page Objects（由後續 worker 填入）
├── ${STEPS_DIR}/                      # Step Definitions（由後續 worker 填入）
├── support/                           # Cucumber hooks + world + helpers
└── specs/
    ├── activities/
    ├── features/
    └── clarify/
```

## Step 3：初始化 MSW Service Worker

在目錄結構建立完成後，執行以下命令產生 MSW service worker：

```bash
cd ${PROJECT_ROOT} && npx msw init public/ --save
```

> 注意：此命令會在 `public/` 目錄下產生 `mockServiceWorker.js`，這是 MSW 在瀏覽器端攔截請求的必要檔案。

## Step 4：分批寫入 templates

按 Batch A–F 順序寫入，每批完成後執行對應的 Gate 驗證。
詳見 [references/batch-gates.md](references/batch-gates.md)。

### Batch A — 基礎建設

| Template 檔案 | 輸出路徑 |
|---------------|----------|
| [templates/package.json](templates/package.json) | `package.json` |
| [templates/tsconfig.json](templates/tsconfig.json) | `tsconfig.json` |
| [templates/tsconfig.test.json](templates/tsconfig.test.json) | `tsconfig.test.json` |
| [templates/next.config.mjs](templates/next.config.mjs) | `next.config.mjs` |
| [templates/cucumber.js](templates/cucumber.js) | `cucumber.js` |
| [templates/env.development](templates/env.development) | `.env.development` |
| [templates/env.example](templates/env.example) | `.env.example` |

**Gate A**: `npm install` 成功；`next.config.mjs` 含 `rewrites` 且 `BACKEND_URL` 存在於 `.env.*`

### Batch B — App Shell

| Template 檔案 | 輸出路徑 |
|---------------|----------|
| [templates/src__app__layout.tsx](templates/src__app__layout.tsx) | `${SRC_DIR}/app/layout.tsx` |
| [templates/src__app__page.tsx](templates/src__app__page.tsx) | `${SRC_DIR}/app/page.tsx` |
| [templates/src__app__globals.css](templates/src__app__globals.css) | `${SRC_DIR}/app/globals.css` |
| [templates/src__app__protected__layout.tsx](templates/src__app__protected__layout.tsx) | `${SRC_DIR}/app/(protected)/layout.tsx` |

**Gate B**: `npm run dev` 能啟動；`/` redirect 到目標頁面

### Batch C — 共用元件

| Template 檔案 | 輸出路徑 |
|---------------|----------|
| [templates/src__components__MSWProvider.tsx](templates/src__components__MSWProvider.tsx) | `${SRC_DIR}/components/MSWProvider.tsx` |
| [templates/src__components__Sidebar.tsx](templates/src__components__Sidebar.tsx) | `${SRC_DIR}/components/Sidebar.tsx` |
| [templates/src__components__TopBar.tsx](templates/src__components__TopBar.tsx) | `${SRC_DIR}/components/TopBar.tsx` |
| [templates/src__components__Toast.tsx](templates/src__components__Toast.tsx) | `${SRC_DIR}/components/Toast.tsx` |

**Gate C**: `tsc --noEmit` 無 import 錯誤

### Batch D — API Client + Types

| Template 檔案 | 輸出路徑 |
|---------------|----------|
| [templates/src__lib__api__client.ts](templates/src__lib__api__client.ts) | `${API_CLIENT_DIR}/client.ts` |
| [templates/src__lib__api__index.ts](templates/src__lib__api__index.ts) | `${API_CLIENT_DIR}/index.ts` |
| [templates/src__lib__types__index.ts](templates/src__lib__types__index.ts) | `${TYPES_DIR}/index.ts` |

**Gate D**: `BASE_URL` 讀取自 `NEXT_PUBLIC_API_BASE_URL`；`apiClient` 可被其他模組 import

### Batch E — MSW 骨架

| Template 檔案 | 輸出路徑 |
|---------------|----------|
| [templates/src__mocks__browser.ts](templates/src__mocks__browser.ts) | `${MSW_DIR}/browser.ts` |
| [templates/src__mocks__fixtures.ts](templates/src__mocks__fixtures.ts) | `${MSW_DIR}/fixtures.ts` |
| [templates/src__mocks__handlers__index.ts](templates/src__mocks__handlers__index.ts) | `${HANDLERS_DIR}/index.ts` |

**Gate E**: `MSWProvider` 能 dynamic import `browser.ts` 無錯誤

### Batch F — 測試骨架

| Template 檔案 | 輸出路徑 |
|---------------|----------|
| [templates/support__hooks.ts](templates/support__hooks.ts) | `support/hooks.ts` |
| [templates/support__world.ts](templates/support__world.ts) | `support/world.ts` |
| [templates/support__route-helpers.ts](templates/support__route-helpers.ts) | `support/route-helpers.ts` |
| [templates/support__parse-helpers.ts](templates/support__parse-helpers.ts) | `support/parse-helpers.ts` |

**Gate F**: `npx cucumber-js --dry-run` 不報錯

## Step 5：建立空 .gitkeep

- `${SRC_DIR}/app/(public)/.gitkeep`
- `${FRONTEND_FEATURES_DIR}/.gitkeep`
- `${PAGE_OBJECTS_DIR}/.gitkeep`
- `${STEPS_DIR}/.gitkeep`

## Step 6：驗證

確認所有檔案已寫入、無殘留 `{{PLACEHOLDER}}`。

---

# 技術棧說明

| 項目 | 技術 | 版本 |
|------|------|------|
| Framework | Next.js | 14.2.x |
| Runtime | React | 18.x |
| Language | TypeScript | 5.x |
| Mocking | MSW (Mock Service Worker) | 2.x |
| Validation | Zod | 3.x |
| E2E Testing | Playwright | 1.x |
| BDD Testing | Cucumber.js | 11.x |
| Node.js | | 20+ |

---

# 與後端 Walking Skeleton 的差異

| 項目 | Backend (Python E2E) | Frontend (API-First MSW) |
|------|---------------------|--------------------------|
| DB | PostgreSQL（Testcontainers） | 無（MSW mock） |
| HTTP | FastAPI TestClient | Playwright + MSW |
| 測試框架 | Behave | Cucumber.js |
| 型別 | Pydantic / dataclass | Zod schemas |
| Mock 策略 | FakeRepository / DB rollback | MSW handlers + fixtures |
| 瀏覽器 | 無 | Playwright (headless Chromium) |
| 認證 | JWT（PyJWT） | Cookie-based auth token |

---

# 安全規則

- **不覆蓋已存在的檔案**。
- **不建立 feature-specific 的程式碼**（如具體頁面、具體 step definition）。
- **不執行 npm install**（僅提示使用者）。
- **不產生任何 Zod schema、fixture 或 handler 內容**（那是 `msw-api-layer` worker 的工作）。

---

# 完成後輸出

列出所有產出的檔案路徑，不加任何額外引導或下一步建議。
