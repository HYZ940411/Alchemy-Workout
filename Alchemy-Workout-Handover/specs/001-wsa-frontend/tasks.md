# Tasks: WSA 課程平台前端

**Input**: Design documents from `/specs/001-wsa-frontend/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in specification. Test tasks are omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- All file paths relative to `exercises/wsa-課程平台/frontend/` unless otherwise noted

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize Next.js project and basic configuration

- [x] T001 Initialize Next.js 14 project with TypeScript and App Router in `exercises/wsa-課程平台/frontend/` using `npx create-next-app@14 --typescript --app --src-dir`
- [x] T002 Configure project dependencies: install `jsonwebtoken` (or `jose` for edge runtime) in `exercises/wsa-課程平台/frontend/package.json`
- [x] T003 [P] Create environment configuration file `exercises/wsa-課程平台/frontend/.env.example` with `NEXT_PUBLIC_API_MODE=mock` and `NEXT_PUBLIC_API_BASE_URL=http://localhost:8080/v1`
- [x] T004 [P] Create Dockerfile for frontend in `exercises/wsa-課程平台/frontend/Dockerfile` (Node.js 20 base, multi-stage build)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Define all TypeScript interfaces from API spec schemas (Product, PlanItem, Order, OrderItem, CourseProgress, CourseWithProgress, UserRole, Error, User, Journey, Chapter, Course, Coupon) in `exercises/wsa-課程平台/frontend/src/lib/types.ts`
- [x] T006 [P] Implement API client with Bearer Token header injection and mock/production mode routing based on `NEXT_PUBLIC_API_MODE` env var in `exercises/wsa-課程平台/frontend/src/lib/api/client.ts`
- [x] T007 [P] Implement auth module with JWT token generation (mock mode), token storage (localStorage), token decode, login/logout functions in `exercises/wsa-課程平台/frontend/src/lib/auth.ts`
- [x] T008 [P] Create mock data constants extracted from all 11 feature file Background Gherkin tables (users, journeys, chapters, courses, products, planItems, orders, coupons, roles, courseProgress) in `exercises/wsa-課程平台/frontend/src/lib/mock/data.ts`
- [x] T009 Create AuthProvider React context component wrapping `useAuth` state in `exercises/wsa-課程平台/frontend/src/components/auth/AuthProvider.tsx`
- [x] T010 Create useAuth custom hook (login, logout, currentUser, token, isAuthenticated) in `exercises/wsa-課程平台/frontend/src/hooks/useAuth.ts`
- [x] T011 [P] Create useApi custom hook (generic fetch wrapper using API client, loading/error states) in `exercises/wsa-課程平台/frontend/src/hooks/useApi.ts`
- [x] T012 Create root layout with AuthProvider wrapper, navigation, and basic page structure in `exercises/wsa-課程平台/frontend/src/app/layout.tsx`
- [x] T013 [P] Create Navbar component with navigation links (商品, 訂單, 課程, 個人資料) and current user display in `exercises/wsa-課程平台/frontend/src/components/layout/Navbar.tsx`
- [x] T014 Create login page with mock user selector (Alice/Bob/Charlie dropdown) and JWT token generation in `exercises/wsa-課程平台/frontend/src/app/login/page.tsx`

**Checkpoint**: Foundation ready - auth works, mock data loaded, API client routes correctly, user can log in

---

## Phase 3: User Story 1 - 瀏覽與購買商品 (Priority: P1) 🎯 MVP

**Goal**: 學生可以瀏覽商品清單、建立訂單、使用折扣券、完成付款，獲得旅程存取權限

**Independent Test**: 登入 → 瀏覽商品清單 → 選擇商品建立訂單 → 選擇付款方式完成付款 → 確認訂單狀態為處理中

### Implementation for User Story 1

