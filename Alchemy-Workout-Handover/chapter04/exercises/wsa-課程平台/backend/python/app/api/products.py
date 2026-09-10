"""商品相關 API 端點。"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_db, get_current_user_id
from app.exceptions import BusinessError
from app.repositories.order_repository import ProductRepository
from app.services.product_service import ProductService

router = APIRouter()


class PlanItem(BaseModel):
    """方案項目。"""
    plan_type: str
    journey_id: Optional[int] = None
    subscription_days: Optional[int] = None


class ProductListItem(BaseModel):
    """商品清單項目。"""
    product_id: int
    name: str
    price: int
    description: Optional[str] = None
    status: str
    plan_items: List[PlanItem]


class ProductListResponse(BaseModel):
    """商品清單回應。"""
    products: List[ProductListItem]


def get_product_service(db: Session = Depends(get_db)) -> ProductService:
    """取得商品服務實例。"""
    return ProductService(product_repo=ProductRepository(db))


@router.get("", response_model=ProductListResponse)
def get_product_list(
    status_filter: Optional[str] = Query(None, alias="status"),
    user_id: int = Depends(get_current_user_id),
    service: ProductService = Depends(get_product_service),
):
    """查詢商品清單。"""
    try:
        result = service.get_product_list(status_filter)
        return ProductListResponse(
            products=[
                ProductListItem(
                    product_id=item.product_id,
                    name=item.name,
                    price=item.price,
                    description=item.description,
                    status=item.status,
                    plan_items=[
                        PlanItem(
                            plan_type=pi.plan_type,
                            journey_id=pi.journey_id,
                            subscription_days=pi.subscription_days
                        )
                        for pi in item.plan_items
                    ]
                )
                for item in result
            ]
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)
