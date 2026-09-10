"""角色相關 Service。"""

from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional

from app.exceptions import BusinessError
from app.repositories.lesson_repository import JourneyRepository


@dataclass
class RoleResult:
    """角色結果。"""
    role_id: int
    role_type: str
    journey_id: int
    journey_name: str
    granted_at: datetime


class RoleQueryRepository:
    """角色查詢資料存取層。"""

    def __init__(self, session):
        from app.models.role import Role
        self.session = session
        self.Role = Role

    def find_active_roles_by_user(self, user_id: int):
        """查詢用戶的有效角色。"""
        return self.session.query(self.Role).filter(
            self.Role.user_id == user_id,
            self.Role.revoked_at.is_(None)
        ).all()


class RoleService:
    """角色業務邏輯服務。"""

    def __init__(
        self,
        role_repo: RoleQueryRepository,
        journey_repo: JourneyRepository,
    ):
        self.role_repo = role_repo
        self.journey_repo = journey_repo

    def get_roles(
        self, current_user_id: int, target_user_id: Optional[int] = None
    ) -> List[RoleResult]:
        """查詢用戶角色清單。"""
        user_id = target_user_id if target_user_id else current_user_id

        if user_id != current_user_id:
            raise BusinessError("權限不足", status_code=403)

        roles = self.role_repo.find_active_roles_by_user(user_id)

        result = []
        for role in roles:
            journey = self.journey_repo.find_by_id(role.journey_id)
            journey_name = journey.name if journey else ""

            result.append(RoleResult(
                role_id=role.id,
                role_type=role.role_type,
                journey_id=role.journey_id,
                journey_name=journey_name,
                granted_at=role.granted_at
            ))

        return result
