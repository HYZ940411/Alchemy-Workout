"""
When: (UID="$userId") 提交挑戰題作業, call table:
呼叫提交挑戰題作業 API
"""
from behave import step, use_step_matcher
import re
from steps.helpers.datatable_parser import parse_datatable

use_step_matcher("re")

@step(r'\(UID="([^"]+)"\) 提交挑戰題作業, call table:')
def call_submit_challenge(context, user_id_var):
    """呼叫提交挑戰題作業 API"""
    # 解析 user_id（支援 $variable）
    user_id = context.scenario_context.resolve_value(user_id_var)
    
    # 解析 DataTable
    rows = parse_datatable(context.table, context)
    
    # 取得第一行資料（API 參數）
    data, context_mappings = rows[0]
    
    lesson_id = data.get('lessonId')
    files = data.get('files[0]', data.get('files', ''))
    
    # 處理 @file: 語法（移除前綴）
    if isinstance(files, str) and files.startswith('@file:'):
        files = files[6:]  # 移除 '@file:' 前綴
    
    # 呼叫 API
    try:
        response = context.api_client.submit_challenge(
            user_id=user_id,
            lesson_id=lesson_id,
            files=files
        )
        
        # 儲存 response
        context.scenario_context.set_response(response)
        
    except Exception as e:
        # 發生異常時，設置 response 為 None
        context.scenario_context.set_response(None)

