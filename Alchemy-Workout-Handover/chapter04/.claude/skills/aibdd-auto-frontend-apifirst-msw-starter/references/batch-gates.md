# Batch Gates — Step 4 驗證清單

每個 Batch 寫入完成後，執行對應的 Gate。Gate 失敗時**立即修復**，不繼續下一個 Batch。

## Gate A — 基礎建設

- [ ] `npm install` 成功，無 peer dependency 衝突
- [ ] `next.config.mjs` 包含 `rewrites()` 函式，source 為 `/api/:path*`
- [ ] `.env.development` 與 `.env.example` 皆包含 `BACKEND_URL`
- [ ] 無殘留 `{{PLACEHOLDER}}`

## Gate B — App Shell

- [ ] `npm run dev` 能啟動（port 3000 可連線）
- [ ] 訪問 `/` 產生 redirect（307）到目標頁面
- [ ] `layout.tsx` 包裹 `MSWProvider`

## Gate C — 共用元件

- [ ] 所有元件檔案的 import path 正確（相對路徑或 `@/` alias）
- [ ] `tsc --noEmit` 針對這些元件無型別錯誤

## Gate D — API Client + Types

- [ ] `client.ts` 的 `BASE_URL` 讀取自 `process.env.NEXT_PUBLIC_API_BASE_URL`
- [ ] `apiClient` 函式從 `api/index.ts` 正確 re-export
- [ ] Mock 開啟時 MSW 攔截；Mock 關閉時 rewrite proxy 到 `BACKEND_URL`

## Gate E — MSW 骨架

- [ ] `browser.ts` export `initMocks` 函式
- [ ] `handlers/index.ts` export 空的 `handlers` 陣列（由後續 worker 填入）
- [ ] `MSWProvider` 的 dynamic import path 與 `browser.ts` 位置一致

## Gate F — 測試骨架

- [ ] `cucumber.js` 的 paths、import 設定指向正確目錄
- [ ] `support/world.ts` 能被 cucumber 載入
- [ ] `npx cucumber-js --dry-run` 不報錯（允許 0 scenarios）
