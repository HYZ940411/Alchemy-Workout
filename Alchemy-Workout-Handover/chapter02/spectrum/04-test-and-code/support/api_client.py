"""
API 客戶端

提供與課程平台 API 互動的介面
"""
import requests
from typing import Optional, Dict, Any
from support.auth import generate_token


class APIClient:
    """課程平台 API 客戶端"""
    
    def __init__(self, base_url='http://localhost:8000'):
        """
        初始化 API 客戶端
        
        Args:
            base_url: API 基礎 URL
        """
        self.base_url = base_url
        self.session = requests.Session()
    
    def _get_headers(self, user_id: Optional[int] = None) -> Dict[str, str]:
        """
        取得 HTTP headers
        
        Args:
            user_id: 用戶 ID（如果提供，會生成並加入 Bearer token）
            
        Returns:
            HTTP headers 字典
        """
        headers = {
            'Content-Type': 'application/json'
        }
        
        if user_id is not None:
            token = generate_token(user_id)
            headers['Authorization'] = f'Bearer {token}'
        
        return headers
    
    def update_video_progress(self, user_id: int, lesson_id: int, progress: float) -> requests.Response:
        """
        更新影片進度
        
        Args:
            user_id: 用戶 ID
            lesson_id: 課程 ID
            progress: 進度（0-100）
            
        Returns:
            requests.Response 物件
        """
        url = f"{self.base_url}/api/lessons/{lesson_id}/progress"
        data = {'progress': progress}
        headers = self._get_headers(user_id)
        
        return self.session.put(url, json=data, headers=headers)
    
    def submit_questionnaire(self, user_id: int, lesson_id: int, form_url: str) -> requests.Response:
        """
        提交問卷表單
        
        Args:
            user_id: 用戶 ID
            lesson_id: 課程 ID
            form_url: 問卷 URL
            
        Returns:
            requests.Response 物件
        """
        url = f"{self.base_url}/api/lessons/{lesson_id}/questionnaire"
        data = {'formUrl': form_url}
        headers = self._get_headers(user_id)
        
        return self.session.post(url, json=data, headers=headers)
    
    def submit_challenge(self, user_id: int, lesson_id: int, files: str) -> requests.Response:
        """
        提交挑戰題作業
        
        Args:
            user_id: 用戶 ID
            lesson_id: 課程 ID
            files: 作業檔案
            
        Returns:
            requests.Response 物件
        """
        url = f"{self.base_url}/api/lessons/{lesson_id}/challenge"
        data = {'files': files}
        headers = self._get_headers(user_id)
        
        return self.session.post(url, json=data, headers=headers)
    
    def submit_review(self, user_id: int, lesson_id: int, verdict: str) -> requests.Response:
        """
        提交批改結果
        
        Args:
            user_id: 用戶 ID
            lesson_id: 課程 ID
            verdict: 批改結果（PASS 或 FAIL）
            
        Returns:
            requests.Response 物件
        """
        url = f"{self.base_url}/api/lessons/{lesson_id}/review"
        data = {'verdict': verdict}
        headers = self._get_headers(user_id)
        
        return self.session.post(url, json=data, headers=headers)
    
    def deliver_lesson(self, user_id: int, lesson_id: int) -> requests.Response:
        """
        交付課程
        
        Args:
            user_id: 用戶 ID
            lesson_id: 課程 ID
            
        Returns:
            requests.Response 物件
        """
        url = f"{self.base_url}/api/lessons/{lesson_id}/deliver"
        headers = self._get_headers(user_id)
        
        return self.session.post(url, headers=headers)
    
    def subscribe_journey(self, user_id: int, journey_id: int) -> requests.Response:
        """
        訂閱旅程
        
        Args:
            user_id: 用戶 ID
            journey_id: 旅程 ID
            
        Returns:
            requests.Response 物件
        """
        url = f"{self.base_url}/api/users/{user_id}/subscriptions"
        data = {'journeyId': journey_id}
        headers = self._get_headers(user_id)
        
        return self.session.post(url, json=data, headers=headers)

