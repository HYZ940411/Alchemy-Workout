"""課程相關 API 端點。"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_db, get_current_user_id
from app.exceptions import BusinessError
from app.repositories.lesson_repository import (
    ChapterRepository,
    JourneyRepository,
    LessonProgressRepository,
    LessonRepository,
    UserRepository,
    UserRoleRepository,
)
from app.services.lesson_service import LessonService

router = APIRouter()


class UpdateProgressRequest(BaseModel):
    """更新進度請求。"""
    progress: int


class UpdateProgressResponse(BaseModel):
    """更新進度回應。"""
    lesson_id: int
    progress: int
    status: str


def get_lesson_service(db: Session = Depends(get_db)) -> LessonService:
    """取得課程服務實例。"""
    return LessonService(
        lesson_repo=LessonRepository(db),
        progress_repo=LessonProgressRepository(db),
        role_repo=UserRoleRepository(db),
        user_repo=UserRepository(db),
        journey_repo=JourneyRepository(db),
        chapter_repo=ChapterRepository(db),
    )


@router.put("/{lesson_id}/progress", response_model=UpdateProgressResponse)
def update_video_progress(
    lesson_id: int,
    request: UpdateProgressRequest,
    user_id: int = Depends(get_current_user_id),
    service: LessonService = Depends(get_lesson_service),
):
    """更新課程的影片進度。"""
    try:
        result = service.update_video_progress(lesson_id, user_id, request.progress)
        return UpdateProgressResponse(
            lesson_id=result.lesson_id,
            progress=result.progress,
            status=result.status
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


class SubmitChallengeResponse(BaseModel):
    """提交挑戰題作業回應。"""
    lesson_id: int
    status: str


@router.post("/{lesson_id}/submit-challenge", response_model=SubmitChallengeResponse)
def submit_challenge(
    lesson_id: int,
    user_id: int = Depends(get_current_user_id),
    service: LessonService = Depends(get_lesson_service),
):
    """提交挑戰題課程的作業。"""
    try:
        result = service.submit_challenge(lesson_id, user_id)
        return SubmitChallengeResponse(
            lesson_id=result.lesson_id,
            status=result.status
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


class LessonProgressResponse(BaseModel):
    """課程進度查詢回應。"""
    user_name: str
    lesson_id: int
    lesson_name: str
    lesson_type: str
    progress: int
    status: str


@router.get("/{lesson_id}/progress", response_model=LessonProgressResponse)
def get_lesson_progress(
    lesson_id: int,
    user_id: int = Depends(get_current_user_id),
    service: LessonService = Depends(get_lesson_service),
):
    """查詢課程進度。"""
    try:
        result = service.get_lesson_progress(lesson_id, user_id)
        return LessonProgressResponse(
            user_name=result.user_name,
            lesson_id=result.lesson_id,
            lesson_name=result.lesson_name,
            lesson_type=result.lesson_type,
            progress=result.progress,
            status=result.status
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


class DeliverLessonResponse(BaseModel):
    """交付課程回應。"""
    lesson_id: int
    status: str
    exp_gained: int
    new_level: int
    leveled_up: bool


@router.post("/{lesson_id}/deliver", response_model=DeliverLessonResponse)
def deliver_lesson(
    lesson_id: int,
    user_id: int = Depends(get_current_user_id),
    service: LessonService = Depends(get_lesson_service),
):
    """交付課程並獲得獎勵。"""
    try:
        result = service.deliver_lesson(lesson_id, user_id)
        return DeliverLessonResponse(
            lesson_id=result.lesson_id,
            status=result.status,
            exp_gained=result.exp_gained,
            new_level=result.new_level,
            leveled_up=result.leveled_up
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)
