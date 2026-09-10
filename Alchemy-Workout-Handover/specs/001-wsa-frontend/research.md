# Research: WSA 課程平台前端

## R1: YouTube IFrame API 整合進度追蹤

**Decision**: 使用 YouTube IFrame Player API 監聽影片播放事件，透過 `onStateChange` 和定時輪詢 `getCurrentTime()` / `getDuration()` 計算進度百分比，達到閾值時呼叫後端 API 更新進度。

**Rationale**: YouTube IFrame API 是官方推薦的嵌入方式，支援跨域通訊、事件監聽和播放控制。可以精確取得播放位置和影片總長度來計算百分比進度。

**Alternatives considered**:
- 原生 HTML5 video + 自託管影片：需要影片儲存和串流基礎設施，不適合教學示範
- Video.js 等第三方播放器：增加不必要的複雜度，YouTube iframe 已足夠
- 模擬進度滑桿：使用者明確要求嵌入真實播放器

## R2: Bearer Token 認證策略

**Decision**: 前端使用簡化的 JWT token，token payload 包含 `username` 欄位。Mock 模式下由前端自行生成 token（使用固定 secret），production 模式下由後端 `/auth/login` endpoint 簽發（需後端擴充）。

**Rationale**: API spec 已統一使用 `BearerAuth` security scheme。教學示範場景下，mock 模式需要前端能自行生成有效 token 來模擬已登入狀態。JWT 格式讓前端可以解碼 payload 取得 username 而不需額外 API 呼叫。

**Alternatives considered**:
- Opaque token + /me endpoint：需要額外 API 呼叫取得用戶資訊，mock 模式較複雜
- Session-based auth：不符合 API spec 定義的 Bearer Token 方式
- 硬編碼 token string：無法動態切換用戶

## R3: Mock Data 策略

**Decision**: 從 11 個 feature files 的 Gherkin table 中提取所有測試資料，轉換為 TypeScript 靜態常數。Mock handlers 實作與真實 API 相同的 interface，在記憶體中維護狀態（進度更新、訂單建立等操作會修改記憶體狀態）。

**Rationale**: Feature files 的 Background 區段定義了完整的測試資料集（旅程、用戶、角色、課程、商品、訂單、折扣券等）。使用相同資料確保前端行為與 BDD 測試一致，也讓學生可以看到 feature file 中的資料如何直接驅動前端展示。

**Alternatives considered**:
- MSW (Mock Service Worker)：增加依賴，教學示範中直接的 mock function 更直觀
- JSON Server：需要獨立服務，增加部署複雜度
- 後端 mock endpoint：違反 API-first 前端可獨立開發的原則

## R4: Docker Compose Profiles 配置

**Decision**: 在 `exercises/wsa-課程平台/docker-compose.yml` 中定義 frontend、database 為 default services，java-backend 和 python-backend 各自使用 `java` 和 `python` profile。啟動方式：`docker compose --profile java up` 或 `docker compose --profile python up`。

**Rationale**: Docker Compose profiles 是原生功能，允許在同一個 compose 檔案中定義可選服務。前端和資料庫是必要服務（default），後端二選一透過 profile 控制。這最清楚地展示「後端可替換」的概念。

**Alternatives considered**:
- 多個 compose 檔案：增加維護負擔，服務定義可能不同步
- compose override 檔案：語意不如 profiles 清楚
- 環境變數控制服務啟動：compose 層級不支援條件啟動

## R5: Next.js App Router vs Pages Router

**Decision**: 使用 App Router（`src/app/` 目錄結構），搭配 Server Components 和 Client Components 混合使用。API 呼叫在 Client Components 中進行（需要互動和狀態管理）。

**Rationale**: App Router 是 Next.js 14 的推薦方式，提供更好的路由組織和 layout 支援。Server Components 用於靜態 layout，Client Components 用於互動式內容（表單、影片播放器、進度更新等）。

**Alternatives considered**:
- Pages Router：仍然支援但不是推薦方式，缺少 layout 嵌套等功能
- Pure React SPA（Create React App/Vite）：無 SSR 支援，不適合展示現代前端架構

## R6: 頁面與 Feature File 對應關係

**Decision**: 每個頁面/路由直接對應一或多個 feature files，在頁面 UI 中可選擇性標註對應的 feature file 名稱。

| 頁面路由 | 對應 Feature Files | 對應 API Endpoints |
|----------|-------------------|-------------------|
| `/login` | N/A（認證） | N/A（前端 token 管理） |
| `/products` | 06-查詢商品清單 | `GET /products` |
| `/orders` | 07-建立訂單 | `POST /orders` |
| `/orders/[orderNumber]` | 08-查詢訂單, 09-訂單付款, 10-取消訂單 | `GET /orders/{orderNumber}`, `POST /orders/{orderId}/payments`, `POST /orders/{orderId}/cancellations` |
| `/journeys/[journeyId]` | 05-查詢課程清單 | `GET /journeys/{journeyId}/courses` |
| `/journeys/[journeyId]/courses/[courseId]` | 01-增加影片進度, 02-提交挑戰題作業, 03-交付課程, 04-查詢課程進度 | `POST /courses/{courseId}/progress`, `GET /courses/{courseId}/progress`, `POST /courses/{courseId}/submissions`, `POST /courses/{courseId}/deliveries` |
| `/profile` | 11-查詢用戶角色清單 | `GET /users/{username}/roles` |

**Rationale**: 清楚的對應關係讓學生可以追蹤每個前端頁面是如何從 feature file 和 API spec 推導出來的，體現 API-first + BDD 的開發流程。
