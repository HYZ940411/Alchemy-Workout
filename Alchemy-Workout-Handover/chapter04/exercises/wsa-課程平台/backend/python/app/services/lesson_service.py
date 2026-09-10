"""課程相關 Service。"""

from dataclasses import dataclass
from typing import List, Optional

from app.exceptions import BusinessError
from app.models.lesson_progress import LessonProgress
from app.repositories.lesson_repository import (
    ChapterRepository,
    JourneyRepository,
    LessonProgressRepository,
    LessonRepository,
    UserRepository,
    UserRoleRepository,
)


REQUIRED_ROLES = {"旅程購買", "旅程訂閱狀態"}


def calculate_level(exp: int) -> int:
    """根據經驗值計算等級。每150經驗值升一級。"""
    return (exp // 150) + 1


@dataclass
class UpdateProgressResult:
    """更新進度結果。"""
    lesson_id: int
    progress: int
    status: str


@dataclass
class SubmitChallengeResult:
    """提交挑戰題結果。"""
    lesson_id: int
    status: str


@dataclass
class LessonProgressResult:
    """課程進度查詢結果。"""
    user_name: str
    lesson_id: int
    lesson_name: str
    lesson_type: str
    progress: int
    status: str


@dataclass
class DeliverLessonResult:
    """交付課程結果。"""
    lesson_id: int
    status: str
    exp_gained: int
    new_level: int
    leveled_up: bool


@dataclass
class LessonListItem:
    """課程清單項目。"""
    lesson_id: int
    name: str
    type: str
    chapter_name: str
    reward_exp: int
    progress: int
    status: str


class LessonService:
    """課程業務邏輯服務。"""

    def __init__(
        self,
        lesson_repo: LessonRepository,
        progress_repo: LessonProgressRepository,
        role_repo: UserRoleRepository,
        user_repo: UserRepository,
        journey_repo: JourneyRepository,
        chapter_repo: ChapterRepository,
    ):
        self.lesson_repo = lesson_repo
        self.progress_repo = progress_repo
        self.role_repo = role_repo
        self.user_repo = user_repo
        self.journey_repo = journey_repo
        self.chapter_repo = chapter_repo

    def _check_journey_access(self, user_id: int, journey_id: int):
        """檢查用戶是否有權限存取旅程。"""
        role_types = self.role_repo.get_role_types(user_id, journey_id)
        if not REQUIRED_ROLES.issubset(role_types):
            raise BusinessError("權限不足", status_code=403)

    def update_video_progress(
        self, lesson_id: int, user_id: int, progress: int
    ) -> UpdateProgressResult:
        """更新課程的影片進度。"""
        lesson = self.lesson_repo.find_by_id(lesson_id)
        if not lesson:
            raise BusinessError("課程不存在", status_code=404)

        self._check_journey_access(user_id, lesson.journey_id)

        if progress < 0 or progress > 100:
            raise BusinessError("進度值必須在 0-100 之間")

        progress_record = self.progress_repo.find_by_user_and_lesson(user_id, lesson_id)

        if not progress_record:
            progress_record = LessonProgress(
                user_id=user_id,
                lesson_id=lesson_id,
                progress=0,
                status="進行中"
            )
            self.progress_repo.save(progress_record)

        if progress < progress_record.progress:
            raise BusinessError("進度不可倒退")

        progress_record.progress = progress

        if progress_record.status != "已交付":
            if progress >= 100:
                progress_record.status = "已完成"
            else:
                progress_record.status = "進行中"

        self.progress_repo.commit()
        self.progress_repo.refresh(progress_record)

        return UpdateProgressResult(
            lesson_id=lesson_id,
            progress=progress_record.progress,
            status=progress_record.status
        )

    def submit_challenge(self, lesson_id: int, user_id: int) -> SubmitChallengeResult:
        """提交挑戰題課程的作業。"""
        lesson = self.lesson_repo.find_by_id(lesson_id)
        if not lesson:
            raise BusinessError("課程不存在", status_code=404)

        if lesson.type != "挑戰題課程":
            raise BusinessError("只能提交挑戰題課程的作業")

        self._check_journey_access(user_id, lesson.journey_id)

        progress_record = self.progress_repo.find_by_user_and_lesson(user_id, lesson_id)

        if not progress_record:
            progress_record = LessonProgress(
                user_id=user_id,
                lesson_id=lesson_id,
                progress=100,
                status="已完成"
            )
            self.progress_repo.save(progress_record)
        else:
            progress_record.progress = 100
            progress_record.status = "已完成"

        self.progress_repo.commit()
        self.progress_repo.refresh(progress_record)

        return SubmitChallengeResult(
            lesson_id=lesson_id,
            status=progress_record.status
        )

    def get_lesson_progress(
        self, lesson_id: int, user_id: int
    ) -> LessonProgressResult:
        """查詢課程進度。"""
        lesson = self.lesson_repo.find_by_id(lesson_id)
        if not lesson:
            raise BusinessError("課程不存在", status_code=404)

        self._check_journey_access(user_id, lesson.journey_id)

        user = self.user_repo.find_by_id(user_id)
        progress_record = self.progress_repo.find_by_user_and_lesson(user_id, lesson_id)

        if progress_record:
            return LessonProgressResult(
                user_name=user.name,
                lesson_id=lesson_id,
                lesson_name=lesson.name,
                lesson_type=lesson.type,
                progress=progress_record.progress,
                status=progress_record.status
            )
        else:
            return LessonProgressResult(
                user_name=user.name,
                lesson_id=lesson_id,
                lesson_name=lesson.name,
                lesson_type=lesson.type,
                progress=0,
                status="未開始"
            )

    def deliver_lesson(self, lesson_id: int, user_id: int) -> DeliverLessonResult:
        """交付課程並獲得獎勵。"""
        lesson = self.lesson_repo.find_by_id(lesson_id)
        if not lesson:
            raise BusinessError("課程不存在", status_code=404)

        self._check_journey_access(user_id, lesson.journey_id)

        progress_record = self.progress_repo.find_by_user_and_lesson(user_id, lesson_id)

        if not progress_record:
            raise BusinessError("尚未開始此課程")

        if progress_record.status == "已交付":
            raise BusinessError("課程已交付")

        if progress_record.status != "已完成":
            raise BusinessError("課程尚未完成")

        user = self.user_repo.find_by_id(user_id)
        old_level = user.level

        exp_gained = lesson.reward_exp
        user.exp += exp_gained

        new_level = calculate_level(user.exp)
        user.level = new_level

        progress_record.status = "已交付"

        self.user_repo.commit()

        return DeliverLessonResult(
            lesson_id=lesson_id,
            status="已交付",
            exp_gained=exp_gained,
            new_level=new_level,
            leveled_up=new_level > old_level
        )

    def get_lesson_list(
        self, journey_id: int, user_id: int, chapter_id: Optional[int] = None
    ) -> List[LessonListItem]:
        """查詢旅程的課程清單。"""
        journey = self.journey_repo.find_by_id(journey_id)
        if not journey:
            raise BusinessError("旅程不存在", status_code=404)

        self._check_journey_access(user_id, journey_id)

        lessons = self.lesson_repo.find_by_journey_id(journey_id, chapter_id)

        lesson_ids = [lesson.id for lesson in lessons]
        progress_records = self.progress_repo.find_by_user_and_lessons(
            user_id, lesson_ids
        )
        progress_map = {pr.lesson_id: pr for pr in progress_records}

        chapter_ids = {lesson.chapter_id for lesson in lessons}
        chapters = self.chapter_repo.find_by_ids(chapter_ids)
        chapter_map = {ch.id: ch.name for ch in chapters}

        result = []
        for lesson in lessons:
            progress_record = progress_map.get(lesson.id)
            if progress_record:
                progress = progress_record.progress
                lesson_status = progress_record.status
            else:
                progress = 0
                lesson_status = "未開始"

            result.append(LessonListItem(
                lesson_id=lesson.id,
                name=lesson.name,
                type=lesson.type,
                chapter_name=chapter_map.get(lesson.chapter_id, ""),
                reward_exp=lesson.reward_exp,
                progress=progress,
                status=lesson_status
            ))

        return result
