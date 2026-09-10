import pytest
import requests
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from testcontainers.postgres import PostgresContainer
from typing import Generator, Dict
import time
import sys
from pathlib import Path

# 確保 Python 路徑正確，以便 conftest.py 能在導入階段找到 app modules
# 雖然 pytest.ini 有 pythonpath = .，但為了確保跨越多層級目錄結構時的可靠性，
# 我們手動設定 sys.path 指向項目根目錄
_project_root = Path(__file__).resolve().parents[2]  # tests/e2e/ -> tests/ -> project_root/
if str(_project_root) not in sys.path:
    sys.path.insert(0, str(_project_root))

# 現在可以安全地使用統一的 paths 管理
from app.core.config import paths

# 導入 Base 和所有 models (app.models.__init__.py 已經導入了所有 models)
from app.models import Base
# 導入 walking skeleton models 以便 Base.metadata 可以檢測到
from app.walking_skeleton.models.message import Message

# 導入測試 helpers
from tests.e2e.helpers import JwtHelper


# Monkey patch PostgresContainer to use psycopg instead of psycopg2
class CustomPostgresContainer(PostgresContainer):
    """自定義 PostgresContainer 以使用 psycopg3 驅動"""
    
    def get_connection_url(self, host=None):
        """覆蓋以使用 psycopg 驅動"""
        # 取得原始 URL
        url = super().get_connection_url(host=host)
        # 轉換為使用 psycopg 驅動
        if url.startswith("postgresql://"):
            url = url.replace("postgresql://", "postgresql+psycopg://", 1)
        elif url.startswith("postgresql+psycopg2://"):
            url = url.replace("postgresql+psycopg2://", "postgresql+psycopg://", 1)
        return url
    
    def _connect(self):
        """覆蓋內部連接方法以使用正確的驅動"""
        import sqlalchemy
        from sqlalchemy.exc import OperationalError
        
        # 等待容器準備好
        max_retries = 30
        for i in range(max_retries):
            try:
                engine = sqlalchemy.create_engine(
                    self.get_connection_url(), 
                    connect_args={"connect_timeout": 5},
                    pool_pre_ping=True
                )
                with engine.connect():
                    pass  # 連接成功
                engine.dispose()
                return  # 成功連接，退出
            except OperationalError:
                if i == max_retries - 1:
                    raise
                time.sleep(0.5)


# ============= Session Scope Fixtures =============

@pytest.fixture(scope="session")
def postgres_container() -> Generator[CustomPostgresContainer, None, None]:
    """啟動 PostgreSQL 容器（整個測試 session 只啟動一次）"""
    with CustomPostgresContainer("postgres:15") as postgres:
        yield postgres


@pytest.fixture(scope="session")
def db_engine(postgres_container: PostgresContainer):
    """
    創建資料庫引擎並使用 Alembic 執行 migrations
    確保測試環境與生產環境使用相同的 schema 管理方式
    """
    connection_url = postgres_container.get_connection_url()
    # 確保使用 psycopg (psycopg3) 驅動
    if connection_url.startswith("postgresql://"):
        connection_url = connection_url.replace("postgresql://", "postgresql+psycopg://", 1)
    elif connection_url.startswith("postgresql+psycopg2://"):
        connection_url = connection_url.replace("postgresql+psycopg2://", "postgresql+psycopg://", 1)
    
    engine = create_engine(connection_url, pool_pre_ping=True)
    
    # 使用 Alembic 執行 migrations（與生產環境一致）
    from alembic.config import Config
    from alembic import command

    # 使用統一的路徑管理
    alembic_cfg = Config(str(paths.ALEMBIC_INI))
    alembic_cfg.set_main_option("sqlalchemy.url", connection_url)
    alembic_cfg.set_main_option("script_location", str(paths.ALEMBIC_DIR))
    
    print(f"\n🔧 執行 Alembic migrations: {connection_url}")
    command.upgrade(alembic_cfg, "head")
    print(f"✅ Alembic migrations 完成\n")
    
    # 額外建立測試用的 E2E models（這些不在 Alembic migrations 中）
    from app.models import Base
    Base.metadata.create_all(engine)
    
    yield engine
    
    # 清理
    engine.dispose()


