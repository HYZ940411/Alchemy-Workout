"""
Response 驗證工具

提供 API Response 驗證的輔助功能
"""
from steps.helpers.datatable_parser import parse_datatable, get_nested_value
from steps.helpers.constraint_validator import validate_constraints


def verify_response_success(response):
    """
    驗證 Response 為成功狀態（2xx）
    
    Args:
        response: requests.Response 物件
        
    Raises:
        AssertionError: 驗證失敗
    """
    assert response is not None, "沒有 API 回應"
    assert 200 <= response.status_code < 300, \
        f"期望成功回應（2xx），但實際為 {response.status_code}"


def verify_response_failed(response):
    """
    驗證 Response 為失敗狀態（4xx）
    
    Args:
        response: requests.Response 物件或 None
        
    Raises:
        AssertionError: 驗證失敗
    """
    if response is None:
        # 可能是異常，這也算失敗
        return
    
    assert response.status_code >= 400, \
        f"操作應該失敗（status code >= 400），但實際為 {response.status_code}"


def verify_response_body(response, table, context):
    """
    驗證 Response Body 符合 DataTable 定義
    
    Args:
        response: requests.Response 物件
        table: Behave table 物件
        context: Behave context 物件
        
    Raises:
        AssertionError: 驗證失敗
    """
    # 解析 JSON
    try:
        response_data = response.json()
    except:
        raise AssertionError("無法解析 JSON 回應")
    
    # 解析 DataTable
    rows = parse_datatable(table, context)
    
    # 驗證每一行
    for data, _ in rows:
        for field, expected_value in data.items():
            # 支援巢狀欄位（如 reward.exp）
            actual_value = get_nested_value(response_data, field)
            
            # 驗證約束或精確值
            validate_constraints(actual_value, expected_value, context)



