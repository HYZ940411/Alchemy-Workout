"""
API 呼叫輔助工具

提供 API 呼叫的封裝
"""


def call_update_video_progress(api_client, user_id: int, lesson_id: int, progress: float):
    """呼叫更新影片進度 API"""
    return api_client.update_video_progress(
        user_id=user_id,
        lesson_id=lesson_id,
        progress=progress
    )


def call_submit_questionnaire(api_client, user_id: int, lesson_id: int, form_url: str):
    """呼叫提交問卷 API"""
    return api_client.submit_questionnaire(
        user_id=user_id,
        lesson_id=lesson_id,
        form_url=form_url
    )


def call_submit_challenge(api_client, user_id: int, lesson_id: int, files: str):
    """呼叫提交挑戰題 API"""
    return api_client.submit_challenge(
        user_id=user_id,
        lesson_id=lesson_id,
        files=files
    )


def call_submit_review(api_client, user_id: int, lesson_id: int, verdict: str):
    """呼叫提交批改結果 API"""
    return api_client.submit_review(
        user_id=user_id,
        lesson_id=lesson_id,
        verdict=verdict
    )


def call_deliver_lesson(api_client, user_id: int, lesson_id: int):
    """呼叫交付課程 API"""
    return api_client.deliver_lesson(
        user_id=user_id,
        lesson_id=lesson_id
    )


def call_subscribe_journey(api_client, user_id: int, journey_id: int):
    """呼叫訂閱旅程 API"""
    return api_client.subscribe_journey(
        user_id=user_id,
        journey_id=journey_id
    )



