"""訂單相關 API 端點。"""

from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.deps import get_db, get_current_user_id
from app.exceptions import BusinessError
from app.repositories.order_repository import (
    CouponRepository,
    OrderItemRepository,
    OrderRepository,
    ProductRepository,
    RoleRepository,
)
from app.services.order_service import OrderItemInput, OrderService

router = APIRouter()


class OrderItemRequest(BaseModel):
    """訂單項目請求。"""
    product_id: int
    quantity: int = 1


class CreateOrderRequest(BaseModel):
    """建立訂單請求。"""
    items: List[OrderItemRequest]
    coupon_ids: Optional[List[int]] = None


class CreateOrderResponse(BaseModel):
    """建立訂單回應。"""
    order_id: int
    order_number: str
    total_price: int
    payment_deadline: str


def get_order_service(db: Session = Depends(get_db)) -> OrderService:
    """取得訂單服務實例。"""
    return OrderService(
        order_repo=OrderRepository(db),
        order_item_repo=OrderItemRepository(db),
        product_repo=ProductRepository(db),
        coupon_repo=CouponRepository(db),
        role_repo=RoleRepository(db),
    )


@router.post("", response_model=CreateOrderResponse, status_code=status.HTTP_200_OK)
def create_order(
    request: CreateOrderRequest,
    user_id: int = Depends(get_current_user_id),
    service: OrderService = Depends(get_order_service),
):
    """建立訂單。"""
    try:
        items = [
            OrderItemInput(product_id=item.product_id, quantity=item.quantity)
            for item in request.items
        ]
        result = service.create_order(user_id, items, request.coupon_ids)
        return CreateOrderResponse(
            order_id=result.order_id,
            order_number=result.order_number,
            total_price=result.total_price,
            payment_deadline=result.payment_deadline.isoformat()
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


class OrderItemResponse(BaseModel):
    """訂單項目回應。"""
    product_id: int
    product_name: str
    price: int
    quantity: int


class GetOrderResponse(BaseModel):
    """查詢訂單回應。"""
    order_id: int
    order_number: str
    status: str
    total_price: int
    created_at: str
    payment_deadline: str
    items: List[OrderItemResponse]


@router.get("/{order_number}", response_model=GetOrderResponse)
def get_order(
    order_number: str,
    user_id: int = Depends(get_current_user_id),
    service: OrderService = Depends(get_order_service),
):
    """查詢訂單。"""
    try:
        result = service.get_order(order_number, user_id)
        return GetOrderResponse(
            order_id=result.order_id,
            order_number=result.order_number,
            status=result.status,
            total_price=result.total_price,
            created_at=result.created_at.strftime('%Y-%m-%d %H:%M:%S'),
            payment_deadline=result.payment_deadline.strftime('%Y-%m-%d %H:%M:%S'),
            items=[
                OrderItemResponse(
                    product_id=item.product_id,
                    product_name=item.product_name,
                    price=int(item.price),
                    quantity=item.quantity
                )
                for item in result.items
            ]
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


class PayOrderRequest(BaseModel):
    """付款請求。"""
    payment_method: str
    provider: Optional[str] = None


class PayOrderResponse(BaseModel):
    """付款回應。"""
    payment_method: str
    amount: int
    provider: Optional[str] = None


@router.post("/{order_id}/pay", response_model=PayOrderResponse)
def pay_order(
    order_id: int,
    request: PayOrderRequest,
    user_id: int = Depends(get_current_user_id),
    service: OrderService = Depends(get_order_service),
):
    """訂單付款。"""
    try:
        result = service.pay_order(
            order_id, user_id, request.payment_method, request.provider
        )
        return PayOrderResponse(
            payment_method=result.payment_method,
            amount=result.amount,
            provider=result.provider
        )
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


class CancelOrderResponse(BaseModel):
    """取消訂單回應。"""
    message: str


@router.post("/{order_id}/cancel", response_model=CancelOrderResponse)
def cancel_order(
    order_id: int,
    user_id: int = Depends(get_current_user_id),
    service: OrderService = Depends(get_order_service),
):
    """取消訂單。"""
    try:
        service.cancel_order(order_id, user_id)
        return CancelOrderResponse(message="訂單已取消")
    except BusinessError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)
