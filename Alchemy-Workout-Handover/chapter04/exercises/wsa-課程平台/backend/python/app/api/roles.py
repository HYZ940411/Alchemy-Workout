"""角色相關 API 端點。"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_db, get_current_user_id
from app.exceptions import BusinessError
from app.repositories.lesson_repository import JourneyRepository
from app.services.role_service import RoleQueryRepository, RoleService

router = APIRouter()


class RoleResponse(BaseModel):
    """角色回應。"""
    role_id: int
    role_type: str
    journey_id: int
    journey_name: str
    granted_at: str


class GetRolesResponse(BaseModel):
    """角色清單回應。"""
    roles: List[RoleResponse]


def get_role_service(db: Session = Depends(get_db)) -> RoleService:
    """取得角色服務實例。"""
    return RoleService(
        role_repo=RoleQueryRepository(db),
        journey_repo=JourneyRepository(db),
    )


@router.get("", response_model=GetRolesResponse)
def get_roles(
    target_user_id: Optional[int] = Query(None, alias="user_id"),
    current_user_id: int = Depends(get_current_user_id),
    service: RoleService = Depends(get_role_service),
):
    """查詢用戶角色清單。"""
    try:
        result = service.get_roles(current_user_id, target_user_id)
        return GetRolesResponse(
            roles=[
                RoleResponse(
                    role_id=item.role_id,
                    role_type=item.role_type,
                    journey_id=item.journey_id,
                    journey_name=item.journey_name,
                    granted_at=item.granted_at.strftime('%Y-%m-%d %H:%M:%S')
                )
                for item in result
            ]
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)
