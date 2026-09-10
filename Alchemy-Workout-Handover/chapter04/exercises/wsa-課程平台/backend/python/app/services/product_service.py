"""商品相關 Service。"""

from dataclasses import dataclass
from typing import List, Optional

from app.exceptions import BusinessError
from app.repositories.order_repository import ProductRepository


VALID_STATUSES = {"上架中", "已下架"}


@dataclass
class PlanItemResult:
    """方案項目結果。"""
    plan_type: str
    journey_id: Optional[int]
    subscription_days: Optional[int]


@dataclass
class ProductListItemResult:
    """商品清單項目結果。"""
    product_id: int
    name: str
    price: int
    description: Optional[str]
    status: str
    plan_items: List[PlanItemResult]


class ProductService:
    """商品業務邏輯服務。"""

    def __init__(self, product_repo: ProductRepository):
        self.product_repo = product_repo

    def get_product_list(
        self, status_filter: Optional[str] = None
    ) -> List[ProductListItemResult]:
        """查詢商品清單。"""
        if status_filter and status_filter not in VALID_STATUSES:
            raise BusinessError("無效的狀態值")

        products = self.product_repo.find_all(status_filter)

        result = []
        for product in products:
            plan_items = []
            for item in product.plan_items or []:
                plan_items.append(PlanItemResult(
                    plan_type=item.get("plan_type"),
                    journey_id=item.get("journey_id"),
                    subscription_days=item.get("subscription_days")
                ))

            result.append(ProductListItemResult(
                product_id=product.id,
                name=product.name,
                price=int(product.price),
                description=product.description,
                status=product.status,
                plan_items=plan_items
            ))

        return result
