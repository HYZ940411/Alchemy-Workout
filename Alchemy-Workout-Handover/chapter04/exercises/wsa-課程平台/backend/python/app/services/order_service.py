"""訂單相關 Service。"""

import random
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Optional

from app.exceptions import BusinessError
from app.models.order import Order
from app.models.order_item import OrderItem
from app.models.role import Role
from app.repositories.order_repository import (
    CouponRepository,
    OrderItemRepository,
    OrderRepository,
    ProductRepository,
    RoleRepository,
)


@dataclass
class OrderItemInput:
    """訂單項目輸入。"""
    product_id: int
    quantity: int = 1


@dataclass
class CreateOrderResult:
    """建立訂單結果。"""
    order_id: int
    order_number: str
    total_price: int
    payment_deadline: datetime


@dataclass
class GetOrderResult:
    """查詢訂單結果。"""
    order_id: int
    order_number: str
    status: str
    total_price: int
    created_at: datetime
    payment_deadline: datetime
    items: List[OrderItem]


@dataclass
class PayOrderResult:
    """付款結果。"""
    payment_method: str
    amount: int
    provider: Optional[str]


def generate_order_number() -> str:
    """生成 18 位數字訂單編號。"""
    timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
    random_part = str(random.randint(1000, 9999))
    return timestamp + random_part


