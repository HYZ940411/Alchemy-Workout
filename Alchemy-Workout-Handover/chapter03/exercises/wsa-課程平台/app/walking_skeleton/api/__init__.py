from fastapi import APIRouter
from app.walking_skeleton.api import messages

router = APIRouter()
router.include_router(messages.router)

__all__ = ["router"]

