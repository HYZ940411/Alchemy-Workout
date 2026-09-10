from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.deps import get_db
from app.walking_skeleton.models.message import Message
from app.walking_skeleton.schemas.message import MessageCreate, MessageResponse, MessageListResponse

router = APIRouter()

@router.post("/messages", response_model=MessageResponse, status_code=201)
def create_message(
    message_data: MessageCreate,
    db: Session = Depends(get_db)
):
    """建立一個新的 message（Hello World 驗證用）"""
    message = Message(content=message_data.content)
    db.add(message)
    db.commit()
    db.refresh(message)
    return message

@router.get("/messages", response_model=MessageListResponse)
def list_messages(
    db: Session = Depends(get_db)
):
    """取得所有 messages"""
    messages = db.query(Message).all()
    return {
        "messages": messages,
        "total": len(messages)
    }

@router.get("/messages/{message_id}", response_model=MessageResponse)
def get_message(
    message_id: int,
    db: Session = Depends(get_db)
):
    """取得特定的 message"""
    message = db.query(Message).filter(Message.id == message_id).first()
    if not message:
        raise HTTPException(status_code=404, detail="Message not found")
    return message

@router.delete("/messages/{message_id}", status_code=204)
def delete_message(
    message_id: int,
    db: Session = Depends(get_db)
):
    """刪除 message"""
    message = db.query(Message).filter(Message.id == message_id).first()
    if not message:
        raise HTTPException(status_code=404, detail="Message not found")
    db.delete(message)
    db.commit()
    return None








