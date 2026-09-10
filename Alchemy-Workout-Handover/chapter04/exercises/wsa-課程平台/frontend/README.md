# WSA 課程平台 — 前端

## 環境準備

```bash
# 安裝依賴
npm install

# 安裝 Playwright 瀏覽器（測試需要）
npx playwright install chromium
```

## 開發

```bash
# 啟動開發伺服器（預設 http://localhost:3000）
npm run dev
```

應用程式在開發模式下會自動啟用 MSW (Mock Service Worker)，攔截所有 API 請求並回傳模擬資料。

## 測試

測試使用 Cucumber + Playwright，**必須先啟動開發伺服器**再跑測試：

```bash
# 終端 1：啟動 dev server
npm run dev

# 終端 2：跑測試
npm test
```

跑單一 feature：

```bash
npx cucumber-js features/products/product-list.feature
```

## 專案結構

```
src/
├── app/                    # Next.js App Router 頁面
│   ├── (protected)/        # 需登入的頁面（含 Sidebar + TopBar）
│   └── layout.tsx          # Root layout（含 MSWProvider）
├── components/             # React 元件
├── lib/
│   ├── api/                # API 客戶端函式（使用 apiClient）
│   └── types/              # Zod schemas + TypeScript 型別
└── mocks/
    ├── browser.ts          # MSW worker 設定
    ├── fixtures.ts         # 模擬資料
    └── handlers/           # MSW request handlers

features/                   # Gherkin feature 檔案
steps/                      # Cucumber step definitions
pages/                      # Page Object（封裝 data-testid 選擇器）
support/                    # 測試基礎建設（hooks, world, helpers）
```

## Pipeline 階段

| Stage | Skill | 產出 |
|-------|-------|------|
| 1 | `msw-api-layer` | Zod schemas, fixtures, MSW handlers, API client |
| 2 | `frontend-gherkin` | 前端 Gherkin features |
| 3 | `test-scaffolding` | Page Objects + Step Definitions |
| 4 | `component-impl` | React 元件 + 頁面路由 |
