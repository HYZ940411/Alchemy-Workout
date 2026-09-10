"""SQLAlchemy ORM Models。

此模組定義所有 SQLAlchemy ORM Models。
E2E 測試和生產環境都使用這些 Models。

Base 是所有 Model 的基類，用於 Alembic 自動偵測 schema 變更。
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """SQLAlchemy ORM Base Class。"""
    pass


# 匯入所有 Models（讓 Alembic 可以偵測）
# from app.models.user import User
# from app.models.lesson_progress import LessonProgress
# ...

__all__ = ["Base"]
