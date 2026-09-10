from behave import then


@then('錯誤訊息應為 "{message}"')
def step_impl(context, message):
    """驗證錯誤訊息。

    E2E 模式：從 HTTP response body 中取得錯誤訊息
    Unit Test 模式：從 context.last_error 取得錯誤訊息
    """
    # E2E 模式：檢查 HTTP response
    if hasattr(context, 'last_response') and context.last_response is not None:
        response = context.last_response
        try:
            data = response.json()
            # 嘗試不同的錯誤訊息欄位名稱
            actual_message = (
                data.get("message") or
                data.get("detail") or
                data.get("error") or
                str(data)
            )
        except Exception:
            actual_message = response.text

        assert message in str(actual_message), \
            f"預期錯誤訊息包含 '{message}'，實際為 '{actual_message}'"
    # Unit Test 模式：檢查 last_error
    else:
        error = context.last_error
        assert error is not None, "預期操作失敗，但沒有發生錯誤"
        assert message in str(error), \
            f"預期錯誤訊息包含 '{message}'，實際為 '{str(error)}'"


