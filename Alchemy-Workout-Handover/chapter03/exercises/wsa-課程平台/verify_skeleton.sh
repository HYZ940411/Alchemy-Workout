#!/bin/bash

# Walking Skeleton 驗證腳本
# 這個腳本會驗證整個系統架構是否能正常運作
# 使用 Testcontainers 自動管理 Docker 容器，無需手動啟動服務

set -e  # 遇到錯誤立即停止

echo "=========================================="
echo "Walking Skeleton 驗證開始"
echo "=========================================="

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 檢查函數
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 已安裝"
        return 0
    else
        echo -e "${RED}✗${NC} $1 未安裝"
        return 1
    fi
}

# 步驟 1: 檢查必要工具
echo ""
echo "步驟 1: 檢查必要工具"
echo "----------------------------------------"
check_command python3 || exit 1
check_command pip3 || exit 1
check_command docker || exit 1
# 檢查 Docker 是否運行
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗${NC} Docker 未運行，請啟動 Docker Desktop"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker 服務運行中"

# 步驟 2: 檢查必要檔案
echo ""
echo "步驟 2: 檢查必要檔案"
echo "----------------------------------------"
required_files=(
    "requirements.txt"
    "requirements-dev.txt"
    "app/main.py"
    "app/walking_skeleton/models/message.py"
    "app/walking_skeleton/api/messages.py"
    "app/walking_skeleton/schemas/message.py"
    "tests/e2e/conftest.py"
    "tests/e2e/walking_skeleton/test_walking_skeleton.py"
    "alembic.ini"
    "Dockerfile"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file 存在"
    else
        echo -e "${RED}✗${NC} $file 不存在"
        exit 1
    fi
done

# 步驟 3: 安裝 Python 依賴
echo ""
echo "步驟 3: 安裝 Python 依賴"
echo "----------------------------------------"
if [ ! -d "venv" ]; then
    echo "建立虛擬環境..."
    python3 -m venv venv
fi

echo "啟動虛擬環境並安裝依賴..."
source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements-dev.txt
echo -e "${GREEN}✓${NC} 依賴安裝完成"

# 步驟 4: 檢查後端 Docker 映像
echo ""
echo "步驟 4: 檢查後端 Docker 映像"
echo "----------------------------------------"
if docker images | grep -q "wsa--backend"; then
    echo -e "${GREEN}✓${NC} 後端 Docker 映像已存在"
else
    echo -e "${YELLOW}⚠${NC} 後端 Docker 映像不存在，正在建置..."
    docker build -t wsa--backend:latest .
    echo -e "${GREEN}✓${NC} 後端 Docker 映像建置完成"
fi

# 步驟 5: 執行 E2E 測試（Testcontainers 會自動管理容器）
echo ""
echo "步驟 5: 執行 E2E 測試"
echo "----------------------------------------"
echo "注意：Testcontainers 會自動啟動以下容器："
echo "  - PostgreSQL 容器（用於測試資料庫）"
echo "  - 後端 API 容器（用於測試 API）"
echo "測試結束後，容器會自動清理"
echo ""
pytest tests/e2e/walking_skeleton/test_walking_skeleton.py -v
TEST_RESULT=$?

# 步驟 6: 總結
echo ""
echo "=========================================="
if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Walking Skeleton 驗證成功！${NC}"
    echo ""
    echo "所有測試通過，系統架構運作正常。"
    echo ""
    echo "測試說明："
    echo "  - Testcontainers 已自動啟動並清理所有測試容器"
    echo "  - 每個測試都在獨立的環境中執行，確保測試隔離"
    echo ""
    echo "你可以："
    echo "  1. 執行 'pytest tests/e2e/walking_skeleton/test_walking_skeleton.py -v' 再次執行測試"
    echo "  2. 使用 'docker-compose up' 啟動完整開發環境（用於手動測試）"
    echo "  3. 訪問 http://localhost:8000/docs 查看 API 文檔（需要先啟動開發環境）"
    exit 0
else
    echo -e "${RED}✗ Walking Skeleton 驗證失敗${NC}"
    echo ""
    echo "請檢查錯誤訊息並修復問題。"
    echo ""
    echo "常見問題："
    echo "  - 確認 Docker 正在運行"
    echo "  - 確認後端 Docker 映像已建置（wsa--backend:latest）"
    echo "  - 檢查測試日誌中的詳細錯誤訊息"
    exit 1
fi
