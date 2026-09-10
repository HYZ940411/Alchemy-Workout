"""Journey Model."""

from sqlalchemy import Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models import Base


class Journey(Base):
    """旅程實體。"""

    __tablename__ = "journeys"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String, nullable=False)

    # Relationships
    chapters: Mapped[list["Chapter"]] = relationship("Chapter", back_populates="journey")
    lessons: Mapped[list["Lesson"]] = relationship("Lesson", back_populates="journey")
    roles: Mapped[list["Role"]] = relationship("Role", back_populates="journey")
