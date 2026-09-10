from sqlalchemy.orm import declarative_base

Base = declarative_base()

# 導入所有 models 以便 Base.metadata 可以檢測到
from app.walking_skeleton.models.message import Message
