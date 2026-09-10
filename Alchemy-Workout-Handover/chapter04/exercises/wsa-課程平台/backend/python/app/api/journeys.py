"""旅程相關 API 端點。"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
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


class LessonListItem(BaseModel):
    """課程清單項目。"""
    lesson_id: int
    name: str
    type: str
    chapter_name: str
    reward_exp: int
    progress: int
    status: str


class LessonListResponse(BaseModel):
    """課程清單回應。"""
    lessons: List[LessonListItem]


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


@router.get("/{journey_id}/lessons", response_model=LessonListResponse)
def get_lesson_list(
    journey_id: int,
    chapter_id: Optional[int] = Query(None),
    user_id: int = Depends(get_current_user_id),
    service: LessonService = Depends(get_lesson_service),
):
    """查詢旅程的課程清單。"""
    try:
        result = service.get_lesson_list(journey_id, user_id, chapter_id)
        return LessonListResponse(
            lessons=[
                LessonListItem(
                    lesson_id=item.lesson_id,
                    name=item.name,
                    type=item.type,
                    chapter_name=item.chapter_name,
                    reward_exp=item.reward_exp,
                    progress=item.progress,
                    status=item.status
                )
                for item in result
            ]
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)
