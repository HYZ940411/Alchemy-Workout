"""
Behave 環境配置

設定測試環境的初始化、清理和 hooks
"""
from support.database import Database
from support.api_client import APIClient
from support.scenario_context import ScenarioContext
from support.assert_helper import AssertEvaluationHelper
import os


def before_all(context):
    """
    測試套件開始前執行一次
    
    初始化全域資源：
    - 資料庫連線
    - API 客戶端
    - 斷言助手
    """
    # 設定配置
    api_base_url = os.getenv('API_BASE_URL', 'http://localhost:8000')
    
    # 使用絕對路徑確保與後端共用同一個資料庫
    base_dir = os.path.dirname(os.path.abspath(__file__))
    db_path = os.path.join(base_dir, 'test_shared.db')
    db_connection = os.getenv('DB_CONNECTION', f'sqlite:///{db_path}')
    
    # 初始化資料庫
    context.db = Database(db_connection)
    context.db.create_all_tables()
    
    # 初始化 API 客戶端
    context.api_client = APIClient(base_url=api_base_url)
    
    # 初始化斷言助手
    context.assert_helper = AssertEvaluationHelper()
    
    print(f"\n✓ 測試環境初始化完成")
    print(f"  - API Base URL: {api_base_url}")
    print(f"  - Database: {db_connection}")


def before_scenario(context, scenario):
    """
    每個 scenario 開始前執行
    
    重置場景相關的狀態：
    - 清空資料庫
    - 建立新的 ScenarioContext
    - 重置錯誤狀態
    """
    # 清空資料庫
    context.db.clear_all_data()
    
    # 建立新的 ScenarioContext
    context.scenario_context = ScenarioContext()
    
    # 重置錯誤狀態
    context.error = None


def after_scenario(context, scenario):
    """
    每個 scenario 結束後執行
    
    可用於清理或記錄
    """
    # 如果測試失敗，輸出一些除錯資訊
    if scenario.status == 'failed':
        print(f"\n✗ Scenario 失敗: {scenario.name}")
        
        # 輸出 ScenarioContext 變數
        if hasattr(context, 'scenario_context'):
            vars_dict = context.scenario_context.get_all_vars()
            if vars_dict:
                print(f"  Context 變數: {vars_dict}")
        
        # 輸出最近的 API response
        if hasattr(context, 'scenario_context'):
            response = context.scenario_context.get_response()
            if response:
                print(f"  最近的 API Response:")
                print(f"    Status Code: {response.status_code}")
                try:
                    print(f"    Body: {response.json()}")
                except:
                    print(f"    Body: {response.text}")
        
        # 輸出錯誤資訊
        if hasattr(context, 'error') and context.error:
            print(f"  錯誤: {context.error}")


def after_all(context):
    """
    測試套件結束後執行一次
    
    清理全域資源
    """
    # 關閉資料庫連線
    if hasattr(context, 'db'):
        context.db.close_session()
    
    print(f"\n✓ 測試環境清理完成")

