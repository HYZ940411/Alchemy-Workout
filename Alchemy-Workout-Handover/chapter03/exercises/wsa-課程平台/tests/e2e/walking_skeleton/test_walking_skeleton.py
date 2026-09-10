"""
Walking Skeleton E2E Test

這個測試驗證整個系統架構能正常運作：
- PostgreSQL 容器啟動
- 資料庫 schema 建立
- FastAPI 服務運作
- HTTP API 呼叫成功
- 資料庫操作正確
"""
import pytest
from app.walking_skeleton.models.message import Message


class Test基礎設施驗證:
    """
    Rule: 基礎設施驗證
    """

    def test_health_check(
        self,
        api_client,
        api_base_url,
    ):
        """測試 health check endpoint"""

        # When 我呼叫健康檢查 API
        response = api_client.get(f"{api_base_url}/health")

        # Then 操作成功
        assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"

        # And 健康狀態應為 "ok"
        assert response.json() == {"status": "ok"}


class TestMessage基本操作:
    """
    Rule: Message 基本操作
    """

    def test_create_and_get_message(
        self,
        api_client,
        api_base_url,
        db_session,
    ):
        """測試建立和取得 message（完整的 E2E 流程）"""

        # Given 準備 message 資料
        message_data = {
            "content": "Hello World from Walking Skeleton!"
        }

        # When 建立 message
        create_response = api_client.post(
            f"{api_base_url}/api/messages",
            json=message_data
        )

        # Then 操作成功
        assert create_response.status_code == 201, f"預期 201，實際 {create_response.status_code}: {create_response.text}"

        # And 建立的 message 應包含正確內容
        created_message = create_response.json()
        assert created_message["content"] == "Hello World from Walking Skeleton!"
        assert "id" in created_message
        assert "created_at" in created_message

        message_id = created_message["id"]

        # When 取得 message
        get_response = api_client.get(f"{api_base_url}/api/messages/{message_id}")

        # Then 操作成功
        assert get_response.status_code == 200, f"預期 200，實際 {get_response.status_code}: {get_response.text}"

        # And 取得的 message 應與建立的一致
        fetched_message = get_response.json()
        assert fetched_message["id"] == message_id
        assert fetched_message["content"] == "Hello World from Walking Skeleton!"

    def test_list_messages(
        self,
        api_client,
        api_base_url,
    ):
        """測試列出所有 messages"""

        # Given 建立幾個 messages
        messages_to_create = [
            {"content": "Message 1"},
            {"content": "Message 2"},
            {"content": "Message 3"}
        ]

        # And 將 messages 逐一建立
        for message_data in messages_to_create:
            api_client.post(f"{api_base_url}/api/messages", json=message_data)

        # When 取得所有 messages
        response = api_client.get(f"{api_base_url}/api/messages")

        # Then 操作成功
        assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"

        # And 應包含 3 個 messages
        data = response.json()
        assert data["total"] == 3, f"預期 total 為 3，實際 {data['total']}"
        assert len(data["messages"]) == 3, f"預期 messages 數量為 3，實際 {len(data['messages'])}"

        # And 內容應與建立的一致
        contents = [msg["content"] for msg in data["messages"]]
        assert "Message 1" in contents
        assert "Message 2" in contents
        assert "Message 3" in contents

    def test_delete_message(
        self,
        api_client,
        api_base_url,
    ):
        """測試刪除 message"""

        # Given 建立一個 message
        create_response = api_client.post(
            f"{api_base_url}/api/messages",
            json={"content": "To be deleted"}
        )
        message_id = create_response.json()["id"]

        # When 刪除 message
        delete_response = api_client.delete(f"{api_base_url}/api/messages/{message_id}")

        # Then 操作成功
        assert delete_response.status_code == 204, f"預期 204，實際 {delete_response.status_code}: {delete_response.text}"

        # When 嘗試再次取得（應該失敗）
        get_response = api_client.get(f"{api_base_url}/api/messages/{message_id}")

        # Then 操作失敗
        assert get_response.status_code == 404, f"預期 404，實際 {get_response.status_code}: {get_response.text}"


class Test資料庫隔離機制:
    """
    Rule: 資料庫隔離機制
    """

    def test_database_isolation(
        self,
        api_client,
        api_base_url,
    ):
        """測試資料庫隔離（每個測試後會清空）"""

        # When 取得所有 messages
        response = api_client.get(f"{api_base_url}/api/messages")

        # Then 操作成功
        assert response.status_code == 200, f"預期 200，實際 {response.status_code}: {response.text}"

        # And 應該是空的（因為每個測試後都會 truncate）
        data = response.json()
        assert data["total"] == 0, f"預期 total 為 0，實際 {data['total']}"
        assert len(data["messages"]) == 0, f"預期 messages 數量為 0，實際 {len(data['messages'])}"
