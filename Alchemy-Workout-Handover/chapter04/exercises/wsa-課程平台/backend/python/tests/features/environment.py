"""Behave 環境設定 - E2E Testing with Testcontainers + PostgreSQL。

此檔案管理 E2E 測試的整個生命週期：
- before_all: 啟動 PostgreSQL 容器、執行 Alembic migrations
- before_scenario: 初始化 context 狀態、DB Session、HTTP Client
- after_scenario: 清理資料（Truncate tables）
- after_all: 關閉容器
"""

import os
import sys
from types import SimpleNamespace

# 確保專案根目錄在 Python path 中
project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

# 全域變數（session scope）
_postgres_container = None
_engine = None
_SessionLocal = None


def before_all(context):
    """啟動 PostgreSQL 容器（整個測試 session 只啟動一次）。"""
    global _postgres_container, _engine, _SessionLocal

    from testcontainers.postgres import PostgresContainer
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    # 啟動 PostgreSQL 容器
    _postgres_container = PostgresContainer(
        image="postgres:15",
        user="postgres",
        password="postgres",
        dbname="chapter04_test"
    )
    _postgres_container.start()

    # 取得連線 URL（使用 psycopg 驅動）
    connection_url = _postgres_container.get_connection_url()
    # testcontainers 預設使用 psycopg2，我們需要改為 psycopg
    connection_url = connection_url.replace("psycopg2", "psycopg")

    # 設定環境變數供 Alembic 使用
    os.environ["DATABASE_URL"] = connection_url

    # 建立引擎
    _engine = create_engine(connection_url)

    # 執行 Alembic migrations
    from alembic.config import Config
    from alembic import command
    from app.core.config import paths

    alembic_cfg = Config(str(paths.ALEMBIC_INI))
    alembic_cfg.set_main_option("sqlalchemy.url", connection_url)
    command.upgrade(alembic_cfg, "head")

    # 建立 Session Factory
    _SessionLocal = sessionmaker(bind=_engine)

    # 設定依賴注入
    from app.core.deps import set_session_factory
    set_session_factory(_SessionLocal)


def before_scenario(context, scenario):
    """每個 Scenario 執行前初始化。"""
    # 初始化狀態
    context.last_error = None
    context.last_response = None
    context.query_result = None
    context.ids = {}
    context.memo = {}

    # 初始化 DB Session
    context.db_session = _SessionLocal()

    # 初始化 HTTP Client（FastAPI TestClient）
    from fastapi.testclient import TestClient
    from app.main import app
    context.api_client = TestClient(app)

    # 初始化 JWT Helper
    from tests.features.helpers.jwt_helper import JwtHelper
    context.jwt_helper = JwtHelper()

    # 初始化 Repositories（使用真實 SQLAlchemy）
    context.repos = SimpleNamespace()
    # 範例：
    # from app.repositories.lesson_progress_repository import LessonProgressRepository
    # context.repos.lesson_progress = LessonProgressRepository(context.db_session)

    # 初始化 Services（如需要）
    context.services = SimpleNamespace()


def after_scenario(context, scenario):
    """每個 Scenario 執行後清理（Truncate tables）。"""
    from sqlalchemy import inspect, text

    # Rollback 任何未提交的變更
    context.db_session.rollback()

    # Truncate 所有 tables（除了 alembic_version）
    inspector = inspect(_engine)
    tables = inspector.get_table_names()
    with _engine.begin() as connection:
        for table in tables:
            if table != 'alembic_version':
                connection.execute(text(f"TRUNCATE TABLE {table} CASCADE"))

    # 關閉 Session
    context.db_session.close()

    # 清理狀態
    context.last_error = None
    context.last_response = None
    context.query_result = None
    context.ids.clear()
    context.memo.clear()


def after_all(context):
    """關閉 PostgreSQL 容器。"""
    global _postgres_container, _engine

    if _engine:
        _engine.dispose()
    if _postgres_container:
        _postgres_container.stop()
