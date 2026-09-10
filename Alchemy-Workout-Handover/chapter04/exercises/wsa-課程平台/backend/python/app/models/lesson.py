"""Lesson Model."""

from sqlalchemy import ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models import Base


class Lesson(Base):
    """課程實體。"""

    __tablename__ = "lessons"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    type: Mapped[str] = mapped_column(
        String, nullable=False, doc="影片課程、問卷課程、挑戰題課程"
    )
    journey_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("journeys.id"), nullable=False
    )
    chapter_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("chapters.id"), nullable=False
    )
    reward_exp: Mapped[int] = mapped_column(Integer, default=0, doc="獎勵經驗值")

    # Relationships
    journey: Mapped["Journey"] = relationship("Journey", back_populates="lessons")
    chapter: Mapped["Chapter"] = relationship("Chapter", back_populates="lessons")
    lesson_progresses: Mapped[list["LessonProgress"]] = relationship(
        "LessonProgress", back_populates="lesson"
    )

    __table_args__ = (
        Index("ix_lessons_journey_id", "journey_id"),
        Index("ix_lessons_chapter_id", "chapter_id"),
    )
