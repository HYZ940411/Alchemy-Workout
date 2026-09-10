"""JWT Token 生成器（測試專用）"""

from datetime import datetime, timedelta, UTC
import jwt


class JwtHelper:
    """JWT Token 生成器（測試專用）"""
    
    def __init__(self, secret_key: str = None):
        """
        初始化 JwtHelper
        
        Args:
            secret_key: JWT 簽名用的密鑰，如果為 None 則使用應用程式的預設密鑰
        """
        # 使用與應用程式相同的 secret key
        if secret_key is None:
            from app.core.config import settings
            secret_key = settings.SECRET_KEY
        self.secret_key = secret_key
    
    def generate_token(self, user_id: int, **kwargs) -> str:
        """
        生成 JWT Token
        
        Args:
            user_id: 用戶 ID
            **kwargs: 額外的 payload 欄位（會覆蓋預設值）
        
        Returns:
            JWT token 字串
        
        Examples:
            # 基本用法
            token = jwt_helper.generate_token(123)
            
            # 加入額外的 payload
            token = jwt_helper.generate_token(123, role="admin", permissions=["read", "write"])
            
            # 自訂過期時間
            token = jwt_helper.generate_token(123, exp=datetime.now(UTC) + timedelta(minutes=30))
        """
        payload = {
            "sub": str(user_id),
            "exp": datetime.now(UTC) + timedelta(hours=1)
        }
        # 使用 kwargs 更新 payload（允許覆蓋預設值）
        payload.update(kwargs)
        return jwt.encode(payload, self.secret_key, algorithm="HS256")










