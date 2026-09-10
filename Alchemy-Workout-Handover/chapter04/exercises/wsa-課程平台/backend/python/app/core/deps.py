"""依賴注入模組 - Chapter04 E2E Testing."""

from typing import Generator
from sqlalchemy.orm import Session
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import jwt

from app.core.config import get_settings

# 全域變數，由 environment.py 或應用程式啟動時設定
_SessionLocal = None

# HTTP Bearer Token scheme
security = HTTPBearer()


def set_session_factory(session_factory):
    """設定 Session Factory（由測試環境或應用程式初始化時呼叫）。"""
    global _SessionLocal
    _SessionLocal = session_factory


def get_db() -> Generator[Session, None, None]:
    """
    取得資料庫 Session。

    用於 FastAPI 依賴注入：
    ```python
    @app.get("/items")
    def read_items(db: Session = Depends(get_db)):
        ...
    ```
    """
    if _SessionLocal is None:
        raise RuntimeError(
            "Database session factory not initialized. "
            "Call set_session_factory() first."
        )

    db = _SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> int:
    """
    從 JWT Token 中提取當前用戶 ID。
    
    用於 FastAPI 依賴注入：
    ```python
    @app.post("/items")
    def create_item(user_id: int = Depends(get_current_user_id)):
        ...
    ```
    
    Raises:
        HTTPException: Token 無效或已過期時拋出 401
    """
    settings = get_settings()
    token = credentials.credentials
    
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )
        user_id_str = payload.get("sub")
        if user_id_str is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="無效的認證憑證"
            )
        # 將字串轉換為 int
        return int(user_id_str)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token 已過期"
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="無效的 Token"
        )
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="無效的用戶 ID"
        )