@pytest.fixture(scope="session")
def app(postgres_container: CustomPostgresContainer):
    """
    提供 FastAPI app 實例，配置測試資料庫
    使用 TestClient 在測試進程中直接運行 ASGI app，無需 Docker container
    """
    from app.main import app
    from app.core.deps import get_db
    
    # 取得測試資料庫連接 URL
    connection_url = postgres_container.get_connection_url()
    
    print(f"\n📊 使用 FastAPI TestClient 模式")
    print(f"   - 測試資料庫: {connection_url}")
    
    # 建立測試資料庫引擎和 Session
    test_engine = create_engine(connection_url, pool_pre_ping=True)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)
    
    # Override get_db dependency
    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()
    
    app.dependency_overrides[get_db] = override_get_db
    
    print(f"✅ FastAPI app 已配置測試資料庫\n")
    
    yield app
    
    # 清理
    try:
        app.dependency_overrides.clear()
    except:
        pass
    
    try:
        test_engine.dispose()
    except:
        pass


@pytest.fixture(scope="session")
def api_base_url():
    """
    TestClient 不需要 base URL，返回空字串
    保留此 fixture 以保持測試代碼相容性
    """
    return ""


# ============= Function Scope Fixtures =============

@pytest.fixture(scope="module")
def db_session(db_engine) -> Generator[Session, None, None]:
    """
    提供資料庫 session (module scope)
    所有測試共享同一個 session，但 truncate_tables 會在每個測試後清空資料
    """
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=db_engine)
    session = SessionLocal()

    yield session

    # 確保清理 session
    try:
        if session.is_active:
            session.rollback()  # 回滾任何未完成的 transaction
    except Exception as e:
        print(f"Warning: Error during session cleanup: {e}")
    finally:
        try:
            session.close()
        except:
            pass


@pytest.fixture(autouse=True)
def truncate_tables(db_session, db_engine):
    """每個測試後清空所有 tables，確保測試隔離"""
    yield

    # 測試執行後清空
    from sqlalchemy import inspect

    # 首先確保 session 沒有待處理的錯誤
    try:
        if db_session.is_active:
            # 檢查是否有待處理的回滾
            if not db_session.in_transaction():
                pass
            else:
                db_session.rollback()
    except Exception:
        pass

    try:
        # 使用新的連接清空資料（避免使用可能有問題的 session）
        with db_engine.begin() as connection:
            # 取得所有 table 名稱
            inspector = inspect(db_engine)
            tables = inspector.get_table_names()

            # 清空每個 table
            for table in tables:
                try:
                    connection.execute(text(f"TRUNCATE TABLE {table} CASCADE"))
                except Exception as e:
                    # 如果某個 table 清空失敗，跳過並繼續清空下一個
                    print(f"Warning: Failed to truncate table {table}: {e}")
    except Exception as e:
        # 如果無法連接到資料庫（容器可能已關閉），忽略錯誤
        print(f"Warning: Could not connect to database for truncation: {e}")


@pytest.fixture(scope="session")
def api_client(app):
    """
    提供 FastAPI TestClient (session scope)
    TestClient 在測試進程中直接運行 ASGI app，無需真實的 HTTP server
    API 與 requests.Session 高度相似，測試代碼無需修改
    """
    from fastapi.testclient import TestClient
    with TestClient(app) as client:
        yield client


@pytest.fixture(scope="module")
def context() -> Dict:
    """
    測試上下文，用於在步驟間傳遞資料 (module scope)
    在 feature_background 中設定基礎資料，在各測試方法中使用
    """
    return {}


@pytest.fixture(scope="module")
def jwt_helper() -> JwtHelper:
    """提供 JWT Token 生成器 (module scope)"""
    return JwtHelper()


# ============= Helper Functions =============

def wait_for_api(base_url: str, timeout: int = 30) -> bool:
    """等待 API 服務啟動"""
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        try:
            response = requests.get(f"{base_url}/health", timeout=1)
            if response.status_code == 200:
                return True
        except:
            time.sleep(0.5)
    
    return False

