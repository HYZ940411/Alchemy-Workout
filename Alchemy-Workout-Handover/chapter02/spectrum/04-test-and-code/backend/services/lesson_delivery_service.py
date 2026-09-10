"""
課程交付服務 - 負責課程交付和經驗值獎勵業務邏輯
"""
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import User, LessonProgress
from backend.repositories.user_repository import UserRepository
from backend.repositories.lesson_repository import LessonRepository
from backend.repositories.lesson_progress_repository import LessonProgressRepository
from backend.services.validation_service import ProgressValidationService
from backend.services.experience_service import ExperienceService


class LessonDeliveryService:
    """課程交付服務（符合 SRP - 單一職責原則）"""
    
    def __init__(
        self, 
        user_repo: UserRepository, 
        lesson_repo: LessonRepository, 
        progress_repo: LessonProgressRepository,
        exp_service: ExperienceService
    ):
        self.user_repo = user_repo
        self.lesson_repo = lesson_repo
        self.progress_repo = progress_repo
        self.exp_service = exp_service
        self.validation_service = ProgressValidationService()
    
    def deliver_lesson(self, user_id: int, lesson_id: int) -> tuple[LessonProgress, dict]:
        """交付課程並獲得獎勵"""
        # 驗證課程存在
        lesson = self.lesson_repo.find_by_id(lesson_id)
        self.validation_service.validate_lesson_exists(lesson)
        
        # 驗證課程進度
        progress = self.progress_repo.find_by_user_and_lesson(user_id, lesson_id)
        self.validation_service.validate_lesson_completed(progress)
        self.validation_service.validate_not_delivered(progress)
        
        # 取得用戶
        user = self.user_repo.find_by_id(user_id)
        self.validation_service.validate_user_exists(user)
        
        # 計算獎勵
        old_exp = user.exp
        new_exp = old_exp + lesson.reward_exp
        reward = self.exp_service.calculate_level_up(old_exp, new_exp)
        
        # 更新用戶經驗值和等級
        user.exp = new_exp
        user.level = reward["newLevel"]
        self.user_repo.update(user)
        
        # 更新課程狀態為已交付
        progress.status = "DELIVERED"
        self.progress_repo.update(progress)
        
        return progress, reward

