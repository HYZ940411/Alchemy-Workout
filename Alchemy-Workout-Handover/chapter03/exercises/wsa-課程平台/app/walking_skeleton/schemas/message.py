from pydantic import BaseModel, ConfigDict
from datetime import datetime
from typing import Optional

class MessageCreate(BaseModel):
    """建立 Message 的請求"""
    content: str

class MessageResponse(BaseModel):
    """Message 回應"""
    model_config = ConfigDict(from_attributes=True)

    id: int
    content: str
    created_at: datetime

class MessageListResponse(BaseModel):
    """Message 列表回應"""
    messages: list[MessageResponse]
    total: int








