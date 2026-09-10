from behave import then


@then('操作失敗，原因為 "{reason}"')
def step_impl(context, reason):
    """驗證前一個操作執行失敗，且錯誤訊息包含指定原因"""
    assert context.last_error is not None, \
        "預期操作失敗，但操作成功了"

    assert reason in str(context.last_error), \
        f"預期錯誤原因包含 '{reason}'，實際錯誤: {context.last_error}"


