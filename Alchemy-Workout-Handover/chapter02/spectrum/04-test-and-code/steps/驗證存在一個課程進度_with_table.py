"""
Then: 驗證存在一個課程進度, with table:
查詢並驗證 LessonProgress 資料庫狀態
"""
from behave import step
from support.models import LessonProgress
from steps.helpers.datatable_parser import parse_datatable
from steps.helpers.constraint_validator import validate_constraints


@step('驗證存在一個課程進度, with table:')
def verify_lesson_progress_exists(context):
    """驗證課程進度存在且符合條件"""
    session = context.db.get_session()
    
    # 解析 DataTable
    rows = parse_datatable(context.table, context)
    
    # 第一行是查詢條件
    if len(rows) == 0:
        raise AssertionError("驗證表格不能為空")
    
    query_data, _ = rows[0]
    
    # 建立查詢條件
    query = session.query(LessonProgress)
    
    if 'userId' in query_data:
        query = query.filter(LessonProgress.user_id == query_data['userId'])
    
    if 'lessonId' in query_data:
        query = query.filter(LessonProgress.lesson_id == query_data['lessonId'])
    
    # 執行查詢
    progress = query.first()
    
    # 確認記錄存在
    assert progress is not None, \
        f"找不到課程進度: userId={query_data.get('userId')}, lessonId={query_data.get('lessonId')}"
    
    # 驗證欄位值
    for field, expected_value in query_data.items():
        if field in ['userId', 'lessonId']:
            continue  # 已用於查詢條件
        
        # 映射欄位名稱（camelCase -> snake_case）
        field_map = {
            'userId': 'user_id',
            'lessonId': 'lesson_id',
            'progress': 'progress',
            'status': 'status'
        }
        
        db_field = field_map.get(field, field)
        actual_value = getattr(progress, db_field, None)
        
        # 驗證值
        validate_constraints(actual_value, expected_value, context)
    
    # 如果有第二行，則為約束斷言行
    if len(rows) > 1:
        for i in range(1, len(rows)):
            constraint_data, _ = rows[i]
            
            for field, constraint in constraint_data.items():
                # 映射欄位名稱
                field_map = {
                    'userId': 'user_id',
                    'lessonId': 'lesson_id',
                    'progress': 'progress',
                    'status': 'status'
                }
                
                db_field = field_map.get(field, field)
                actual_value = getattr(progress, db_field, None)
                
                # 驗證約束
                validate_constraints(actual_value, constraint, context)

