"""
DataTable 解析工具

處理 BDD Feature 中的 DataTable，支援 Var-system 語法：
- >contextKey: 定義要存入 context 的變數名稱
- <executionKey: 從執行結果取值
- $variable: 引用 context 中的變數
"""
from typing import Dict, Any, List, Tuple


def parse_datatable(table, context) -> List[Tuple[Dict[str, Any], Dict[str, str]]]:
    """
    解析 DataTable，處理 var-system operators
    
    Args:
        table: Behave table 物件
        context: Behave context 物件
        
    Returns:
        List of (parsed_data, context_mappings) tuples
        - parsed_data: 解析後的資料字典（不含 >key）
        - context_mappings: context variable 映射 {contextKey: executionKey}
    """
    results = []
    
    for row in table:
        parsed_data = {}
        context_mappings = {}
        
        for heading in table.headings:
            value = row[heading]
            
            # 檢查 header 是否有 >contextKey
            if heading.startswith('>'):
                context_key = heading[1:]
                # 檢查 value 是否有 <executionKey
                if value.startswith('<'):
                    execution_key = value[1:]
                    context_mappings[context_key] = execution_key
                continue  # 不加入 parsed_data
            
            # 解析值（支援 $variable）
            resolved_value = resolve_variable(value, context)
            parsed_data[heading] = resolved_value
        
        results.append((parsed_data, context_mappings))
    
    return results


def resolve_variable(value: Any, context) -> Any:
    """
    解析值中的變數引用
    
    Args:
        value: 原始值
        context: Behave context 物件
        
    Returns:
        解析後的值
    """
    if isinstance(value, str) and value.startswith('$'):
        return context.scenario_context.resolve_value(value)
    return value


def get_nested_value(data: Dict[str, Any], field_path: str) -> Any:
    """
    取得巢狀欄位的值（如 reward.exp）
    
    Args:
        data: 資料字典或物件
        field_path: 欄位路徑（用 . 分隔）
        
    Returns:
        欄位值
    """
    parts = field_path.split('.')
    value = data
    
    for part in parts:
        if isinstance(value, dict):
            value = value.get(part)
        else:
            value = getattr(value, part, None)
        
        if value is None:
            break
    
    return value



