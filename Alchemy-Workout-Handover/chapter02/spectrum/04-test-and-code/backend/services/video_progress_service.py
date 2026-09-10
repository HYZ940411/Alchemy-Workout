"""
影片進度服務 - 負責影片進度更新業務邏輯
"""
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import LessonProgress
from backend.repositories.lesson_repository import LessonRepository
from backend.repositories.lesson_progress_repository import LessonProgressRepository
from backend.services.validation_service import ProgressValidationService


class VideoProgressService:
    """影片進度服務（符合 SRP - 單一職責原則）"""
    
    def __init__(self, lesson_repo: LessonRepository, progress_repo: LessonProgressRepository):
        self.lesson_repo = lesson_repo
        self.progress_repo = progress_repo
        self.validation_service = ProgressValidationService()
    
    def update_progress(self, user_id: int, lesson_id: int, new_progress: int) -> LessonProgress:
        """更新影片進度"""
        # 驗證課程
        lesson = self.lesson_repo.find_by_id(lesson_id)
        self.validation_service.validate_lesson_exists(lesson)
        self.validation_service.validate_lesson_type_for_video(lesson)
        
        # 驗證進度範圍
        self.validation_service.validate_progress_range(new_progress)
        
        # 查詢或建立課程進度
        progress = self.progress_repo.find_by_user_and_lesson(user_id, lesson_id)
        
        if not progress:
            # 建立新進度
            progress = LessonProgress(
                user_id=user_id,
                lesson_id=lesson_id,
                progress=new_progress,
                status="IN_PROGRESS" if new_progress < 100 else "COMPLETED"
            )
            return self.progress_repo.create(progress)
        else:
            # 驗證進度不可倒退
            self.validation_service.validate_progress_monotonic(progress, new_progress)
            
            # 更新進度（已交付的課程狀態不變）
            progress.progress = new_progress
            if progress.status != "DELIVERED":
                progress.status = "COMPLETED" if new_progress == 100 else "IN_PROGRESS"
            
            return self.progress_repo.update(progress)

