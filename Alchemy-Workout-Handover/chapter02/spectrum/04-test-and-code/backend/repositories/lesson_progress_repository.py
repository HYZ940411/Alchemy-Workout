"""
Lesson Progress Repository - 課程進度資料訪問
"""
from typing import Optional
from sqlalchemy.orm import Session
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import LessonProgress


class LessonProgressRepository:
    """課程進度資料倉庫"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def find_by_user_and_lesson(self, user_id: int, lesson_id: int) -> Optional[LessonProgress]:
        """根據用戶 ID 和課程 ID 查找課程進度"""
        return self.db.query(LessonProgress).filter(
            LessonProgress.user_id == user_id,
            LessonProgress.lesson_id == lesson_id
        ).first()
    
    def create(self, progress: LessonProgress) -> LessonProgress:
        """建立新課程進度"""
        self.db.add(progress)
        self.db.commit()
        self.db.refresh(progress)
        return progress
    
    def update(self, progress: LessonProgress) -> LessonProgress:
        """更新課程進度"""
        self.db.commit()
        self.db.refresh(progress)
        return progress

