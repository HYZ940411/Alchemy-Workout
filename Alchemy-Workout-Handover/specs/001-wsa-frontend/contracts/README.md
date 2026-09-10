# API Contracts: WSA 課程平台前端

**Branch**: `001-wsa-frontend` | **Date**: 2026-01-26

## API Specification

本專案的 API 合約已完整定義於共用的 OpenAPI 3.0.3 規範：

**Location**: [`exercises/wsa-課程平台/specs/api.yml`](../../../chapter04/exercises/wsa-課程平台/specs/api.yml)

此 API spec 由前端和後端（Java/Python）共用，是 API-first 開發流程的核心。

## Endpoints Summary

| Method | Path | Operation | Feature |
|--------|------|-----------|---------|
| POST | `/courses/{courseId}/progress` | updateCourseProgress | 01-增加影片進度 |
| POST | `/courses/{courseId}/submissions` | submitChallengeAssignment | 02-提交挑戰題作業 |
| POST | `/courses/{courseId}/deliveries` | deliverCourse | 03-交付課程 |
| GET | `/courses/{courseId}/progress` | getCourseProgress | 04-查詢課程進度 |
| GET | `/journeys/{journeyId}/courses` | getJourneyCourses | 05-查詢課程清單 |
| GET | `/journeys/{journeyId}/chapters/{chapterId}/courses` | getChapterCourses | 05-查詢課程清單 |
| GET | `/products` | getProducts | 06-查詢商品清單 |
| POST | `/orders` | createOrder | 07-建立訂單 |
| GET | `/orders/{orderNumber}` | getOrder | 08-查詢訂單 |
| POST | `/orders/{orderId}/payments` | payOrder | 09-訂單付款 |
| POST | `/orders/{orderId}/cancellations` | cancelOrder | 10-取消訂單 |
| GET | `/users/{username}/roles` | getUserRoles | 11-查詢用戶角色清單 |

## Authentication

All endpoints use `BearerAuth` (HTTP Bearer Token with JWT format):

```
Authorization: Bearer <jwt-token>
```

JWT payload contains `username` field for user identification.

## Response Format

All responses follow unified format:

**Success**:
```json
{
  "success": true,
  "data": { ... }
}
```

**Error**:
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message"
  }
}
```

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| UNAUTHORIZED | 401 | 未提供有效的認證令牌 |
| PERMISSION_DENIED | 403 | 權限不足 |
| PROGRESS_DECREASED | 400 | 進度不可倒退 |
| INVALID_PROGRESS | 400 | 進度值必須在 0-100 之間 |
| INVALID_COURSE_TYPE | 400 | 無法提交非挑戰題課程的作業 |
| COURSE_NOT_COMPLETED | 400 | 課程未完成，無法交付 |
| ALREADY_DELIVERED | 400 | 課程已交付，無法重複交付 |
| INVALID_STATUS | 400 | 狀態篩選參數必須有效 |
| PRODUCT_NOT_FOUND | 400 | 商品不存在 |
| PRODUCT_OFF_SHELF | 400 | 商品已下架 |
| DUPLICATE_ITEMS | 400 | 訂單項目重複 |
| INVALID_COUPON | 400 | 折扣券無效 |
| ALREADY_PURCHASED | 400 | 已購買此旅程 |
| ORDER_NOT_FOUND | 404 | 訂單不存在 |
| INVALID_ORDER_STATUS | 400 | 訂單狀態不允許此操作 |

## Schema References

Shared schemas defined in `api.yml` `components/schemas`:
- `Error` - Unified error response
- `CourseProgress` - Course progress with user context
- `CourseWithProgress` - Course listing with progress
- `Product` - Product with plan items
- `Order` - Order with items
- `UserRole` - User role with journey info
