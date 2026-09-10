"""自定義例外類別"""


class BusinessError(Exception):
    """業務規則例外 - 業務規則違反時拋出"""
    def __init__(self, message: str, status_code: int = 400):
        self.message = message
        self.status_code = status_code
        super().__init__(message)


class InvalidStateError(Exception):
    """無效狀態例外 - 業務規則違反時拋出"""
    pass


class InvalidArgumentError(Exception):
    """無效參數例外 - 參數格式或值不正確時拋出"""
    pass


class NotFoundError(Exception):
    """找不到資源例外 - 查詢的資源不存在時拋出"""
    pass


class UnauthorizedError(Exception):
    """未授權例外 - 沒有權限執行操作時拋出"""
    pass


class DuplicateError(Exception):
    """重複操作例外 - 重複建立相同資源時拋出"""
    pass

