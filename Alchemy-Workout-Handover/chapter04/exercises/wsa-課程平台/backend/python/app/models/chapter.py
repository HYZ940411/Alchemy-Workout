"""Chapter Model."""

from sqlalchemy import ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models import Base


class Chapter(Base):
    """章節實體。"""

    __tablename__ = "chapters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    journey_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("journeys.id"), nullable=False
    )
    name: Mapped[str] = mapped_column(String, nullable=False)
    order_index: Mapped[int] = mapped_column(Integer, nullable=False, doc="章節順序")

    # Relationships
    journey: Mapped["Journey"] = relationship("Journey", back_populates="chapters")
    lessons: Mapped[list["Lesson"]] = relationship("Lesson", back_populates="chapter")
