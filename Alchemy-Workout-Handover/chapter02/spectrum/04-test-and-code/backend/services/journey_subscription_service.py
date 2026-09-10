"""
旅程訂閱服務 - 負責旅程訂閱業務邏輯
"""
import sys
import os

# 加入測試路徑以便引用 support 模組
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from support.models import JourneySubscription
from backend.repositories.journey_subscription_repository import JourneySubscriptionRepository
from backend.services.validation_service import ProgressValidationService


class JourneySubscriptionService:
    """旅程訂閱服務（符合 SRP - 單一職責原則）"""
    
    def __init__(self, subscription_repo: JourneySubscriptionRepository):
        self.subscription_repo = subscription_repo
        self.validation_service = ProgressValidationService()
    
    def subscribe_journey(self, user_id: int, journey_id: int, current_user_id: int) -> bool:
        """訂閱旅程"""
        # 驗證權限
        self.validation_service.validate_subscription_permission(user_id, current_user_id)
        
        # 檢查是否已訂閱
        existing = self.subscription_repo.find_by_user_and_journey(user_id, journey_id)
        
        if not existing:
            subscription = JourneySubscription(
                user_id=user_id,
                journey_id=journey_id
            )
            self.subscription_repo.create(subscription)
        
        return True

