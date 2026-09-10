from behave import then


@then('操作失敗')
def step_impl(context):
    """驗證前一個操作執行失敗。

    E2E 模式：檢查 HTTP status code 為 4XX
    Unit Test 模式：檢查 context.last_error 不為 None
    """
    # E2E 模式：檢查 HTTP response
    if hasattr(context, 'last_response') and context.last_response is not None:
        response = context.last_response
        assert 400 <= response.status_code < 500, \
            f"預期失敗（4XX），實際 {response.status_code}: {response.text}"
    # Unit Test 模式：檢查 last_error
    else:
        assert context.last_error is not None, \
            "預期操作失敗，但操作成功了"


