"""
FastAPI 後端主程式

實作課程進度管理 API - 應用分層架構和 SOLID 原則
"""
from fastapi import FastAPI, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from typing import Optional
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from support.models import Base
from support.auth import decode_token
from backend.database import engine, get_db
from backend.schemas import (
    UpdateVideoProgressRequest, UpdateVideoProgressResponse,
    SubmitChallengeRequest, SubmitChallengeResponse,
    DeliverLessonResponse,
    SubscribeJourneyRequest, SubscribeJourneyResponse
)

# Repository 層
from backend.repositories.user_repository import UserRepository
from backend.repositories.lesson_repository import LessonRepository
from backend.repositories.lesson_progress_repository import LessonProgressRepository
from backend.repositories.journey_subscription_repository import JourneySubscriptionRepository

# Service 層
from backend.services.experience_service import ExperienceService
from backend.services.video_progress_service import VideoProgressService
from backend.services.challenge_service import ChallengeService
from backend.services.lesson_delivery_service import LessonDeliveryService
from backend.services.journey_subscription_service import JourneySubscriptionService

# 建立資料表
Base.metadata.create_all(bind=engine)

app = FastAPI(title="WSA Lesson Progress API")


def get_current_user_id(authorization: Optional[str] = Header(None)) -> int:
    """從 Authorization header 取得 user_id"""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="未提供認證 token")
    
    token = authorization.replace("Bearer ", "")
    try:
        user_id = decode_token(token)
        return user_id
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"無效的 token: {str(e)}")


# API Endpoints

@app.put("/api/lessons/{lesson_id}/progress")
def update_video_progress(
    lesson_id: int,
    request: UpdateVideoProgressRequest,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_current_user_id)
):
    """更新影片進度"""
    # 建立 Repository 和 Service
    lesson_repo = LessonRepository(db)
    progress_repo = LessonProgressRepository(db)
    video_service = VideoProgressService(lesson_repo, progress_repo)
    
    # 執行業務邏輯
    progress = video_service.update_progress(user_id, lesson_id, request.progress)
    
    return UpdateVideoProgressResponse(
        lessonId=lesson_id,
        progress=progress.progress,
        status=progress.status
    )


@app.post("/api/lessons/{lesson_id}/challenge")
def submit_challenge(
    lesson_id: int,
    request: SubmitChallengeRequest,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_current_user_id)
):
    """提交挑戰題作業"""
    # 建立 Repository 和 Service
    lesson_repo = LessonRepository(db)
    progress_repo = LessonProgressRepository(db)
    challenge_service = ChallengeService(lesson_repo, progress_repo)
    
    # 執行業務邏輯
    progress = challenge_service.submit_challenge(user_id, lesson_id, request.files)
    
    return SubmitChallengeResponse(
        lessonId=lesson_id,
        status=progress.status,
        message="作業提交成功"
    )


@app.post("/api/lessons/{lesson_id}/deliver")
def deliver_lesson(
    lesson_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_current_user_id)
):
    """交付課程"""
    # 建立 Repository 和 Service
    user_repo = UserRepository(db)
    lesson_repo = LessonRepository(db)
    progress_repo = LessonProgressRepository(db)
    exp_service = ExperienceService()
    delivery_service = LessonDeliveryService(user_repo, lesson_repo, progress_repo, exp_service)
    
    # 執行業務邏輯
    progress, reward = delivery_service.deliver_lesson(user_id, lesson_id)
    
    return DeliverLessonResponse(
        lessonId=lesson_id,
        status="DELIVERED",
        reward=reward
    )


@app.post("/api/users/{user_id}/subscriptions")
def subscribe_journey(
    user_id: int,
    request: SubscribeJourneyRequest,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """訂閱旅程"""
    # 建立 Repository 和 Service
    subscription_repo = JourneySubscriptionRepository(db)
    subscription_service = JourneySubscriptionService(subscription_repo)
    
    # 執行業務邏輯
    subscription_service.subscribe_journey(user_id, request.journeyId, current_user_id)
    
    return SubscribeJourneyResponse(
        journeyId=request.journeyId,
        subscribed=True
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

