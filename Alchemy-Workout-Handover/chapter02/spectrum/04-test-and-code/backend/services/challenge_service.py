"""
挑戰題服務 - 負責挑戰題作業提交業務邏輯
"""
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import LessonProgress
from backend.repositories.lesson_repository import LessonRepository
from backend.repositories.lesson_progress_repository import LessonProgressRepository
from backend.services.validation_service import ProgressValidationService


class ChallengeService:
    """挑戰題服務（符合 SRP - 單一職責原則）"""
    
    def __init__(self, lesson_repo: LessonRepository, progress_repo: LessonProgressRepository):
        self.lesson_repo = lesson_repo
        self.progress_repo = progress_repo
        self.validation_service = ProgressValidationService()
    
    def submit_challenge(self, user_id: int, lesson_id: int, files: str) -> LessonProgress:
        """提交挑戰題作業"""
        # 驗證課程
        lesson = self.lesson_repo.find_by_id(lesson_id)
        self.validation_service.validate_lesson_exists(lesson)
        self.validation_service.validate_lesson_type_for_challenge(lesson)
        
        # 查詢或建立課程進度
        progress = self.progress_repo.find_by_user_and_lesson(user_id, lesson_id)
        
        if not progress:
            progress = LessonProgress(
                user_id=user_id,
                lesson_id=lesson_id,
                status="COMPLETED",
                files=files
            )
            return self.progress_repo.create(progress)
        else:
            progress.status = "COMPLETED"
            progress.files = files
            return self.progress_repo.update(progress)

