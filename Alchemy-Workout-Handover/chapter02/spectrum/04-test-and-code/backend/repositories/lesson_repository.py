"""
Lesson Repository - 課程資料訪問
"""
from typing import Optional
from sqlalchemy.orm import Session
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import Lesson


class LessonRepository:
    """課程資料倉庫"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def find_by_id(self, lesson_id: int) -> Optional[Lesson]:
        """根據 ID 查找課程"""
        return self.db.query(Lesson).filter(Lesson.lesson_id == lesson_id).first()

