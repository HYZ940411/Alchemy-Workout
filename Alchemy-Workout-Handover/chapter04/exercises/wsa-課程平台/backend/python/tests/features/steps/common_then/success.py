from behave import then


@then('操作成功')
def step_impl(context):
    """驗證前一個操作執行成功。

    E2E 模式：檢查 HTTP status code 為 2XX
    Unit Test 模式：檢查 context.last_error 為 None
    """
    # E2E 模式：檢查 HTTP response
    if hasattr(context, 'last_response') and context.last_response is not None:
        response = context.last_response
        assert response.status_code in [200, 201, 204], \
            f"預期成功（2XX），實際 {response.status_code}: {response.text}"
    # Unit Test 模式：檢查 last_error
    else:
        assert context.last_error is None, \
            f"預期操作成功，但發生錯誤: {context.last_error}"


