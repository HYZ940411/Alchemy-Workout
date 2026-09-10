"""
SQLAlchemy 資料庫模型定義

定義課程平台的所有資料庫實體：
- User: 用戶
- Journey: 旅程
- Chapter: 章節
- Lesson: 課程
- LessonProgress: 課程進度
- JourneySubscription: 旅程訂閱
"""
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()


class User(Base):
    """用戶"""
    __tablename__ = 'users'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False)
    level = Column(Integer, default=1)
    exp = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)
    
    # 關聯
    lesson_progresses = relationship('LessonProgress', back_populates='user')
    journey_subscriptions = relationship('JourneySubscription', back_populates='user')
    
    def __repr__(self):
        return f"<User(id={self.id}, name='{self.name}', level={self.level}, exp={self.exp})>"


class Journey(Base):
    """旅程"""
    __tablename__ = 'journeys'
    
    journey_id = Column(Integer, primary_key=True)
    name = Column(String(200), nullable=False)
    description = Column(Text)
    created_at = Column(DateTime, default=datetime.now)
    
    # 關聯
    chapters = relationship('Chapter', back_populates='journey')
    lessons = relationship('Lesson', back_populates='journey')
    subscriptions = relationship('JourneySubscription', back_populates='journey')
    
    def __repr__(self):
        return f"<Journey(journey_id={self.journey_id}, name='{self.name}')>"


class Chapter(Base):
    """章節"""
    __tablename__ = 'chapters'
    
    chapter_id = Column(Integer, primary_key=True)
    journey_id = Column(Integer, ForeignKey('journeys.journey_id'), nullable=False)
    name = Column(String(200), nullable=False)
    order = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.now)
    
    # 關聯
    journey = relationship('Journey', back_populates='chapters')
    lessons = relationship('Lesson', back_populates='chapter')
    
    def __repr__(self):
        return f"<Chapter(chapter_id={self.chapter_id}, name='{self.name}')>"


class Lesson(Base):
    """課程"""
    __tablename__ = 'lessons'
    
    lesson_id = Column(Integer, primary_key=True)
    name = Column(String(200), nullable=False)
    type = Column(Integer, nullable=False)  # 0:問卷, 2:影片, 3:挑戰題, 4:Boss挑戰
    journey_id = Column(Integer, ForeignKey('journeys.journey_id'), nullable=False)
    chapter_id = Column(Integer, ForeignKey('chapters.chapter_id'), nullable=False)
    reward_exp = Column(Integer, default=0)
    description = Column(Text)
    created_at = Column(DateTime, default=datetime.now)
    
    # 關聯
    journey = relationship('Journey', back_populates='lessons')
    chapter = relationship('Chapter', back_populates='lessons')
    progresses = relationship('LessonProgress', back_populates='lesson')
    
    def __repr__(self):
        return f"<Lesson(lesson_id={self.lesson_id}, name='{self.name}', type={self.type})>"


class LessonProgress(Base):
    """課程進度"""
    __tablename__ = 'lesson_progress'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    lesson_id = Column(Integer, ForeignKey('lessons.lesson_id'), nullable=False)
    progress = Column(Float, default=0.0)  # 0-100%
    status = Column(String(50), default='NOT_STARTED')  # NOT_STARTED, IN_PROGRESS, COMPLETED, WAITING_FOR_REVIEW, DELIVERED
    form_url = Column(String(500))  # 問卷 URL
    files = Column(Text)  # 作業檔案
    created_at = Column(DateTime, default=datetime.now)
    updated_at = Column(DateTime, default=datetime.now, onupdate=datetime.now)
    
    # 關聯
    user = relationship('User', back_populates='lesson_progresses')
    lesson = relationship('Lesson', back_populates='progresses')
    
    def __repr__(self):
        return f"<LessonProgress(user_id={self.user_id}, lesson_id={self.lesson_id}, progress={self.progress}, status='{self.status}')>"


class JourneySubscription(Base):
    """旅程訂閱"""
    __tablename__ = 'journey_subscriptions'
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    journey_id = Column(Integer, ForeignKey('journeys.journey_id'), nullable=False)
    subscribed_at = Column(DateTime, default=datetime.now)
    
    # 關聯
    user = relationship('User', back_populates='journey_subscriptions')
    journey = relationship('Journey', back_populates='subscriptions')
    
    def __repr__(self):
        return f"<JourneySubscription(user_id={self.user_id}, journey_id={self.journey_id})>"

