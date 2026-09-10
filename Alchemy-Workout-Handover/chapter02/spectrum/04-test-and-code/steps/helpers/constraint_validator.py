"""
約束斷言驗證工具

提供簡化的約束斷言驗證介面
"""


def validate_constraints(actual_value, expected_value, context):
    """
    驗證值是否符合約束條件
    
    Args:
        actual_value: 實際值
        expected_value: 期望值（可能是字面值或約束表達式）
        context: Behave context 物件
        
    Returns:
        是否通過驗證
        
    Raises:
        AssertionError: 驗證失敗
    """
    # 檢查是否為約束斷言
    if isinstance(expected_value, str) and expected_value.startswith('&'):
        # 使用約束斷言系統
        result = context.assert_helper.evaluate_multiple(
            actual_value, 
            expected_value, 
            context.scenario_context
        )
        if not result:
            raise AssertionError(
                f"約束斷言失敗: 實際值 {actual_value}, 約束 {expected_value}"
            )
    else:
        # 精確比對（支持類型轉換）
        # 如果期望值是字串但實際值是數字或布林，嘗試轉換比較
        if not values_match(actual_value, expected_value):
            raise AssertionError(
                f"值不符: 期望 {expected_value}, 實際 {actual_value}"
            )


def values_match(actual, expected):
    """
    比較兩個值是否匹配，支持類型轉換
    
    Args:
        actual: 實際值
        expected: 期望值
        
    Returns:
        bool: 是否匹配
    """
    # 如果類型相同，直接比較
    if type(actual) == type(expected):
        return actual == expected
    
    # 如果期望值是字串，嘗試轉換實際值
    if isinstance(expected, str):
        # ⚠️ 注意：必須先檢查布林，因為 bool 是 int 的子類
        # 嘗試轉換為布林
        if isinstance(actual, bool):
            return str(actual).lower() == expected.lower()
        
        # 嘗試轉換為數字
        if isinstance(actual, (int, float)):
            try:
                # 先嘗試轉為 int
                if isinstance(actual, int) or actual == int(actual):
                    return str(int(actual)) == expected
                else:
                    return str(actual) == expected
            except:
                return str(actual) == expected
        
        # 其他類型直接字串化比較
        return str(actual) == expected
    
    # 如果實際值是字串，嘗試轉換期望值
    if isinstance(actual, str):
        if isinstance(expected, bool):
            return actual.lower() == str(expected).lower()
            
        if isinstance(expected, (int, float)):
            try:
                actual_num = int(actual) if '.' not in actual else float(actual)
                return actual_num == expected
            except:
                return False
    
    # 最後嘗試直接比較
    return actual == expected



