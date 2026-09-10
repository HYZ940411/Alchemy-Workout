"""User Model."""

from sqlalchemy import Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models import Base


class User(Base):
    """用戶實體。"""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    level: Mapped[int] = mapped_column(Integer, default=1, doc="用戶等級")
    exp: Mapped[int] = mapped_column(Integer, default=0, doc="經驗值")

    # Relationships
    lesson_progresses: Mapped[list["LessonProgress"]] = relationship(
        "LessonProgress", back_populates="user"
    )
    roles: Mapped[list["Role"]] = relationship("Role", back_populates="user")

    __table_args__ = (Index("ix_users_name", "name"),)
