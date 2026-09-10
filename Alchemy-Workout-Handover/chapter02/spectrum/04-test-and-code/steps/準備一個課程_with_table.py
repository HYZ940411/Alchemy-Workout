"""
Given: 準備一個課程, with table:
插入 Lesson 測試資料到資料庫
"""
from behave import step
from support.models import Lesson
from steps.helpers.datatable_parser import parse_datatable, get_nested_value


@step('準備一個課程, with table:')
def prepare_lesson(context):
    """準備課程測試資料"""
    session = context.db.get_session()
    
    # 解析 DataTable
    rows = parse_datatable(context.table, context)
    
    for data, context_mappings in rows:
        # 處理巢狀欄位 reward.exp
        reward_exp = data.pop('reward.exp', None)
        
        # 建立 Lesson 物件
        lesson = Lesson(
            lesson_id=data.get('lesson_id'),
            name=data.get('name'),
            type=data.get('type'),
            journey_id=data.get('journey_id'),
            chapter_id=data.get('chapter_id'),
            reward_exp=reward_exp if reward_exp is not None else 0
        )
        
        session.add(lesson)
    
    session.commit()

