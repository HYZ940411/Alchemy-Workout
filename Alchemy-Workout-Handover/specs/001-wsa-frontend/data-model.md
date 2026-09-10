# Data Model: WSA 課程平台前端

**Branch**: `001-wsa-frontend` | **Date**: 2026-01-26
**Source**: [spec.md](../../chapter04/specs/001-wsa-frontend/spec.md), [api.yml](../../chapter04/exercises/wsa-課程平台/specs/api.yml)

## Entities

### User (用戶)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| username | string | 用戶名稱（唯一識別） | Required, from JWT token payload |
| level | integer | 用戶等級 | >= 1 |
| experience | integer | 累計經驗值 | >= 0 |

**Notes**: 前端不直接管理 User 實體。用戶身份從 JWT token 解碼取得 `username`，等級和經驗值從交付課程的回應中取得。

---

### Journey (旅程)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| journeyId | integer | 旅程 ID | Primary key |
| name | string | 旅程名稱 | Required |

**Relationships**:
- Journey 1:N Chapter（一個旅程有多個章節）
- Journey 1:N Course（透過 Chapter）
- Journey N:M User（透過 UserRole）

**Mock Data**:
| journeyId | name |
|-----------|------|
| 1 | 軟體設計模式精通之旅 / 物件導向設計之旅 |
| 2 | AI x BDD 實戰工作坊 / 敏捷開發之旅 |
| 3 | 敏捷開發實戰 |

---

### Chapter (章節)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| chapterId | integer | 章節 ID | Primary key |
| journeyId | integer | 所屬旅程 ID | FK → Journey |
| name | string | 章節名稱 | Required |
| order | integer | 排序順序 | >= 1 |

**Mock Data**:
| chapterId | journeyId | name | order |
|-----------|-----------|------|-------|
| 1 | 1 | 基礎篇 | 1 |
| 2 | 1 | 進階篇 | 2 |
| 3 | 2 | Scrum 實戰 | 1 |

---

### Course (課程)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| courseId | integer | 課程 ID | Primary key |
| name | string | 課程名稱 | Required |
| type | string | 課程類型 | Enum: `影片課程`, `問卷課程`, `挑戰題課程` |
| journeyId | integer | 所屬旅程 ID | FK → Journey |
| chapterId | integer | 所屬章節 ID | FK → Chapter |
| experiencePoints | integer | 獎勵經驗值 | >= 0 |

**Relationships**:
- Course N:1 Journey
- Course N:1 Chapter
- Course 1:1 CourseProgress（per user）

**Mock Data**:
| courseId | name | type | journeyId | chapterId | experiencePoints |
|---------|------|------|-----------|-----------|-----------------|
| 1 | 物件導向基礎 | 影片課程 | 1 | 1 | 300 |
| 2 | 設計模式問卷 | 問卷課程 | 1 | 1 | 50 |
| 3 | 實作練習 | 挑戰題課程 | 1 | 1 | 200 |
| 4 | SOLID 原則 | 影片課程 | 1 | 2 | 400 |
| 5 | Scrum 入門 | 影片課程 | 2 | 3 | 300 |

---

### CourseProgress (課程進度)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| username | string | 用戶名稱 | FK → User |
| courseId | integer | 課程 ID | FK → Course |
| courseName | string | 課程名稱 | Denormalized |
| courseType | string | 課程類型 | Enum: `影片課程`, `問卷課程`, `挑戰題課程` |
| progress | integer | 進度百分比 | 0-100, 影片課程適用 |
| status | string | 課程狀態 | Enum: see state transitions |

**State Transitions**:

```
未開始 ──(更新進度 > 0%)──→ 進行中
進行中 ──(進度達 100%)──→ 已完成
已完成 ──(交付課程)──→ 已交付
已交付 ──(不可逆)──→ (final state)
```

**Validation Rules**:
- 進度只能單調遞增（不可倒退）
- 進度值必須在 0-100 之間
- 影片課程達 100% 自動標記已完成
- 挑戰題課程提交作業直接標記已完成
- 已完成才能交付，已交付不可重複交付
- 已交付的課程仍可更新進度，但狀態不變

---

### Product (商品)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| productId | integer | 商品 ID | Primary key |
| name | string | 商品名稱 | Required |
| price | number | 商品價格 | >= 0 |
| description | string | 商品描述 | Optional |
| status | string | 商品狀態 | Enum: `上架中`, `已下架` |
| planItems | PlanItem[] | 方案項目清單 | 1..N items |

**PlanItem** (嵌入式):

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| planType | string | 方案類型 | Enum: `旅程購買`, `旅程訂閱` |
| journeyId | integer | 旅程 ID | FK → Journey |
| subscriptionDays | integer? | 訂閱天數 | 僅 `旅程訂閱` 適用, nullable |

**Mock Data**:
| productId | name | price | description | status |
|-----------|------|-------|-------------|--------|
| 1 | 軟體設計模式精通之旅 | 9800 | 學習 23 種設計模式 | 上架中 |
| 2 | AI x BDD 課程 | 12000 | AI 輔助行為驅動開發 | 上架中 |
| 3 | 敏捷開發實戰 | 8500 | Scrum 與 Kanban | 已下架 |
| 4 | 軟體設計模式續訂 | 2000 | 續訂一個月 | 上架中 |

---

