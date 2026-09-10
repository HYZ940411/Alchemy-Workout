"""
Common: 回應 {status}, with table:
"""
from behave import step, register_type
import re
from steps.helpers.response_validator import verify_response_success, verify_response_body


def parse_status(text):
    """解析狀態碼"""
    return int(text)


register_type(StatusCode=parse_status)


@step('回應 {status:d}, with table:')
def verify_response_with_status(context, status):
    """驗證 API 回應狀態碼和內容"""
    response = context.scenario_context.get_response()
    
    # 檢查 response 存在
    assert response is not None, "沒有 API 回應"
    
    # 驗證狀態碼
    assert response.status_code == status, \
        f"期望狀態碼 {status}，但實際為 {response.status_code}"
    
    # 驗證 response body
    verify_response_body(response, context.table, context)


@step('回應, with table:')
def verify_response(context):
    """驗證 API 回應內容（不指定狀態碼，預設 2xx）"""
    response = context.scenario_context.get_response()
    
    # 檢查 response 存在且為 2xx
    verify_response_success(response)
    
    # 驗證 response body
    verify_response_body(response, context.table, context)



