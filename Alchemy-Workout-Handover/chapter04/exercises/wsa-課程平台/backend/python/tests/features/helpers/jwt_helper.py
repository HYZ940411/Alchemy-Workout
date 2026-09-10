"""JWT Token 生成器 - 測試專用。"""

from datetime import datetime, timedelta
from typing import Optional

import jwt

from app.core.config import get_settings


class JwtHelper:
    """JWT Token 生成器（測試專用）。

    用於在 E2E 測試中生成有效的 JWT Token，
    模擬已認證的用戶進行 API 請求。

    Usage:
        ```python
        jwt_helper = JwtHelper()
        token = jwt_helper.generate_token(user_id="user-123")

        response = api_client.post(
            "/api/v1/some-endpoint",
            headers={"Authorization": f"Bearer {token}"},
            json={...}
        )
        ```
    """

    def __init__(self, secret_key: Optional[str] = None):
        """初始化 JWT Helper。

        Args:
            secret_key: JWT 密鑰。如果未提供，使用設定中的密鑰。
        """
        settings = get_settings()
        self.secret_key = secret_key or settings.JWT_SECRET_KEY
        self.algorithm = settings.JWT_ALGORITHM
        self.expire_hours = settings.JWT_EXPIRE_HOURS

    def generate_token(
        self,
        user_id,
        extra_claims: Optional[dict] = None,
        expire_hours: Optional[int] = None
    ) -> str:
        """生成 JWT Token。

        Args:
            user_id: 用戶 ID（會放在 'sub' claim 中，自動轉換為字串）
            extra_claims: 額外的 claims（可選）
            expire_hours: 過期時間（小時）。如果未提供，使用預設值。

        Returns:
            JWT Token 字串
        """
        expire = datetime.utcnow() + timedelta(
            hours=expire_hours or self.expire_hours
        )

        payload = {
            "sub": str(user_id),  # 確保 sub 是字串（符合 JWT 標準）
            "exp": expire,
            "iat": datetime.utcnow(),
        }

        if extra_claims:
            payload.update(extra_claims)

        return jwt.encode(payload, self.secret_key, algorithm=self.algorithm)

    def decode_token(self, token: str) -> dict:
        """解碼 JWT Token（用於測試驗證）。

        Args:
            token: JWT Token 字串

        Returns:
            解碼後的 payload

        Raises:
            jwt.ExpiredSignatureError: Token 已過期
            jwt.InvalidTokenError: Token 無效
        """
        return jwt.decode(token, self.secret_key, algorithms=[self.algorithm])