- [x] T015 [P] [US1] Implement products API module with `getProducts(status?)` function (mock: filter from data.ts; production: GET /products) in `exercises/wsa-課程平台/frontend/src/lib/api/products.ts`
- [x] T016 [P] [US1] Implement orders API module with `createOrder(items, couponIds?)` and `payOrder(orderId, paymentMethod, paymentProvider?)` functions (mock: create in-memory order with 18-digit number, calculate price with coupon discount; production: POST /orders, POST /orders/{orderId}/payments) in `exercises/wsa-課程平台/frontend/src/lib/api/orders.ts`
- [x] T017 [P] [US1] Implement mock handlers for products and order-create/payment endpoints (product status filtering, order number generation, coupon validation and discount calculation, payment with role granting) in `exercises/wsa-課程平台/frontend/src/lib/mock/handlers.ts`
- [x] T018 [P] [US1] Create ProductCard component displaying product name, price, description, status badge, and plan items list in `exercises/wsa-課程平台/frontend/src/components/products/ProductCard.tsx`
- [x] T019 [US1] Create ProductList component with status filter (上架中/已下架/全部) wrapping ProductCard grid in `exercises/wsa-課程平台/frontend/src/components/products/ProductList.tsx`
- [x] T020 [US1] Create products page fetching product list and rendering ProductList in `exercises/wsa-課程平台/frontend/src/app/products/page.tsx`
- [x] T021 [P] [US1] Create OrderForm component with product selection, quantity input, coupon selection (from user's available coupons), and total price preview with discount calculation in `exercises/wsa-課程平台/frontend/src/components/orders/OrderForm.tsx`
- [x] T022 [P] [US1] Create PaymentForm component with payment method selector (信用卡/ATM轉帳/無卡分期), payment provider selector, and submit button in `exercises/wsa-課程平台/frontend/src/components/orders/PaymentForm.tsx`
- [x] T023 [US1] Create orders page with OrderForm for creating new orders; on success show order number, total price, payment deadline, and PaymentForm for immediate payment in `exercises/wsa-課程平台/frontend/src/app/orders/page.tsx`

**Checkpoint**: User Story 1 fully functional - browse products, create order with coupons, pay and receive roles

---

## Phase 4: User Story 2 - 學習課程與追蹤進度 (Priority: P2)

**Goal**: 已購買旅程的學生可以查看課程清單、觀看影片並自動追蹤進度、提交挑戰題、交付課程獲得經驗值

**Independent Test**: 以 Alice 登入 → 進入旅程 1 課程清單 → 選擇影片課程 → 播放影片至 80% 確認進度更新 → 播放至 100% 確認狀態變已完成 → 交付課程確認經驗值獎勵

### Implementation for User Story 2

- [x] T024 [P] [US2] Implement journeys API module with `getJourneyCourses(journeyId, chapterId?)` function (mock: filter courses from data.ts with progress; production: GET /journeys/{journeyId}/courses) in `exercises/wsa-課程平台/frontend/src/lib/api/journeys.ts`
- [x] T025 [P] [US2] Implement courses API module with `updateProgress(courseId, progress)`, `getCourseProgress(courseId)`, `submitChallenge(courseId, data)`, `deliverCourse(courseId)` functions (mock: update in-memory state with validation rules; production: POST/GET endpoints) in `exercises/wsa-課程平台/frontend/src/lib/api/courses.ts`
- [x] T026 [US2] Add mock handlers for journey courses, course progress, challenge submission, and course delivery endpoints (progress monotonic increase, auto-complete at 100%, delivery with XP/level calculation) to `exercises/wsa-課程平台/frontend/src/lib/mock/handlers.ts`
- [x] T027 [P] [US2] Create CourseCard component displaying course name, type icon, chapter name, XP reward, progress bar, and status badge in `exercises/wsa-課程平台/frontend/src/components/courses/CourseCard.tsx`
- [x] T028 [US2] Create CourseList component with chapter filter tabs wrapping CourseCard grid in `exercises/wsa-課程平台/frontend/src/components/courses/CourseList.tsx`
- [x] T029 [US2] Create journey courses page fetching course list for journeyId param and rendering CourseList with chapter filter in `exercises/wsa-課程平台/frontend/src/app/journeys/[journeyId]/page.tsx`
- [x] T030 [US2] Create VideoPlayer component wrapping YouTube IFrame Player API with `onStateChange` listener and 3-second polling of `getCurrentTime()`/`getDuration()` to calculate and POST progress percentage in `exercises/wsa-課程平台/frontend/src/components/courses/VideoPlayer.tsx`
- [x] T031 [P] [US2] Create ChallengeSubmit component with submission form (textarea/file upload placeholder) and submit button calling `submitChallenge` API in `exercises/wsa-課程平台/frontend/src/components/courses/ChallengeSubmit.tsx`
- [x] T032 [P] [US2] Create DeliveryButton component showing deliver action for completed courses, displaying XP gained and level-up info on success in `exercises/wsa-課程平台/frontend/src/components/courses/DeliveryButton.tsx`
- [x] T033 [US2] Create course detail page rendering VideoPlayer (for 影片課程), ChallengeSubmit (for 挑戰題課程), or info display (for 問卷課程), plus progress status and DeliveryButton in `exercises/wsa-課程平台/frontend/src/app/journeys/[journeyId]/courses/[courseId]/page.tsx`

**Checkpoint**: User Story 2 fully functional - view courses, watch video with auto-progress, submit challenge, deliver for XP

---

## Phase 5: User Story 3 - 管理訂單 (Priority: P3)

**Goal**: 學生可以查詢訂單詳情和取消未完成的訂單

**Independent Test**: 以 Alice 登入 → 查詢已存在的訂單編號 → 確認訂單詳情顯示完整 → 取消一筆已建立狀態的訂單 → 確認狀態變已取消且折扣券釋放

### Implementation for User Story 3

- [x] T034 [US3] Add `getOrder(orderNumber)` and `cancelOrder(orderId)` functions to existing orders API module (mock: lookup by orderNumber, validate status for cancel, release coupons; production: GET /orders/{orderNumber}, POST /orders/{orderId}/cancellations) in `exercises/wsa-課程平台/frontend/src/lib/api/orders.ts`
- [x] T035 [US3] Add mock handlers for order query and order cancellation endpoints (ownership check, status validation, coupon release on cancel) to `exercises/wsa-課程平台/frontend/src/lib/mock/handlers.ts`
- [x] T036 [US3] Create OrderDetail component displaying order number, status badge, total price, created time, payment deadline, order items table, and cancel button (shown for 已建立/處理中 status) with PaymentForm (shown for 已建立 status) in `exercises/wsa-課程平台/frontend/src/components/orders/OrderDetail.tsx`
- [x] T037 [US3] Create order detail page fetching order by orderNumber param and rendering OrderDetail in `exercises/wsa-課程平台/frontend/src/app/orders/[orderNumber]/page.tsx`

**Checkpoint**: User Story 3 fully functional - view order details, pay pending orders, cancel eligible orders

---

## Phase 6: User Story 4 - 查看個人角色與權限 (Priority: P4)

**Goal**: 學生可以查看自己擁有的所有有效角色，了解可存取的旅程

**Independent Test**: 以 Alice 登入 → 進入個人資料頁 → 確認顯示 3 個有效角色（不含已撤銷的角色 5） → 每個角色顯示類型、旅程名稱、授予時間

### Implementation for User Story 4

- [x] T038 [P] [US4] Implement users API module with `getUserRoles(username)` function (mock: filter active roles from data.ts excluding revoked; production: GET /users/{username}/roles) in `exercises/wsa-課程平台/frontend/src/lib/api/users.ts`
- [x] T039 [US4] Add mock handler for user roles endpoint (ownership check, filter out revokedAt != null) to `exercises/wsa-課程平台/frontend/src/lib/mock/handlers.ts`
- [x] T040 [US4] Create profile page fetching current user's roles and displaying role type, journey name, granted time in a table, with link to journey courses page per role in `exercises/wsa-課程平台/frontend/src/app/profile/page.tsx`

**Checkpoint**: User Story 4 fully functional - view all active roles with journey links

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T041 Create home page with redirect to /products or welcome message with navigation links in `exercises/wsa-課程平台/frontend/src/app/page.tsx`
- [x] T042 [P] Create Footer component with feature file reference annotations in `exercises/wsa-課程平台/frontend/src/components/layout/Footer.tsx`
- [x] T043 Add unified error handling UI: display user-friendly error messages from API error responses (權限不足, 商品不存在, 訂單狀態不允許取消, etc.) across all pages
- [x] T044 Add empty state displays for all list pages (no products, no orders, no courses, no roles)
- [x] T045 Add loading state indicators (skeleton/spinner) for all API-fetching pages
- [x] T046 Create `docker-compose.yml` with frontend (default), database (default), java-backend (profile: java), python-backend (profile: python) services in `exercises/wsa-課程平台/docker-compose.yml`
- [x] T047 Run quickstart.md validation: verify mock mode startup, login flow, and all page routes render correctly

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3 → P4)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - No dependencies on other stories (uses separate API endpoints)
- **User Story 3 (P3)**: Extends orders API module from US1 (T016) - should start after US1 or at minimum after T016 is complete
- **User Story 4 (P4)**: Can start after Foundational (Phase 2) - No dependencies on other stories

