"""
ScenarioContext: 管理跨 step 的變數和 API response
"""
from typing import Any, Optional


class ScenarioContext:
    """
    Scenario Context 用於在 BDD 測試的多個 step 之間共享資料
    
    主要功能：
    1. 儲存和讀取 context 變數（支援 var-system 的 $variable）
    2. 儲存最近一次的 API response
    3. 解析值（自動處理 $variable 引用）
    """
    
    def __init__(self):
        """初始化 ScenarioContext"""
        self._variables = {}  # 儲存變數的字典
        self._response = None  # 儲存最近一次的 API response
    
    def set_var(self, key: str, value: Any) -> None:
        """
        設定變數值
        
        Args:
            key: 變數名稱（不含 $ 符號）
            value: 變數值
        """
        self._variables[key] = value
    
    def get_var(self, key: str) -> Any:
        """
        取得變數值
        
        Args:
            key: 變數名稱（不含 $ 符號）
            
        Returns:
            變數值，如果不存在則回傳 None
        """
        return self._variables.get(key)
    
    def has_var(self, key: str) -> bool:
        """
        檢查變數是否存在
        
        Args:
            key: 變數名稱（不含 $ 符號）
            
        Returns:
            變數是否存在
        """
        return key in self._variables
    
    def resolve_value(self, value: Any) -> Any:
        """
        解析值，如果是 $variable 則取得變數值，否則回傳原值
        
        Args:
            value: 原始值（可能是字串、數字或 $variable）
            
        Returns:
            解析後的值
            
        Examples:
            >>> ctx.set_var('userId', 123)
            >>> ctx.resolve_value('$userId')
            123
            >>> ctx.resolve_value('hello')
            'hello'
            >>> ctx.resolve_value(456)
            456
        """
        if isinstance(value, str) and value.startswith('$'):
            var_name = value[1:]  # 移除 $ 符號
            if '.' in var_name:
                # 支援 $Alice.id 這種格式
                parts = var_name.split('.')
                result = self._variables.get(parts[0])
                for part in parts[1:]:
                    if isinstance(result, dict):
                        result = result.get(part)
                    else:
                        result = getattr(result, part, None)
                return result
            return self.get_var(var_name)
        return value
    
    def set_response(self, response) -> None:
        """
        儲存 API response
        
        Args:
            response: requests.Response 物件或自定義 response 物件
        """
        self._response = response
    
    def get_response(self):
        """
        取得最近一次的 API response
        
        Returns:
            最近一次的 API response，如果沒有則回傳 None
        """
        return self._response
    
    def clear(self) -> None:
        """清空所有變數和 response"""
        self._variables.clear()
        self._response = None
    
    def get_all_vars(self) -> dict:
        """
        取得所有變數（用於除錯）
        
        Returns:
            包含所有變數的字典
        """
        return self._variables.copy()

