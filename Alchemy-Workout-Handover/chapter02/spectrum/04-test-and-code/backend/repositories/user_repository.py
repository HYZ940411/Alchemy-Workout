"""
User Repository - 用戶資料訪問
"""
from typing import Optional
from sqlalchemy.orm import Session
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import User


class UserRepository:
    """用戶資料倉庫"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def find_by_id(self, user_id: int) -> Optional[User]:
        """根據 ID 查找用戶"""
        return self.db.query(User).filter(User.id == user_id).first()
    
    def update(self, user: User) -> User:
        """更新用戶資料"""
        self.db.commit()
        self.db.refresh(user)
        return user

