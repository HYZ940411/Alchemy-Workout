"""LessonProgress Model."""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models import Base


class LessonProgress(Base):
    """課程進度實體。"""

    __tablename__ = "lesson_progress"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("users.id"), nullable=False
    )
    lesson_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("lessons.id"), nullable=False
    )
    progress: Mapped[int] = mapped_column(Integer, default=0, doc="進度百分比 0-100")
    status: Mapped[str] = mapped_column(
        String, nullable=False, doc="進行中、已完成、已交付"
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now()
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="lesson_progresses")
    lesson: Mapped["Lesson"] = relationship(
        "Lesson", back_populates="lesson_progresses"
    )

    __table_args__ = (
        UniqueConstraint("user_id", "lesson_id", name="uq_lesson_progress_user_lesson"),
        Index("ix_lesson_progress_user_id", "user_id"),
        Index("ix_lesson_progress_lesson_id", "lesson_id"),
    )
