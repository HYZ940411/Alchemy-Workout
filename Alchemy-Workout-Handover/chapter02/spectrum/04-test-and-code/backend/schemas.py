"""
後端 Pydantic Schemas

定義 API 請求和回應的資料結構
"""
from pydantic import BaseModel
from typing import Optional


# 更新影片進度
class UpdateVideoProgressRequest(BaseModel):
    progress: int


class UpdateVideoProgressResponse(BaseModel):
    lessonId: int
    progress: int
    status: str


# 提交挑戰題
class SubmitChallengeRequest(BaseModel):
    files: str


class SubmitChallengeResponse(BaseModel):
    lessonId: int
    status: str
    message: str


# 交付課程
class DeliverLessonResponse(BaseModel):
    lessonId: int
    status: str
    reward: dict


# 訂閱旅程
class SubscribeJourneyRequest(BaseModel):
    journeyId: int


class SubscribeJourneyResponse(BaseModel):
    journeyId: int
    subscribed: bool

