# Quickstart: WSA 課程平台前端

**Branch**: `001-wsa-frontend` | **Date**: 2026-01-26

## Prerequisites

- Node.js 20+
- npm or yarn
- Docker & Docker Compose (for full stack)

## Mode 1: Mock Data (Frontend Only)

前端獨立開發模式，使用從 feature files 提取的靜態測試資料。

```bash
cd exercises/wsa-課程平台/frontend

# Install dependencies
npm install

# Start in mock mode
NEXT_PUBLIC_API_MODE=mock npm run dev
```

Open http://localhost:3000

**Login**: Select a user from the mock user list (Alice, Bob, Charlie). Frontend generates a JWT token locally.

## Mode 2: Production (With Backend)

連接實際後端 API。

```bash
cd exercises/wsa-課程平台/frontend

# Install dependencies
npm install

# Start with backend connection
NEXT_PUBLIC_API_MODE=production \
NEXT_PUBLIC_API_BASE_URL=http://localhost:8080/v1 \
npm run dev
```

Requires a running backend (Java or Python) on port 8080.

## Mode 3: Docker Compose (Full Stack)

使用單一 `docker-compose.yml` 一鍵啟動前後端和資料庫。

```bash
cd exercises/wsa-課程平台

# With Java backend
docker compose --profile java up

# With Python backend
docker compose --profile python up

# Frontend only (mock mode, no backend)
docker compose up
```

| Service | URL | Profile |
|---------|-----|---------|
| Frontend | http://localhost:3000 | default |
| Database | localhost:5432 | default |
| Java Backend | http://localhost:8080 | `java` |
| Python Backend | http://localhost:8080 | `python` |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEXT_PUBLIC_API_MODE` | `mock` | `mock` or `production` |
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:8080/v1` | Backend API base URL (production mode) |

## Mock Users

Available in mock mode (from feature file Background data):

| Username | Level | Experience | Roles |
|----------|-------|------------|-------|
| Alice | 1 | 0 | Journey 1: 旅程購買 + 旅程訂閱狀態; Journey 2: 旅程老師 |
| Bob | 2 | 500 | Journey 1: 旅程訂閱狀態 |
| Charlie | 1 | 0 | (none) |

## Page Routes

| Route | Description | Feature Files |
|-------|-------------|---------------|
| `/login` | User login | N/A |
| `/products` | Browse products | 06-查詢商品清單 |
| `/orders` | Create order | 07-建立訂單 |
| `/orders/[orderNumber]` | Order details, payment, cancellation | 08, 09, 10 |
| `/journeys/[journeyId]` | Course list | 05-查詢課程清單 |
| `/journeys/[journeyId]/courses/[courseId]` | Course detail, video, submission | 01, 02, 03, 04 |
| `/profile` | User roles | 11-查詢用戶角色清單 |
