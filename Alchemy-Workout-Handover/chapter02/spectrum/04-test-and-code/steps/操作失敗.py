"""
Common: 操作失敗
"""
from behave import step
from steps.helpers.response_validator import verify_response_failed


@step('操作失敗')
def verify_operation_failed(context):
    """驗證操作失敗（HTTP 4xx）"""
    response = context.scenario_context.get_response()
    verify_response_failed(response)



