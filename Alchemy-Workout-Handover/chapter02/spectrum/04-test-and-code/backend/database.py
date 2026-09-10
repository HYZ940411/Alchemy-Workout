"""
後端資料庫配置

使用 SQLAlchemy 連接 SQLite
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.ext.declarative import declarative_base
import os

# 使用絕對路徑確保後端和測試共用同一個資料庫檔案
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(BASE_DIR, 'test_shared.db')
SQLALCHEMY_DATABASE_URL = os.getenv('DB_CONNECTION', f'sqlite:///{DB_PATH}')

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False} if 'sqlite' in SQLALCHEMY_DATABASE_URL else {}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db() -> Session:
    """取得資料庫 session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

