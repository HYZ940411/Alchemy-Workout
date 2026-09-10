"""
When: (UID="$userId") 用戶訂閱旅程, call table:
呼叫用戶訂閱旅程 API
"""
from behave import step, use_step_matcher
import re
from steps.helpers.datatable_parser import parse_datatable

use_step_matcher("re")

@step(r'\(UID="([^"]+)"\) 用戶訂閱旅程, call table:')
def call_subscribe_journey(context, user_id_var):
    """呼叫用戶訂閱旅程 API"""
    # 解析 user_id（支援 $variable）
    user_id = context.scenario_context.resolve_value(user_id_var)
    
    # 解析 DataTable
    rows = parse_datatable(context.table, context)
    
    # 取得第一行資料（API 參數）
    data, context_mappings = rows[0]
    
    journey_id = data.get('journeyId')
    
    # 呼叫 API
    try:
        response = context.api_client.subscribe_journey(
            user_id=user_id,
            journey_id=journey_id
        )
        
        # 儲存 response
        context.scenario_context.set_response(response)
        
    except Exception as e:
        # 發生異常時，設置 response 為 None
        context.scenario_context.set_response(None)