### Within Each User Story

- API modules before components
- Components before pages
- Mock handlers alongside their API modules
- Core implementation before integration

### Parallel Opportunities

- Setup: T003 and T004 can run in parallel (after T001/T002)
- Foundational: T005, T006, T007, T008 can all run in parallel (different files), then T009-T011 (depend on T007), then T012-T014
- US1: T015, T016, T017 can run in parallel; T018, T021, T022 can run in parallel
- US2: T024, T025 can run in parallel; T027, T031, T032 can run in parallel
- US3/US4 are small enough to run sequentially
- US1 and US2 can be worked on in parallel by different developers
- US4 can run in parallel with US1/US2/US3

---

## Parallel Example: User Story 1

```bash
# Launch API modules in parallel (different files):
Task: "Implement products API module in src/lib/api/products.ts"        # T015
Task: "Implement orders API module in src/lib/api/orders.ts"            # T016
Task: "Implement mock handlers for products/orders in src/lib/mock/handlers.ts"  # T017

# Launch independent components in parallel:
Task: "Create ProductCard component in src/components/products/ProductCard.tsx"  # T018
Task: "Create OrderForm component in src/components/orders/OrderForm.tsx"        # T021
Task: "Create PaymentForm component in src/components/orders/PaymentForm.tsx"    # T022
```