class OrderService:
    """訂單業務邏輯服務。"""

    def __init__(
        self,
        order_repo: OrderRepository,
        order_item_repo: OrderItemRepository,
        product_repo: ProductRepository,
        coupon_repo: CouponRepository,
        role_repo: RoleRepository,
    ):
        self.order_repo = order_repo
        self.order_item_repo = order_item_repo
        self.product_repo = product_repo
        self.coupon_repo = coupon_repo
        self.role_repo = role_repo

    def create_order(
        self,
        user_id: int,
        items: List[OrderItemInput],
        coupon_ids: Optional[List[int]] = None,
    ) -> CreateOrderResult:
        """建立訂單。"""
        # 檢查訂單項目是否重複
        product_ids = [item.product_id for item in items]
        if len(product_ids) != len(set(product_ids)):
            raise BusinessError("訂單項目重複")

        # 取得所有商品並計算總價
        products = {}
        total_price = 0

        for item in items:
            product = self.product_repo.find_by_id(item.product_id)
            if not product:
                raise BusinessError("商品不存在")
            if product.status == "已下架":
                raise BusinessError("商品已下架")

            # 檢查用戶是否已購買旅程
            for plan_item in product.plan_items or []:
                if plan_item.get("plan_type") == "旅程購買":
                    journey_id = plan_item.get("journey_id")
                    if journey_id:
                        existing_role = self.role_repo.find_active_role(
                            user_id, journey_id, "旅程購買"
                        )
                        if existing_role:
                            raise BusinessError("已購買此旅程，無法再次購買包含首購的商品")

            products[item.product_id] = product
            total_price += int(product.price) * item.quantity

        # 處理折扣券
        coupons_to_use = []
        if coupon_ids:
            for coupon_id in coupon_ids:
                coupon = self.coupon_repo.find_by_id(coupon_id)
                if not coupon:
                    raise BusinessError("折扣券無效")
                if coupon.user_id != user_id:
                    raise BusinessError("折扣券無效")
                if coupon.expired_at and coupon.expired_at < datetime.now():
                    raise BusinessError("折扣券無效")
                if coupon.order_id is not None:
                    raise BusinessError("折扣券已使用")
                coupons_to_use.append(coupon)

        # 計算折扣後價格
        discounted_price = total_price
        voucher_discount = 0

        for coupon in coupons_to_use:
            if coupon.type == "折扣":
                discounted_price = int(discounted_price * float(coupon.value))
            elif coupon.type == "抵用券":
                voucher_discount += int(coupon.value)

        final_price = discounted_price - voucher_discount
        if final_price < 0:
            final_price = 0

        # 建立訂單
        order_number = generate_order_number()
        payment_deadline = datetime.now() + timedelta(days=3)

        order = Order(
            user_id=user_id,
            order_number=order_number,
            status="待付款",
            total_price=final_price,
            payment_deadline=payment_deadline
        )
        self.order_repo.save(order)

        # 建立訂單項目
        for item in items:
            product = products[item.product_id]
            order_item = OrderItem(
                order_id=order.id,
                product_id=item.product_id,
                product_name=product.name,
                price=int(product.price),
                quantity=item.quantity
            )
            self.order_item_repo.save(order_item)

        # 標記折扣券已使用
        for coupon in coupons_to_use:
            coupon.order_id = order.id

        self.order_repo.commit()
        self.order_repo.refresh(order)

        return CreateOrderResult(
            order_id=order.id,
            order_number=order.order_number,
            total_price=int(order.total_price),
            payment_deadline=order.payment_deadline
        )

    def get_order(self, order_number: str, user_id: int) -> GetOrderResult:
        """查詢訂單。"""
        order = self.order_repo.find_by_order_number(order_number)
        if not order:
            raise BusinessError("訂單不存在", status_code=404)

        if order.user_id != user_id:
            raise BusinessError("權限不足", status_code=403)

        items = self.order_item_repo.find_by_order_id(order.id)

        return GetOrderResult(
            order_id=order.id,
            order_number=order.order_number,
            status=order.status,
            total_price=int(order.total_price),
            created_at=order.created_at,
            payment_deadline=order.payment_deadline,
            items=items
        )

    def pay_order(
        self,
        order_id: int,
        user_id: int,
        payment_method: str,
        provider: Optional[str] = None
    ) -> PayOrderResult:
        """訂單付款。"""
        from app.models.payment_request import PaymentRequest

        order = self.order_repo.find_by_id(order_id)
        if not order:
            raise BusinessError("訂單不存在")

        if order.user_id != user_id:
            raise BusinessError("權限不足", status_code=403)

        if order.status != "已建立":
            raise BusinessError("訂單狀態不允許付款")

        # 建立付款請求記錄
        payment_request = PaymentRequest(
            order_id=order.id,
            payment_method=payment_method,
            payment_provider=provider,
            amount=int(order.total_price)
        )
        self.order_repo.session.add(payment_request)

        # 更新訂單狀態
        order.status = "處理中"

        # 取得訂單項目並授予角色
        order_items = self.order_item_repo.find_by_order_id(order.id)

        for item in order_items:
            product = self.product_repo.find_by_id(item.product_id)
            if product and product.plan_items:
                for plan_item in product.plan_items:
                    plan_type = plan_item.get("plan_type")
                    journey_id = plan_item.get("journey_id")

                    if plan_type and journey_id:
                        if plan_type == "旅程購買":
                            existing = self.role_repo.find_active_role(
                                user_id, journey_id, "旅程購買"
                            )
                            if not existing:
                                role = Role(
                                    user_id=user_id,
                                    role_type="旅程購買",
                                    journey_id=journey_id
                                )
                                self.role_repo.save(role)

                        elif plan_type == "旅程訂閱":
                            existing = self.role_repo.find_active_role(
                                user_id, journey_id, "旅程訂閱狀態"
                            )
                            if not existing:
                                role = Role(
                                    user_id=user_id,
                                    role_type="旅程訂閱狀態",
                                    journey_id=journey_id
                                )
                                self.role_repo.save(role)

        self.order_repo.commit()

        return PayOrderResult(
            payment_method=payment_method,
            amount=int(order.total_price),
            provider=provider
        )

    def cancel_order(self, order_id: int, user_id: int) -> None:
        """取消訂單。"""
        order = self.order_repo.find_by_id(order_id)
        if not order:
            raise BusinessError("訂單不存在")

        if order.user_id != user_id:
            raise BusinessError("權限不足", status_code=403)

        if order.status not in ["已建立", "處理中"]:
            raise BusinessError("訂單狀態不允許取消")

        # 更新訂單狀態
        order.status = "已取消"

        # 釋放使用的折扣券
        coupons = self.coupon_repo.find_by_order_id(order.id)
        for coupon in coupons:
            coupon.order_id = None

        self.order_repo.commit()
