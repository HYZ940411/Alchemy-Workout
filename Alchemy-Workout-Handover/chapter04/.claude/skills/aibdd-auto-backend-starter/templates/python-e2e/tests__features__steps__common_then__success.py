from behave import then


@then("操作成功")
def step_then_success(context):
    assert context.last_response is not None, "No response received"
    resp = context.last_response.json()
    assert resp.get("success") is True, f"Expected success=true, got {resp}"
