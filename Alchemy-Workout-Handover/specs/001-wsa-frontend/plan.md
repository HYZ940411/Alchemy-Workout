# Implementation Plan: WSA 課程平台前端

**Branch**: `001-wsa-frontend` | **Date**: 2026-01-26 | **Spec**: [spec.md](../../chapter04/specs/001-wsa-frontend/spec.md)
**Input**: Feature specification from `/chapter04/specs/001-wsa-frontend/spec.md`

## Summary

建立 WSA 課程平台的 Next.js 前端應用，位於 `exercises/wsa-課程平台/frontend/`，與現有 Java/Python 後端共用同一套 API spec (`specs/api.yml`) 和 11 個 feature files。前端支援 mock data 模式（資料來自 feature files 的 Gherkin tables）和 production 模式（透過 Bearer Token 認證連接後端 API）。影片課程使用 YouTube iframe 播放器。透過單一 `docker-compose.yml` 搭配 profiles 管理 Java/Python 後端選擇。

## Technical Context

**Language/Version**: TypeScript 5.x / Node.js 20+
**Primary Dependencies**: Next.js 14 (App Router), React 18, YouTube IFrame API
**Storage**: N/A（前端不直接操作資料庫；mock 模式使用靜態 JSON）
**Testing**: Jest + React Testing Library
**Target Platform**: Web（現代瀏覽器）
**Project Type**: web（前端單一專案，後端已存在）
**Performance Goals**: 教學示範用途，無特殊效能需求
**Constraints**: 必須完全遵守 `specs/api.yml` 的 endpoint 定義；mock/production 模式透過環境變數切換
**Scale/Scope**: 教學示範應用，約 8-10 個頁面，11 個 API endpoint 對應

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution 為未客製化的模板，無專案特定的 gates 或約束。所有設計決策基於 spec 中的 clarifications 和 assumptions。

**Pre-Phase 0 Status**: PASS（無 gate violations）
**Post-Phase 1 Re-evaluation**: PASS（Constitution 為未客製化模板，Phase 1 設計產出物無違反任何約束）

## Project Structure

### Documentation (this feature)

```text
specs/001-wsa-frontend/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (references existing api.yml)
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code

```text
exercises/wsa-課程平台/
├── frontend/                        # Next.js 前端專案
│   ├── src/
│   │   ├── app/                     # Next.js App Router pages
│   │   │   ├── layout.tsx           # Root layout with auth provider
│   │   │   ├── page.tsx             # Home / 商品清單
│   │   │   ├── login/
│   │   │   │   └── page.tsx         # 登入頁面
│   │   │   ├── products/
│   │   │   │   └── page.tsx         # 商品清單 (Feature 06)
│   │   │   ├── orders/
│   │   │   │   ├── page.tsx         # 建立訂單 (Feature 07)
│   │   │   │   └── [orderNumber]/
│   │   │   │       └── page.tsx     # 查詢訂單 (Feature 08)
│   │   │   ├── journeys/
│   │   │   │   └── [journeyId]/
│   │   │   │       ├── page.tsx     # 課程清單 (Feature 05)
│   │   │   │       └── courses/
│   │   │   │           └── [courseId]/
│   │   │   │               └── page.tsx  # 課程詳情 + 影片播放 (Features 01,02,03,04)
│   │   │   └── profile/
│   │   │       └── page.tsx         # 用戶角色清單 (Feature 11)
│   │   ├── components/              # 共用 UI 元件
│   │   │   ├── layout/
│   │   │   │   ├── Navbar.tsx
│   │   │   │   └── Footer.tsx
│   │   │   ├── products/
│   │   │   │   ├── ProductCard.tsx
│   │   │   │   └── ProductList.tsx
│   │   │   ├── orders/
│   │   │   │   ├── OrderForm.tsx
│   │   │   │   ├── OrderDetail.tsx
│   │   │   │   └── PaymentForm.tsx
│   │   │   ├── courses/
│   │   │   │   ├── CourseList.tsx
│   │   │   │   ├── CourseCard.tsx
│   │   │   │   ├── VideoPlayer.tsx      # YouTube iframe wrapper
│   │   │   │   ├── ChallengeSubmit.tsx
│   │   │   │   └── DeliveryButton.tsx
│   │   │   └── auth/
│   │   │       └── AuthProvider.tsx
│   │   ├── lib/                     # 工具與 API 層
│   │   │   ├── api/
│   │   │   │   ├── client.ts        # API client (Bearer Token, base URL)
│   │   │   │   ├── products.ts      # GET /products
│   │   │   │   ├── orders.ts        # POST /orders, GET /orders/{}, POST payments, POST cancellations
│   │   │   │   ├── courses.ts       # POST progress, GET progress, POST submissions, POST deliveries
│   │   │   │   ├── journeys.ts      # GET /journeys/{}/courses
│   │   │   │   └── users.ts         # GET /users/{}/roles
│   │   │   ├── mock/
│   │   │   │   ├── data.ts          # Mock data extracted from feature files
│   │   │   │   └── handlers.ts      # Mock API handlers (same interface as real API)
│   │   │   ├── auth.ts              # Token management
│   │   │   └── types.ts             # TypeScript types from API spec schemas
│   │   └── hooks/                   # Custom React hooks
│   │       ├── useAuth.ts
│   │       └── useApi.ts
│   ├── public/
│   ├── package.json
│   ├── next.config.js
│   ├── tsconfig.json
│   ├── Dockerfile
│   └── .env.example
├── docker-compose.yml               # Unified compose with profiles
├── features/                        # Existing feature files (shared)
├── specs/                           # Existing API spec (shared)
├── java/                            # Existing Java backend
└── python/                          # Existing Python backend
```

**Structure Decision**: 使用 Next.js App Router 結構，頁面路由直接對應 API endpoint 和 feature files。API client 層抽象 mock/production 模式切換。前端專案位於 `exercises/wsa-課程平台/frontend/`，與 `java/` 和 `python/` 同層級。`docker-compose.yml` 放在 `exercises/wsa-課程平台/` 根目錄管理所有服務。

## Complexity Tracking

> No constitution violations. No complexity justifications needed.
