"""
Given: 準備一個課程進度, with table:
插入 LessonProgress 測試資料到資料庫
"""
from behave import step
from support.models import LessonProgress
from steps.helpers.datatable_parser import parse_datatable


@step('準備一個課程進度, with table:')
def prepare_lesson_progress(context):
    """準備課程進度測試資料"""
    session = context.db.get_session()
    
    # 解析 DataTable
    rows = parse_datatable(context.table, context)
    
    for data, context_mappings in rows:
        # 建立 LessonProgress 物件
        progress = LessonProgress(
            user_id=data.get('userId'),
            lesson_id=data.get('lessonId'),
            progress=data.get('progress', 0.0),
            status=data.get('status', 'NOT_STARTED')
        )
        
        session.add(progress)
    
    session.commit()

