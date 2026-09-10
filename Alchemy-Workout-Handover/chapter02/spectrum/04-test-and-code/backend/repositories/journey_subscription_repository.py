"""
Journey Subscription Repository - 旅程訂閱資料訪問
"""
from typing import Optional
from sqlalchemy.orm import Session
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import JourneySubscription


class JourneySubscriptionRepository:
    """旅程訂閱資料倉庫"""
    
    def __init__(self, db: Session):
        self.db = db
    
    def find_by_user_and_journey(self, user_id: int, journey_id: int) -> Optional[JourneySubscription]:
        """根據用戶 ID 和旅程 ID 查找訂閱"""
        return self.db.query(JourneySubscription).filter(
            JourneySubscription.user_id == user_id,
            JourneySubscription.journey_id == journey_id
        ).first()
    
    def create(self, subscription: JourneySubscription) -> JourneySubscription:
        """建立新訂閱"""
        self.db.add(subscription)
        self.db.commit()
        self.db.refresh(subscription)
        return subscription

