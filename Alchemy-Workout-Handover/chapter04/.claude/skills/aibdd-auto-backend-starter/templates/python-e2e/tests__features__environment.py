import os
from types import SimpleNamespace

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from testcontainers.postgres import PostgresContainer

from ${PY_APP_MODULE}.core.deps import set_session_factory
from ${PY_APP_MODULE}.main import create_app
from ${PY_APP_MODULE}.models import Base

postgres_container = None
engine = None
SessionLocal = None


def before_all(context):
    global postgres_container, engine, SessionLocal

    postgres_container = PostgresContainer("postgres:15")
    postgres_container.start()

    db_url = postgres_container.get_connection_url().replace(
        "psycopg2", "psycopg"
    )
    os.environ["DATABASE_URL"] = db_url

    engine = create_engine(db_url)

    # Run Alembic migrations
    alembic_cfg = Config("alembic.ini")
    alembic_cfg.set_main_option("sqlalchemy.url", db_url)
    command.upgrade(alembic_cfg, "head")

    SessionLocal = sessionmaker(bind=engine)
    set_session_factory(SessionLocal)


def before_scenario(context, scenario):
    context.last_error = None
    context.last_response = None
    context.query_result = None
    context.ids = {}
    context.memo = {}

    context.db_session = SessionLocal()

    app = create_app()
    from starlette.testclient import TestClient

    context.api_client = TestClient(app)
    context.repos = SimpleNamespace()
    context.services = SimpleNamespace()


def after_scenario(context, scenario):
    if hasattr(context, "db_session") and context.db_session:
        context.db_session.rollback()
        # Truncate all tables except alembic_version
        for table in reversed(Base.metadata.sorted_tables):
            context.db_session.execute(
                text(f"TRUNCATE TABLE {table.name} CASCADE")
            )
        context.db_session.commit()
        context.db_session.close()

    context.last_error = None
    context.last_response = None
    context.query_result = None
    context.ids = {}
    context.memo = {}


def after_all(context):
    global engine, postgres_container
    if engine:
        engine.dispose()
    if postgres_container:
        postgres_container.stop()
