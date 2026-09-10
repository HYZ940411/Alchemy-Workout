"""
JWT Token 生成工具

為測試環境生成假的 JWT token
"""
import base64


def generate_token(user_id: int) -> str:
    """
    從 user_id 生成固定的假 JWT token
    
    在測試環境中，我們不需要真正的 JWT 加密，
    只需要一個可以重複使用、可逆的編碼即可。
    
    Args:
        user_id: 用戶 ID
        
    Returns:
        假的 JWT token 字串
        
    Examples:
        >>> generate_token(123)
        'test_token_user_123'
    """
    # 簡單的編碼方式：將 user_id 編碼成 base64
    user_id_str = str(user_id)
    encoded = base64.b64encode(user_id_str.encode()).decode()
    return f"test_token_{encoded}"


def decode_token(token: str) -> int:
    """
    從 token 解碼出 user_id
    
    Args:
        token: JWT token 字串
        
    Returns:
        用戶 ID
        
    Examples:
        >>> token = generate_token(123)
        >>> decode_token(token)
        123
    """
    if not token.startswith('test_token_'):
        raise ValueError(f"無效的 token 格式: {token}")
    
    encoded = token[len('test_token_'):]
    decoded = base64.b64decode(encoded).decode()
    return int(decoded)

