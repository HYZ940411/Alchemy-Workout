"""
AssertEvaluationHelper: 完整的約束斷言系統 (Constraint Assertion System)

支援 8 大類約束斷言：
1. 數值比較：&eq, &ne, &gt, &lt, &ge, &le
2. 類型檢查：&isNum, &isStr, &isBool, &isNull, &isNotNull, &isUndef, &isDef
3. 字串操作：&contains, &startsWith, &endsWith, &matches, &length
4. 集合/陣列：&hasItem, &hasNoItem, &size, &isEmpty, &isNotEmpty
5. 存在性：&exists, &notExists, &hasField, &noField
6. 範圍檢查：&between, &notBetween, &oneOf, &noneOf
7. 時間相關：&before, &after, &timeRange, &sameDay, &withinDays
8. 函數調用：&called, &calledWith, &notCalled, &calledBefore
"""
import re
from typing import Any, List, Optional, Union
from datetime import datetime, timedelta
from dateutil import parser as date_parser


class AssertEvaluationHelper:
    """約束斷言評估器"""
    
    def __init__(self):
        """初始化評估器"""
        self._constraint_pattern = re.compile(r'&(\w+)(?:\(([^)]*)\))?')
    
    def evaluate(self, actual_value: Any, constraint_expr: str, context=None) -> bool:
        """
        評估單一約束表達式
        
        Args:
            actual_value: 實際值
            constraint_expr: 約束表達式（如 '&gt(0)' 或 '&isStr'）
            context: ScenarioContext 物件（用於解析變數）
            
        Returns:
            是否通過約束檢查
        """
        match = self._constraint_pattern.match(constraint_expr.strip())
        if not match:
            raise ValueError(f"無效的約束表達式: {constraint_expr}")
        
        constraint_name = match.group(1)
        params_str = match.group(2) if match.group(2) else ""
        
        # 解析參數
        params = self._parse_params(params_str, context)
        
        # 呼叫對應的約束檢查方法
        method_name = f"_check_{constraint_name}"
        if hasattr(self, method_name):
            method = getattr(self, method_name)
            return method(actual_value, params)
        else:
            raise ValueError(f"不支援的約束: &{constraint_name}")
    
    def evaluate_multiple(self, actual_value: Any, constraint_exprs: str, context=None) -> bool:
        """
        評估多個約束表達式（空格分隔）
        
        Args:
            actual_value: 實際值
            constraint_exprs: 多個約束表達式（如 '&isNum &gt(0) &le(100)'）
            context: ScenarioContext 物件
            
        Returns:
            是否通過所有約束檢查
        """
        # 分割多個約束（以空格分隔）
        exprs = self._split_constraints(constraint_exprs)
        
        for expr in exprs:
            if not self.evaluate(actual_value, expr, context):
                return False
        
        return True
    
    def _split_constraints(self, constraint_exprs: str) -> List[str]:
        """分割多個約束表達式"""
        constraints = []
        current = ""
        paren_depth = 0
        
        for char in constraint_exprs:
            if char == '(':
                paren_depth += 1
                current += char
            elif char == ')':
                paren_depth -= 1
                current += char
            elif char == ' ' and paren_depth == 0:
                if current.strip():
                    constraints.append(current.strip())
                current = ""
            else:
                current += char
        
        if current.strip():
            constraints.append(current.strip())
        
        return constraints
    
    def _parse_params(self, params_str: str, context=None) -> List[Any]:
        """解析參數列表"""
        if not params_str:
            return []
        
        # 分割參數（以逗號分隔）
        params = []
        current = ""
        paren_depth = 0
        quote_char = None
        
        for char in params_str:
            if char in ('"', "'") and quote_char is None:
                quote_char = char
            elif char == quote_char:
                quote_char = None
            elif char == '(' and quote_char is None:
                paren_depth += 1
            elif char == ')' and quote_char is None:
                paren_depth -= 1
            elif char == ',' and paren_depth == 0 and quote_char is None:
                params.append(self._parse_param_value(current.strip(), context))
                current = ""
                continue
            
            current += char
        
        if current.strip():
            params.append(self._parse_param_value(current.strip(), context))
        
        return params
    
    def _parse_param_value(self, value: str, context=None) -> Any:
        """解析單一參數值"""
        value = value.strip()
        
        # 處理引號包裹的字串
        if (value.startswith('"') and value.endswith('"')) or \
           (value.startswith("'") and value.endswith("'")):
            return value[1:-1]
        
        # 處理變數引用 $variable
        if value.startswith('$') and context:
            return context.resolve_value(value)
        
        # 處理數字
        try:
            if '.' in value:
                return float(value)
            return int(value)
        except ValueError:
            pass
        
        # 處理布林值
        if value.lower() == 'true':
            return True
        if value.lower() == 'false':
            return False
        
        # 處理 null
        if value.lower() in ('null', 'none'):
            return None
        
        # 其他情況當作字串
        return value
    
    # ==================== 1. 數值比較斷言 ====================
    
    def _check_eq(self, actual: Any, params: List[Any]) -> bool:
        """等於"""
        return actual == params[0]
    
    def _check_ne(self, actual: Any, params: List[Any]) -> bool:
        """不等於"""
        return actual != params[0]
    
    def _check_gt(self, actual: Any, params: List[Any]) -> bool:
        """大於"""
        return float(actual) > float(params[0])
    
    def _check_lt(self, actual: Any, params: List[Any]) -> bool:
        """小於"""
        return float(actual) < float(params[0])
    
    def _check_ge(self, actual: Any, params: List[Any]) -> bool:
        """大於等於"""
        return float(actual) >= float(params[0])
    
    def _check_le(self, actual: Any, params: List[Any]) -> bool:
        """小於等於"""
        return float(actual) <= float(params[0])
    
    # ==================== 2. 類型檢查斷言 ====================
    
    def _check_isNum(self, actual: Any, params: List[Any]) -> bool:
        """是數字"""
        return isinstance(actual, (int, float)) and not isinstance(actual, bool)
    
    def _check_isStr(self, actual: Any, params: List[Any]) -> bool:
        """是字串"""
        return isinstance(actual, str)
    
    def _check_isBool(self, actual: Any, params: List[Any]) -> bool:
        """是布林值"""
        return isinstance(actual, bool)
    
    def _check_isNull(self, actual: Any, params: List[Any]) -> bool:
        """是 null"""
        return actual is None
    
    def _check_isNotNull(self, actual: Any, params: List[Any]) -> bool:
        """不是 null"""
        return actual is not None
    
    def _check_isUndef(self, actual: Any, params: List[Any]) -> bool:
        """是 undefined（在 Python 中視為 None）"""
        return actual is None
    
    def _check_isDef(self, actual: Any, params: List[Any]) -> bool:
        """已定義（不是 undefined）"""
        return actual is not None
    
    # ==================== 3. 字串操作斷言 ====================
    
    def _check_contains(self, actual: Any, params: List[Any]) -> bool:
        """包含子字串"""
        return str(params[0]) in str(actual)
    
    def _check_startsWith(self, actual: Any, params: List[Any]) -> bool:
        """開始於"""
        return str(actual).startswith(str(params[0]))
    
    def _check_endsWith(self, actual: Any, params: List[Any]) -> bool:
        """結束於"""
        return str(actual).endswith(str(params[0]))
    
    def _check_matches(self, actual: Any, params: List[Any]) -> bool:
        """符合正則表達式"""
        pattern = str(params[0])
        return re.match(pattern, str(actual)) is not None
    
    def _check_length(self, actual: Any, params: List[Any]) -> bool:
        """字串長度範圍"""
        length = len(str(actual))
        if len(params) == 1:
            return length == int(params[0])
        elif len(params) == 2:
            return int(params[0]) <= length <= int(params[1])
        return False
    
    # ==================== 4. 集合/陣列斷言 ====================
    
    def _check_hasItem(self, actual: Any, params: List[Any]) -> bool:
        """包含元素"""
        if not isinstance(actual, (list, tuple, set)):
            return False
        return params[0] in actual
    
    def _check_hasNoItem(self, actual: Any, params: List[Any]) -> bool:
        """不包含元素"""
        if not isinstance(actual, (list, tuple, set)):
            return True
        return params[0] not in actual
    
    def _check_size(self, actual: Any, params: List[Any]) -> bool:
        """集合大小"""
        if not isinstance(actual, (list, tuple, set, dict)):
            return False
        return len(actual) == int(params[0])
    
    def _check_isEmpty(self, actual: Any, params: List[Any]) -> bool:
        """是空集合"""
        if not isinstance(actual, (list, tuple, set, dict, str)):
            return False
        return len(actual) == 0
    
    def _check_isNotEmpty(self, actual: Any, params: List[Any]) -> bool:
        """不是空集合"""
        if not isinstance(actual, (list, tuple, set, dict, str)):
            return False
        return len(actual) > 0
    
    # ==================== 5. 存在性斷言 ====================
    
    def _check_exists(self, actual: Any, params: List[Any]) -> bool:
        """存在（不是 None）"""
        return actual is not None
    
    def _check_notExists(self, actual: Any, params: List[Any]) -> bool:
        """不存在（是 None）"""
        return actual is None
    
    def _check_hasField(self, actual: Any, params: List[Any]) -> bool:
        """有特定欄位"""
        if isinstance(actual, dict):
            return params[0] in actual
        return hasattr(actual, params[0])
    
    def _check_noField(self, actual: Any, params: List[Any]) -> bool:
        """沒有特定欄位"""
        if isinstance(actual, dict):
            return params[0] not in actual
        return not hasattr(actual, params[0])
    
    # ==================== 6. 範圍檢查斷言 ====================
    
    def _check_between(self, actual: Any, params: List[Any]) -> bool:
        """在範圍內"""
        return float(params[0]) <= float(actual) <= float(params[1])
    
    def _check_notBetween(self, actual: Any, params: List[Any]) -> bool:
        """不在範圍內"""
        return not (float(params[0]) <= float(actual) <= float(params[1]))
    
    def _check_oneOf(self, actual: Any, params: List[Any]) -> bool:
        """是其中一個值"""
        return actual in params
    
    def _check_noneOf(self, actual: Any, params: List[Any]) -> bool:
        """不是其中任何值"""
        return actual not in params
    
    # ==================== 7. 時間相關斷言 ====================
    
    def _check_before(self, actual: Any, params: List[Any]) -> bool:
        """在時間之前"""
        actual_dt = self._parse_datetime(actual)
        expected_dt = self._parse_datetime(params[0])
        return actual_dt < expected_dt
    
    def _check_after(self, actual: Any, params: List[Any]) -> bool:
        """在時間之後"""
        actual_dt = self._parse_datetime(actual)
        expected_dt = self._parse_datetime(params[0])
        return actual_dt > expected_dt
    
    def _check_timeRange(self, actual: Any, params: List[Any]) -> bool:
        """在時間範圍內"""
        actual_dt = self._parse_datetime(actual)
        start_dt = self._parse_datetime(params[0])
        end_dt = self._parse_datetime(params[1])
        return start_dt <= actual_dt <= end_dt
    
    def _check_sameDay(self, actual: Any, params: List[Any]) -> bool:
        """同一天"""
        actual_dt = self._parse_datetime(actual)
        expected_dt = self._parse_datetime(params[0])
        return actual_dt.date() == expected_dt.date()
    
    def _check_withinDays(self, actual: Any, params: List[Any]) -> bool:
        """在幾天內"""
        actual_dt = self._parse_datetime(actual)
        now = datetime.now()
        days = int(params[0])
        return abs((actual_dt - now).days) <= days
    
    def _parse_datetime(self, value: Any) -> datetime:
        """解析時間字串或物件"""
        if isinstance(value, datetime):
            return value
        if isinstance(value, str):
            # 特殊關鍵字
            if value.lower() == 'now':
                return datetime.now()
            if value.lower() == 'today':
                return datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            # 使用 dateutil 解析
            return date_parser.parse(value)
        raise ValueError(f"無法解析時間值: {value}")
    
    # ==================== 8. 函數調用斷言 ====================
    
    def _check_called(self, actual: Any, params: List[Any]) -> bool:
        """被調用次數"""
        if not isinstance(actual, dict) or 'call_count' not in actual:
            return False
        return actual['call_count'] == int(params[0])
    
    def _check_calledWith(self, actual: Any, params: List[Any]) -> bool:
        """被調用時的參數"""
        if not isinstance(actual, dict) or 'call_args' not in actual:
            return False
        return actual['call_args'] == tuple(params)
    
    def _check_notCalled(self, actual: Any, params: List[Any]) -> bool:
        """未被調用"""
        if not isinstance(actual, dict) or 'call_count' not in actual:
            return False
        return actual['call_count'] == 0
    
    def _check_calledBefore(self, actual: Any, params: List[Any]) -> bool:
        """在某個時間點前被調用"""
        if not isinstance(actual, dict) or 'called_at' not in actual:
            return False
        called_at = self._parse_datetime(actual['called_at'])
        deadline = self._parse_datetime(params[0])
        return called_at < deadline

