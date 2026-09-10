"""路徑管理與設定模組 - Chapter04 E2E Testing."""

import os
from pathlib import Path
from functools import lru_cache


class Paths:
    """專案路徑管理。"""

    def __init__(self):
        # 專案根目錄（chapter04/）
        self.ROOT = Path(__file__).parent.parent.parent.resolve()

        # 主要目錄
        self.APP = self.ROOT / "app"
        self.TESTS = self.ROOT / "tests"
        self.SPECS = self.ROOT / "specs"
        self.ALEMBIC = self.ROOT / "alembic"

        # 子目錄
        self.MODELS = self.APP / "models"
        self.REPOSITORIES = self.APP / "repositories"
        self.SERVICES = self.APP / "services"
        self.API = self.APP / "api"
        self.CORE = self.APP / "core"

        # 測試目錄
        self.FEATURES = self.TESTS / "features"
        self.E2E_FEATURES = self.TESTS / "features"

        # 配置檔案
        self.ALEMBIC_INI = self.ROOT / "alembic.ini"
        self.DBML = self.SPECS / "erm.dbml"


class Settings:
    """應用程式設定。"""

    def __init__(self):
        # 資料庫設定
        self.DATABASE_URL: str = os.environ.get(
            "DATABASE_URL",
            "postgresql+psycopg://postgres:postgres@localhost:5432/chapter04_dev"
        )

        # JWT 設定
        self.JWT_SECRET_KEY: str = os.environ.get(
            "JWT_SECRET_KEY",
            "chapter04-test-secret-key-do-not-use-in-production"
        )
        self.JWT_ALGORITHM: str = "HS256"
        self.JWT_EXPIRE_HOURS: int = 1

        # API 設定
        self.API_V1_PREFIX: str = "/api/v1"
        self.PROJECT_NAME: str = "Chapter04 課程平台"
        self.DEBUG: bool = os.environ.get("DEBUG", "true").lower() == "true"


# 單例實例
paths = Paths()


@lru_cache()
def get_settings() -> Settings:
    """取得設定單例。"""
    return Settings()
