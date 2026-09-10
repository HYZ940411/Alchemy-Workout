"""API 路由註冊模組。

所有 API endpoints 都在此註冊到主 router。
"""

from fastapi import APIRouter

router = APIRouter()

# 在此註冊各個模組的路由
# from app.api import lesson_progress
# router.include_router(lesson_progress.router, prefix="/lesson-progress", tags=["課程進度"])

# from app.api import orders
# router.include_router(orders.router, prefix="/orders", tags=["訂單"])


@router.get("/")
def api_root():
    """API 根端點。"""
    return {"message": "Chapter04 課程平台 API", "version": "1.0.0"}
