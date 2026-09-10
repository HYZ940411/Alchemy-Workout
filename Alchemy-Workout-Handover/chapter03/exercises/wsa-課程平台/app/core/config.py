"""
應用程式配置與路徑管理

這個模組集中管理所有應用程式設定和路徑常數。

路徑管理好處：
- 單一來源的真實性（Single Source of Truth）
- 便於維護和修改路徑
- 避免重複的路徑計算邏輯
- 在不同環境中保持一致性

使用範例：
    1. 使用設定：
        from app.core.config import settings
        print(settings.DATABASE_URL)
    
    2. 使用路徑：
        from app.core.config import paths
        print(paths.PROJECT_ROOT)
    
    3. 在測試中：
        from app.core.config import paths
        test_file = paths.E2E_TESTS_DIR / "test_example.py"
"""

import os
from pathlib import Path
from pydantic_settings import BaseSettings
from pydantic import ConfigDict


# ============= 路徑管理 =============

class Paths:
    """
    專案路徑集中管理
    
    所有路徑都是 pathlib.Path 物件，支持跨平台操作。
    """
    
    # ============= 專案根目錄 =============
    # config.py 位於 app/core/config.py，往上 2 層到達專案根目錄
    # app/core/ -> app/ -> project_root/
    PROJECT_ROOT: Path = Path(__file__).resolve().parents[2]
    """專案根目錄路徑"""
    
    # ============= 主要目錄 =============
    APP_DIR: Path = PROJECT_ROOT / "app"
    """App 應用程式目錄 (app/)"""
    
    TESTS_DIR: Path = PROJECT_ROOT / "tests"
    """測試目錄 (tests/)"""
    
    # ============= App 目錄結構 =============
    API_DIR: Path = APP_DIR / "api"
    """API 路由目錄 (app/api)"""
    
    CORE_DIR: Path = APP_DIR / "core"
    """核心設定目錄 (app/core)"""
    
    MODELS_DIR: Path = APP_DIR / "models"
    """資料模型目錄 (app/models)"""
    
    SCHEMAS_DIR: Path = APP_DIR / "schemas"
    """Pydantic Schema 目錄 (app/schemas)"""
    
    WALKING_SKELETON_DIR: Path = APP_DIR / "walking_skeleton"
    """Walking Skeleton 模組目錄 (app/walking_skeleton)"""
    
    # ============= Tests 目錄結構 =============
    E2E_TESTS_DIR: Path = TESTS_DIR / "e2e"
    """E2E 測試目錄 (tests/e2e)"""
    
    WALKING_SKELETON_TESTS_DIR: Path = E2E_TESTS_DIR / "walking_skeleton"
    """Walking Skeleton 測試目錄 (tests/e2e/walking_skeleton)"""
    
    # ============= Walking Skeleton 子模塊 =============
    WS_MODELS_DIR: Path = WALKING_SKELETON_DIR / "models"
    """Walking Skeleton 模型目錄 (app/walking_skeleton/models)"""
    
    WS_SCHEMAS_DIR: Path = WALKING_SKELETON_DIR / "schemas"
    """Walking Skeleton Schema 目錄 (app/walking_skeleton/schemas)"""
    
    WS_API_DIR: Path = WALKING_SKELETON_DIR / "api"
    """Walking Skeleton API 目錄 (app/walking_skeleton/api)"""
    
    # ============= 配置和遷移文件 =============
    ALEMBIC_DIR: Path = PROJECT_ROOT / "alembic"
    """Alembic 遷移目錄 (alembic/)"""
    
    ALEMBIC_INI: Path = PROJECT_ROOT / "alembic.ini"
    """Alembic 配置文件 (alembic.ini)"""
    
    PYTEST_INI: Path = PROJECT_ROOT / "pytest.ini"
    """Pytest 配置文件 (pytest.ini)"""
    
    # ============= 需求文件 =============
    REQUIREMENTS_TXT: Path = PROJECT_ROOT / "requirements.txt"
    """生產環境依賴文件 (requirements.txt)"""
    
    REQUIREMENTS_DEV_TXT: Path = PROJECT_ROOT / "requirements-dev.txt"
    """開發環境依賴文件 (requirements-dev.txt)"""
    
    # ============= Docker 相關 =============
    DOCKERFILE: Path = PROJECT_ROOT / "Dockerfile"
    """Docker 映像建置文件 (Dockerfile)"""
    
    DOCKER_COMPOSE_YML: Path = PROJECT_ROOT / "docker-compose.yml"
    """Docker Compose 配置文件 (docker-compose.yml)"""
    
    @staticmethod
    def setup_python_path():
        """
        將專案根目錄加入 Python path，確保可以正確導入 app module
        
        通常在 conftest.py 或其他測試設定中調用此函數。
        這個函數會檢查專案根目錄是否已在 sys.path 中，如果沒有則加入。
        
        使用範例：
            from app.core.config import paths
            
            # 確保可以導入 app module
            paths.setup_python_path()
            from app.models import Base
        
        Returns:
            None
        """
        import sys
        if str(Paths.PROJECT_ROOT) not in sys.path:
            sys.path.insert(0, str(Paths.PROJECT_ROOT))


# 建立全域路徑物件
paths = Paths()


# ============= 應用程式設定 =============

class Settings(BaseSettings):
    """應用程式設定"""

    model_config = ConfigDict(case_sensitive=True)

    # 資料庫設定
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql://postgres:postgres@localhost:5432/wsa_course"
    )

    # JWT 設定
    SECRET_KEY: str = os.getenv("SECRET_KEY", "test-secret-key-change-in-production")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_HOURS: int = 24

    # 應用程式設定
    DEBUG: bool = os.getenv("DEBUG", "False") == "True"

    @property
    def database_url_with_driver(self) -> str:
        """確保使用 psycopg (psycopg3) 驅動"""
        url = self.DATABASE_URL
        if url.startswith("postgresql://"):
            return url.replace("postgresql://", "postgresql+psycopg://", 1)
        return url


# 建立全域設定物件
settings = Settings()
