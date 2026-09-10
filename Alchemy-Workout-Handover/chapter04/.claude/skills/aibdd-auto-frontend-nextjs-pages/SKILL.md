---
name: aibdd-auto-frontend-nextjs-pages
description: >
  前端 Next.js 頁面實作。基於已完成的 Walking Skeleton（MSW + API client）和 UI/UX
  consultant 產出的 layout.html 靜態原型，將靜態頁面轉換為動態 Next.js React 元件。
  當使用者要求實作前端頁面、將 layout.html 轉為 Next.js、或在已有 MSW 骨架的前端專案中
  開發功能頁面時，使用此 skill。需要 specs 目錄下的 activities 或 features 作為規格參考。
  可搭配 /aibdd-auto-frontend-msw-api-layer 所產生的 API 基礎建設。
---

# Next.js 頁面實作器

將靜態 HTML 原型 + 規格文件轉換為動態 Next.js 頁面。

**前提假設**：
- Walking Skeleton 已由 `/aibdd-auto-frontend-apifirst-msw-starter` 初始化完成
- MSW API layer 已由 `/aibdd-auto-frontend-msw-api-layer` 產生完成
- API client 函式（`src/lib/api/`）和 Zod schemas（`src/lib/types/`）已就位

```
1. 參數載入        — 從 arguments.yml 讀取路徑配置
2. 規格校驗        — 確認 activities 或 features 至少擇一存在
3. 盤點頁面        — 從規格推導需要實作的頁面清單
4. 元件拆解        — 將 layout.html 拆解為 React 元件樹
5. 逐頁實作        — 將靜態 HTML 轉為動態 Next.js 頁面
6. 整合驗證        — 確保頁面間導航與資料流正確
```

## Phase 0：參數載入

從 `${SPECS_HOME}/arguments.yml` 讀取路徑配置：

| 參數 | 用途 | 範例值 |
|------|------|--------|
| `PROJECT_ROOT` | 前端專案根目錄 | `frontend/` |
| `SPECS_HOME` | 規格文件目錄 | `specs/` |
| `SRC_DIR` | 原始碼目錄 | `src` |
| `TYPES_DIR` | Zod schema 目錄 | `src/lib/types` |
| `API_CLIENT_DIR` | API client 目錄 | `src/lib/api` |

額外掃描的路徑（非參數，固定慣例）：

| 路徑 | 用途 |
|------|------|
| `${SPECS_HOME}/activities/*.activity` | Activity Diagram，推導頁面流程 |
| `${SPECS_HOME}/features/**/*.feature` | Feature Files，推導頁面功能細節 |
| `${SPECS_HOME}/activities/*.testplan.md` | 測試計畫（Optional），供驗證參考 |
| `${PROJECT_ROOT}/layout.html` 或 `${SPECS_HOME}/*.layout.html` | UI/UX 靜態原型 |

## Phase 1：規格校驗

**必要條件**：`activities/` 或 `features/` 至少擇一存在。

```
掃描 ${SPECS_HOME}/activities/*.activity
掃描 ${SPECS_HOME}/features/**/*.feature

存在任一？
  ├─ 是 → 繼續 Phase 2
  └─ 否 → 中斷
         ├─ 預設：輸出錯誤訊息，請使用者提供 .activity 或 .feature 檔案
         └─ 使用者強行要求 → 根據 layout.html 的頁面結構腦補基礎規格
```

校驗細節見 [references/spec-validation.md](references/spec-validation.md)。

## Phase 2：盤點頁面

從規格文件推導需要實作的頁面清單。

### 從 Activity Diagram 推導

每個 `[STEP]` 綁定的 `.feature` 暗示一個使用者操作場景。
將相關操作歸類為頁面：

```
[STEP:1] {specs/features/lead/匯入名單.feature}  → /leads/import 頁面
[STEP:2] {specs/features/lead/新增名單.feature}  → /leads/new 頁面（或 /leads 頁面的新增功能）
[STEP:5] {specs/features/lead/查詢名單.feature}  → /leads 清單頁面
```

### 從 Feature Files 推導

每個 `Feature:` 對應一個功能模組。按 CRUD 語意歸類：
- `查詢/清單` → List 頁面
- `新增/建立` → Create 表單（或 List 頁面的 Modal）
- `編輯/更新` → Edit 表單（或 Detail 頁面的 inline editing）
- `刪除` → Delete 確認（通常是 Modal 或 Popconfirm）
- `詳情/檢視` → Detail 頁面

### 產出：頁面清單

```
盤點結果：
1. /projects              — 專案清單頁（建立、查詢、刪除）
2. /projects/[id]         — 專案詳情頁（編輯、階段設定）
3. /projects/[id]/leads   — 名單清單頁（匯入、新增、查詢、刪除）
4. /projects/[id]/leads/[leadId] — 名單詳情頁（編輯、激活狀態）
```