### Order (訂單)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| orderNumber | string | 訂單編號 | 18 位數字, pattern: `^\d{18}$` |
| status | string | 訂單狀態 | Enum: see state transitions |
| totalPrice | number | 訂單總價 | >= 0 |
| createdAt | datetime | 建立時間 | ISO 8601 |
| paymentDeadline | datetime | 付款期限 | 建立時間 + 3 天 |
| items | OrderItem[] | 訂單項目 | 1..N items |

**OrderItem** (嵌入式):

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| productId | integer | 商品 ID | FK → Product |
| productName | string | 商品名稱 | Denormalized |
| unitPrice | number | 單價 | >= 0 |
| quantity | integer | 數量 | >= 1 |

**State Transitions**:

```
已建立 ──(付款)──→ 處理中
已建立 ──(取消)──→ 已取消
處理中 ──(付款完成)──→ 已付款
處理中 ──(取消)──→ 已取消
已付款 ──(完成)──→ 已完成
已取消 ──(不可逆)──→ (final state)
已完成 ──(不可逆)──→ (final state)
```

**Validation Rules**:
- 商品必須存在且上架中
- 訂單項目不可重複（同一商品不可出現兩次）
- 已有「旅程購買」角色的用戶不可購買包含該旅程購買方案的商品
- 只能取消自己的訂單
- 只能取消已建立或處理中狀態的訂單
- 只能為已建立狀態的訂單付款

---

### Coupon (折扣券)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| couponId | integer | 折扣券 ID | Primary key |
| username | string | 所屬用戶 | FK → User |
| code | string | 折扣碼 | Unique |
| name | string | 折扣券名稱 | Required |
| type | string | 折扣券類型 | Enum: `抵用券`, `折扣` |
| discountValue | number | 折扣值 | 抵用券: 金額; 折扣: 比例 (e.g., 0.9 = 九折) |
| used | boolean | 是否已使用 | Default: false |
| expiresAt | datetime | 過期時間 | Must be future |

**Discount Calculation Order**:
1. 先套用折扣比例（`折扣` type）: `price * discountValue`
2. 再扣除抵用券金額（`抵用券` type）: `price - discountValue`

**Validation Rules**:
- 折扣券必須屬於下單用戶
- 折扣券必須未使用且未過期
- 取消訂單時釋放折扣券（重設為未使用）

**Mock Data**:
| couponId | username | code | name | type | discountValue | used | expiresAt |
|----------|----------|------|------|------|---------------|------|-----------|
| 1 | Alice | WELCOME100 | 新人優惠 | 抵用券 | 1000 | 否 | 2026-12-31 |
| 2 | Alice | DISCOUNT10 | 九折優惠 | 折扣 | 0.9 | 否 | 2026-12-31 |
| 3 | Alice | EXPIRED | 過期券 | 抵用券 | 500 | 否 | 2023-01-01 |
| 4 | Bob | BOB200 | Bob 專屬 | 抵用券 | 200 | 否 | 2026-12-31 |

---

### UserRole (用戶角色)

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| roleId | integer | 角色 ID | Primary key |
| username | string | 用戶名稱 | FK → User |
| roleType | string | 角色類型 | Enum: `旅程購買`, `旅程訂閱狀態`, `旅程老師` |
| journeyId | integer | 旅程 ID | FK → Journey |
| journeyName | string | 旅程名稱 | Denormalized |
| grantedAt | datetime | 授予時間 | ISO 8601 |
| revokedAt | datetime? | 撤銷時間 | Nullable, ISO 8601 |

**Validation Rules**:
- 只能查詢自己的角色清單
- 查詢結果不包含已撤銷的角色（`revokedAt != null`）
- 付款訂單後自動授予對應旅程角色

**Mock Data**:
| roleId | username | roleType | journeyId | journeyName | grantedAt | revokedAt |
|--------|----------|----------|-----------|-------------|-----------|-----------|
| 1 | Alice | 旅程購買 | 1 | 軟體設計模式精通之旅 | 2023-12-01T10:00:00 | null |
| 2 | Alice | 旅程訂閱狀態 | 1 | 軟體設計模式精通之旅 | 2023-12-01T10:00:00 | null |
| 3 | Alice | 旅程老師 | 2 | AI x BDD 實戰工作坊 | 2023-12-05T14:30:00 | null |
| 4 | Bob | 旅程訂閱狀態 | 1 | 軟體設計模式精通之旅 | 2023-12-10T09:00:00 | null |
| 5 | Alice | 旅程訂閱狀態 | 2 | AI x BDD 實戰工作坊 | 2023-11-01T08:00:00 | 2023-11-30T23:59:59 |

## Entity Relationship Diagram

```
User ──1:N──→ UserRole ──N:1──→ Journey
User ──1:N──→ Coupon
User ──1:N──→ Order
User ──1:N──→ CourseProgress ──N:1──→ Course

Journey ──1:N──→ Chapter ──1:N──→ Course
Product ──1:N──→ PlanItem ──N:1──→ Journey
Order ──1:N──→ OrderItem ──N:1──→ Product
```

## Access Control Matrix

| Entity | Create | Read | Update | Delete |
|--------|--------|------|--------|--------|
| Product | - | All users | - | - |
| Order | Owner | Owner only | Owner (pay/cancel) | - |
| CourseProgress | Owner | Owner only | Owner | - |
| Course | - | Users with journey roles | - | - |
| UserRole | System (via payment) | Owner only | - | - |
| Coupon | - | Owner (via order flow) | System (use/release) | - |

**Access requires**: Valid Bearer Token in all cases. For Course/CourseProgress: user must have both `旅程購買` AND `旅程訂閱狀態` roles for the journey.
