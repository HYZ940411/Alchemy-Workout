"""
Given: 準備一個用戶, with table:
插入 User 測試資料到資料庫，支援變數捕獲語法
"""
from behave import step
from support.models import User
from steps.helpers.datatable_parser import parse_datatable, get_nested_value


@step('準備一個用戶, with table:')
def prepare_user(context):
    """準備用戶測試資料"""
    session = context.db.get_session()
    
    # 解析 DataTable
    rows = parse_datatable(context.table, context)
    
    for data, context_mappings in rows:
        # 建立 User 物件
        user = User(
            name=data.get('name'),
            level=data.get('level', 1),
            exp=data.get('exp', 0)
        )
        
        session.add(user)
        session.flush()  # 取得自動生成的 id
        
        # 處理變數捕獲：將執行結果存入 context
        # 例如：>Alice.id | <id 會將 user.id 存為 context 變數 Alice.id
        for context_key, execution_key in context_mappings.items():
            if execution_key == 'id':
                # 支援 Alice.id 這種巢狀變數名稱
                if '.' in context_key:
                    # 拆分為 Alice 和 id
                    parts = context_key.split('.')
                    if len(parts) == 2:
                        obj_name, field_name = parts
                        # 創建一個字典來儲存
                        if not context.scenario_context.has_var(obj_name):
                            context.scenario_context.set_var(obj_name, {})
                        obj = context.scenario_context.get_var(obj_name)
                        obj[field_name] = user.id
                else:
                    context.scenario_context.set_var(context_key, user.id)
    
    session.commit()

