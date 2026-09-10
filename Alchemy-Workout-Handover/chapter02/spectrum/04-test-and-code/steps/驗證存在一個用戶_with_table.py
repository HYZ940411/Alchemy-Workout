"""
Then: 驗證存在一個用戶, with table:
查詢並驗證 User 資料庫狀態
"""
from behave import step
from support.models import User
from steps.helpers.datatable_parser import parse_datatable
from steps.helpers.constraint_validator import validate_constraints


@step('驗證存在一個用戶, with table:')
def verify_user_exists(context):
    """驗證用戶存在且符合條件"""
    session = context.db.get_session()
    
    # 解析 DataTable
    rows = parse_datatable(context.table, context)
    
    # 第一行是查詢條件
    if len(rows) == 0:
        raise AssertionError("驗證表格不能為空")
    
    query_data, _ = rows[0]
    
    # 建立查詢條件
    query = session.query(User)
    
    if 'id' in query_data:
        query = query.filter(User.id == query_data['id'])
    
    if 'name' in query_data:
        query = query.filter(User.name == query_data['name'])
    
    # 執行查詢
    user = query.first()
    
    # 確認記錄存在
    assert user is not None, \
        f"找不到用戶: id={query_data.get('id')}, name={query_data.get('name')}"
    
    # 驗證欄位值
    for field, expected_value in query_data.items():
        if field in ['id', 'name'] and field in ['id']:
            continue  # id 已用於查詢條件
        
        actual_value = getattr(user, field, None)
        
        # 驗證值
        validate_constraints(actual_value, expected_value, context)
    
    # 如果有第二行，則為約束斷言行
    if len(rows) > 1:
        for i in range(1, len(rows)):
            constraint_data, _ = rows[i]
            
            for field, constraint in constraint_data.items():
                actual_value = getattr(user, field, None)
                
                # 驗證約束
                validate_constraints(actual_value, constraint, context)

