from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func
from app.models import Base

class Message(Base):
    """簡單的 Message entity 用於 walking skeleton 驗證"""
    __tablename__ = "messages"
    
    id = Column(Integer, primary_key=True, index=True)
    content = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    def __repr__(self):
        return f"<Message(id={self.id}, content='{self.content}')>"








