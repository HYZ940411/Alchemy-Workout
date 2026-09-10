"""課程相關 Repository。"""

from typing import List, Optional, Set
from sqlalchemy.orm import Session

from app.models.chapter import Chapter
from app.models.journey import Journey
from app.models.lesson import Lesson
from app.models.lesson_progress import LessonProgress
from app.models.role import Role
from app.models.user import User


class LessonRepository:
    """課程資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_id(self, lesson_id: int) -> Optional[Lesson]:
        """根據 ID 查詢課程。"""
        return self.session.query(Lesson).filter_by(id=lesson_id).first()

    def find_by_journey_id(
        self, journey_id: int, chapter_id: Optional[int] = None
    ) -> List[Lesson]:
        """根據旅程 ID 查詢課程清單。"""
        query = self.session.query(Lesson).filter(Lesson.journey_id == journey_id)
        if chapter_id:
            query = query.filter(Lesson.chapter_id == chapter_id)
        return query.order_by(Lesson.id).all()


class LessonProgressRepository:
    """課程進度資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_user_and_lesson(
        self, user_id: int, lesson_id: int
    ) -> Optional[LessonProgress]:
        """根據用戶和課程查詢進度。"""
        return self.session.query(LessonProgress).filter_by(
            user_id=user_id, lesson_id=lesson_id
        ).first()

    def find_by_user_and_lessons(
        self, user_id: int, lesson_ids: List[int]
    ) -> List[LessonProgress]:
        """根據用戶和多個課程查詢進度。"""
        return self.session.query(LessonProgress).filter(
            LessonProgress.user_id == user_id,
            LessonProgress.lesson_id.in_(lesson_ids)
        ).all()

    def save(self, progress: LessonProgress) -> LessonProgress:
        """儲存課程進度。"""
        self.session.add(progress)
        self.session.flush()
        return progress

    def commit(self):
        """提交交易。"""
        self.session.commit()

    def refresh(self, progress: LessonProgress):
        """重新載入進度。"""
        self.session.refresh(progress)


class UserRoleRepository:
    """用戶角色資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_active_roles_for_journey(
        self, user_id: int, journey_id: int
    ) -> List[Role]:
        """查詢用戶在旅程的有效角色。"""
        return self.session.query(Role).filter(
            Role.user_id == user_id,
            Role.journey_id == journey_id,
            Role.revoked_at.is_(None)
        ).all()

    def get_role_types(self, user_id: int, journey_id: int) -> Set[str]:
        """取得用戶在旅程的角色類型集合。"""
        roles = self.find_active_roles_for_journey(user_id, journey_id)
        return {role.role_type for role in roles}


class UserRepository:
    """用戶資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_id(self, user_id: int) -> Optional[User]:
        """根據 ID 查詢用戶。"""
        return self.session.query(User).filter_by(id=user_id).first()

    def commit(self):
        """提交交易。"""
        self.session.commit()


class JourneyRepository:
    """旅程資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_id(self, journey_id: int) -> Optional[Journey]:
        """根據 ID 查詢旅程。"""
        return self.session.query(Journey).filter_by(id=journey_id).first()


class ChapterRepository:
    """章節資料存取層。"""

    def __init__(self, session: Session):
        self.session = session

    def find_by_ids(self, chapter_ids: Set[int]) -> List[Chapter]:
        """根據 ID 集合查詢章節。"""
        return self.session.query(Chapter).filter(Chapter.id.in_(chapter_ids)).all()
