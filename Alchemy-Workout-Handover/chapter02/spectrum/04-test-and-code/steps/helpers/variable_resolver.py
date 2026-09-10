"""
變數解析工具

處理 ScenarioContext 中的變數設定和讀取
"""
from typing import Any


def save_execution_variables(execution_result: dict, context_mappings: dict, context) -> None:
    """
    從執行結果中提取變數並存入 context
    
    Args:
        execution_result: 執行結果字典
        context_mappings: {contextKey: executionKey} 映射
        context: Behave context 物件
    """
    for context_key, execution_key in context_mappings.items():
        if execution_key in execution_result:
            value = execution_result[execution_key]
            
            # 支援巢狀變數名稱（如 Alice.id）
            if '.' in context_key:
                parts = context_key.split('.')
                obj_name = parts[0]
                field_name = parts[1]
                
                # 取得或建立物件
                obj = context.scenario_context.get_var(obj_name)
                if obj is None:
                    obj = {}
                    context.scenario_context.set_var(obj_name, obj)
                
                # 設定欄位值
                if isinstance(obj, dict):
                    obj[field_name] = value
            else:
                context.scenario_context.set_var(context_key, value)


def resolve_uid(uid: str, context) -> int:
    """
    解析 UID 參數（可能是變數引用）
    
    Args:
        uid: UID 字串（如 "$Alice.id" 或 "123"）
        context: Behave context 物件
        
    Returns:
        用戶 ID（整數）
    """
    if uid.startswith('$'):
        return context.scenario_context.resolve_value(uid)
    return int(uid)



