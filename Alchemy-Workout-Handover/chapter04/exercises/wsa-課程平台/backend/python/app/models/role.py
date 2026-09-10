"""Role Model."""

from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models import Base


class Role(Base):
    """角色實體。

    記錄用戶在特定旅程中的角色。

    role_type 中英對照：
    - 旅程購買 (journey_purchased): 已購買旅程（完成付款的訂單）
    - 旅程訂閱狀態 (journey_subscription): 旅程訂閱中（有效的訂閱資格）
    - 旅程老師 (journey_teacher): 旅程老師

    約束：
    - 同一用戶在同一旅程中不可重複擁有同一 role_type
    - revoked_at 為 null 時表示角色有效
    """

    __tablename__ = "roles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False
    )
    role_type: Mapped[str] = mapped_column(
        String,
        nullable=False,
        doc="journey_purchased, journey_subscription, journey_teacher",
    )
    journey_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("journeys.id"), nullable=False, doc="關聯的旅程 ID"
    )
    granted_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), doc="授予時間"
    )
    revoked_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime, nullable=True, doc="撤銷時間，null 表示角色仍有效"
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="roles")
    journey: Mapped["Journey"] = relationship("Journey", back_populates="roles")

    __table_args__ = (
        UniqueConstraint(
            "user_id", "role_type", "journey_id", name="uq_roles_user_role_journey"
        ),
        Index("ix_roles_user_id", "user_id"),
        Index("ix_roles_journey_id", "journey_id"),
        Index("ix_roles_role_type", "role_type"),
    )