## Parallel Example: User Story 2

```bash
# Launch API modules in parallel:
Task: "Implement journeys API in src/lib/api/journeys.ts"    # T024
Task: "Implement courses API in src/lib/api/courses.ts"      # T025

# Launch independent components in parallel:
Task: "Create ChallengeSubmit in src/components/courses/ChallengeSubmit.tsx"  # T031
Task: "Create DeliveryButton in src/components/courses/DeliveryButton.tsx"    # T032
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (瀏覽與購買商品)
4. **STOP and VALIDATE**: Login → Browse products → Create order → Pay → Verify roles granted
5. Deploy/demo if ready - students can already experience the purchase flow

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (login works, mock data loaded)
2. Add User Story 1 → Test independently → Deploy/Demo (MVP! Purchase flow works)
3. Add User Story 2 → Test independently → Deploy/Demo (Learning experience works)
4. Add User Story 3 → Test independently → Deploy/Demo (Order management works)
5. Add User Story 4 → Test independently → Deploy/Demo (Role visibility works)
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (Products & Orders)
   - Developer B: User Story 2 (Courses & Progress)
   - Developer C: User Story 4 (User Roles)
3. After US1 completes: Developer A continues with User Story 3 (extends orders)
4. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Mock handlers (handlers.ts) grows incrementally with each story
- All API modules handle both mock and production modes via client.ts routing
- US3 extends orders.ts from US1 - only dependency between stories
