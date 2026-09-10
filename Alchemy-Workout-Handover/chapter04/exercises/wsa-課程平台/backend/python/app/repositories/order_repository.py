"""訂單相關 Repository。"""

from typing import List, Optional
from sqlalchemy.orm import Session

from app.models.coupon import Coupon
from app.models.order import Order
from app.models.order_item import OrderItem
from app.models.product import Product
from app.models.role import Role


class OrderRepository:
    """訂單資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_id(self, order_id: int) -> Optional[Order]:
        """根據 ID 查詢訂單。"""
        return self.session.query(Order).filter_by(id=order_id).first()

    def find_by_order_number(self, order_number: str) -> Optional[Order]:
        """根據訂單編號查詢訂單。"""
        return self.session.query(Order).filter_by(order_number=order_number).first()

    def save(self, order: Order) -> Order:
        """儲存訂單。"""
        self.session.add(order)
        self.session.flush()
        return order

    def commit(self):
        """提交交易。"""
        self.session.commit()

    def refresh(self, order: Order):
        """重新載入訂單。"""
        self.session.refresh(order)


class OrderItemRepository:
    """訂單項目資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_order_id(self, order_id: int) -> List[OrderItem]:
        """根據訂單 ID 查詢訂單項目。"""
        return self.session.query(OrderItem).filter_by(order_id=order_id).all()

    def save(self, order_item: OrderItem) -> OrderItem:
        """儲存訂單項目。"""
        self.session.add(order_item)
        return order_item


class ProductRepository:
    """商品資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_id(self, product_id: int) -> Optional[Product]:
        """根據 ID 查詢商品。"""
        return self.session.query(Product).filter_by(id=product_id).first()

    def find_all(self, status_filter: Optional[str] = None) -> List[Product]:
        """查詢所有商品，可選擇按狀態篩選。"""
        query = self.session.query(Product)
        if status_filter:
            query = query.filter(Product.status == status_filter)
        return query.order_by(Product.id).all()


class CouponRepository:
    """折扣券資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_id(self, coupon_id: int) -> Optional[Coupon]:
        """根據 ID 查詢折扣券。"""
        return self.session.query(Coupon).filter_by(id=coupon_id).first()

    def find_by_order_id(self, order_id: int) -> List[Coupon]:
        """根據訂單 ID 查詢折扣券。"""
        return self.session.query(Coupon).filter_by(order_id=order_id).all()


class RoleRepository:
    """角色資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_active_role(
        self, user_id: int, journey_id: int, role_type: str
    ) -> Optional[Role]:
        """查詢有效角色。"""
        return self.session.query(Role).filter(
            Role.user_id == user_id,
            Role.journey_id == journey_id,
            Role.role_type == role_type,
            Role.revoked_at.is_(None)
        ).first()

    def save(self, role: Role) -> Role:
        """儲存角色。"""
        self.session.add(role)
        return role