## Phase 3：元件拆解

將 `layout.html` 拆解為 React 元件樹。詳細策略見 [references/component-decomposition.md](references/component-decomposition.md)。

核心原則：

1. **視覺保真**：拆解後的元件渲染結果必須與原始 `layout.html` 視覺一致。不能「變醜」。
2. **CSS 遷移**：將 layout.html 的 inline styles 和 `<style>` 區塊轉為 CSS Modules 或 Tailwind classes。
3. **語意化拆解**：按 UI 職責拆分（Header、Sidebar、Content、Table、Form、Modal）。
4. **共用元件提取**：多頁面重複出現的 UI 區塊提取為 `src/components/` 下的共用元件。

### 元件目錄結構

```
src/
├── app/
│   ├── (protected)/
│   │   ├── layout.tsx              ← 包含 Sidebar + TopBar 的 shell
│   │   ├── projects/
│   │   │   ├── page.tsx            ← 專案清單
│   │   │   └── [id]/
│   │   │       ├── page.tsx        ← 專案詳情
│   │   │       └── leads/
│   │   │           ├── page.tsx    ← 名單清單
│   │   │           └── [leadId]/
│   │   │               └── page.tsx ← 名單詳情
│   │   └── ...
│   ├── layout.tsx
│   └── page.tsx                    ← Landing / redirect
├── components/
│   ├── ui/                         ← 通用 UI 元件（Button, Input, Modal, Table...）
│   └── domain/                     ← 業務元件（LeadForm, ProjectCard...）
```

## Phase 4：逐頁實作

對每個頁面，執行以下步驟。詳細模式見 [references/spec-driven-patterns.md](references/spec-driven-patterns.md)。

### 步驟 4A：讀取頁面規格

1. 找到該頁面對應的 `.feature` 檔案
2. 從 `Background:` data table 提取資料結構（→ 表格欄位、表單欄位）
3. 從 `When` 步驟提取使用者操作（→ 按鈕、表單提交、導航）
4. 從 `Then` 步驟提取預期回饋（→ Toast、redirect、UI 狀態變化）
5. 從 `Rule:` 提取驗證規則（→ 表單驗證、條件渲染）

### 步驟 4B：對接 API client

從 `src/lib/api/` 引入已有的 API client 函式：

```typescript
// 已由 msw-api-layer 產生
import { listLeads, createLead, deleteLead } from '@/lib/api/lead'
import type { LeadResponse, CreateLeadRequest } from '@/lib/types/lead.schema'
```

- **不要重新實作 API 呼叫**。直接使用已有的 API client 函式。
- **不要重新定義型別**。直接使用已有的 Zod schema 推導的 TypeScript type。

### 步驟 4C：實作頁面元件

1. 從 `layout.html` 對應區塊提取 HTML 結構
2. 將靜態 HTML 轉為 React JSX
3. 用 `useState` / `useEffect` / React Server Components 實現動態行為
4. 從 API client 獲取資料（Server Component: 直接 await / Client Component: useEffect）
5. 實作使用者操作的 handler（form submit、button click）
6. 加入 Loading / Empty / Error 狀態處理

### 步驟 4D：樣式遷移

從 layout.html 遷移樣式，優先順序：
1. **Tailwind CSS classes**（如果專案已配置 Tailwind）
2. **CSS Modules**（`page.module.css`）
3. **globals.css 中的 CSS 變數**（for design tokens）

**禁止**：inline style objects（除非是動態計算值）。

## Phase 5：整合驗證

完成所有頁面後，驗證整體：

1. **導航連貫性**：從 Activity Diagram 的 STEP 序列驗證頁面間跳轉
2. **資料流一致性**：頁面 A 建立的資料能在頁面 B 正確顯示
3. **狀態同步**：操作（新增、刪除）後清單即時更新
4. **錯誤處理**：API 錯誤正確顯示（Feature 的 Error Scenario）
5. **Test Plan 對照**（若有）：每個測試步驟的預期結果可達成


## 注意事項

- **MSW 已就位**：開發階段所有 API 呼叫會被 MSW 攔截，返回 fixtures 資料。不需要真實後端。
- **不修改 MSW 層**：不要修改 `src/mocks/` 下的檔案。如需新 endpoint，回報給使用者或呼叫 `/aibdd-auto-frontend-msw-api-layer`。
- **視覺品質不能退化**：拆解後的 React 元件渲染結果必須與 layout.html 視覺一致或更好。
- **繁體中文產出**：所有 TODO 註解和文件使用繁體中文，但程式碼中的變數名和函式名使用英文。
