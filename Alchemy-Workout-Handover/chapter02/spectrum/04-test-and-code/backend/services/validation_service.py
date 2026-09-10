"""
課程進度驗證服務 - 負責業務規則驗證
"""
from fastapi import HTTPException
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import Lesson, LessonProgress


class ProgressValidationService:
    """進度驗證服務（符合 SRP - 單一職責原則）"""
    
    @staticmethod
    def validate_lesson_exists(lesson) -> None:
        """驗證課程是否存在"""
        if not lesson:
            raise HTTPException(status_code=404, detail="課程不存在")
    
    @staticmethod
    def validate_lesson_type_for_video(lesson: Lesson) -> None:
        """驗證是否為影片課程"""
        if lesson.type != 2:
            raise HTTPException(status_code=400, detail="只能更新影片課程的進度")
    
    @staticmethod
    def validate_lesson_type_for_challenge(lesson: Lesson) -> None:
        """驗證是否為挑戰題課程"""
        if lesson.type != 3:
            raise HTTPException(status_code=400, detail="只能為挑戰題課程提交作業")
    
    @staticmethod
    def validate_progress_range(progress: int) -> None:
        """驗證進度範圍"""
        if progress < 0 or progress > 100:
            raise HTTPException(status_code=400, detail="進度必須在 0-100 之間")
    
    @staticmethod
    def validate_progress_monotonic(current_progress: LessonProgress, new_progress: int) -> None:
        """驗證進度是否倒退"""
        if new_progress < current_progress.progress and current_progress.status != "DELIVERED":
            raise HTTPException(status_code=400, detail="進度不可倒退")
    
    @staticmethod
    def validate_lesson_completed(progress: LessonProgress) -> None:
        """驗證課程是否已完成"""
        if not progress:
            raise HTTPException(status_code=400, detail="課程進度不存在")
        
        if progress.status != "COMPLETED":
            raise HTTPException(status_code=400, detail="課程尚未完成")
    
    @staticmethod
    def validate_not_delivered(progress: LessonProgress) -> None:
        """驗證課程是否已交付"""
        if progress.status == "DELIVERED":
            raise HTTPException(status_code=400, detail="課程已交付，無法重複交付")
    
    @staticmethod
    def validate_user_exists(user) -> None:
        """驗證用戶是否存在"""
        if not user:
            raise HTTPException(status_code=404, detail="用戶不存在")
    
    @staticmethod
    def validate_subscription_permission(user_id: int, current_user_id: int) -> None:
        """驗證訂閱權限"""
        if user_id != current_user_id:
            raise HTTPException(status_code=403, detail="無權限訂閱他人旅程")

