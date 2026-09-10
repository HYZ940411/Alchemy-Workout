"""
資料庫初始化和連線管理

提供資料庫連線、初始化、清理等功能
"""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from support.models import Base


class Database:
    """資料庫管理類別"""
    
    def __init__(self, connection_string='sqlite:///:memory:'):
        """
        初始化資料庫連線
        
        Args:
            connection_string: 資料庫連線字串，預設為 in-memory SQLite
        """
        self.engine = create_engine(connection_string, echo=False)
        self.SessionLocal = sessionmaker(bind=self.engine)
        self.session: Session = None
    
    def create_all_tables(self):
        """建立所有資料表"""
        Base.metadata.create_all(self.engine)
    
    def drop_all_tables(self):
        """刪除所有資料表"""
        Base.metadata.drop_all(self.engine)
    
    def get_session(self) -> Session:
        """取得資料庫 session"""
        if self.session is None:
            self.session = self.SessionLocal()
        return self.session
    
    def close_session(self):
        """關閉資料庫 session"""
        if self.session:
            self.session.close()
            self.session = None
    
    def clear_all_data(self):
        """清空所有資料表的資料"""
        session = self.get_session()
        
        # 按照依賴順序清空（先清除依賴表，再清除主表）
        for table in reversed(Base.metadata.sorted_tables):
            session.execute(table.delete())
        
        session.commit()
    
    def reset(self):
        """重置資料庫（清空所有資料）"""
        self.clear_all_data()

