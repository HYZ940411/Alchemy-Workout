#!/usr/bin/env python3
"""git commit 前，提醒一次「完成條件」。

由 .claude/settings.json 的 PreToolUse hook 呼叫。
只在 Bash 指令真的含 `git commit` 時才出聲，其餘一律靜默 ——
提醒要少而準，天天出現就沒人看了。
"""
import json
import re
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cmd = (data.get("tool_input") or {}).get("command") or ""
# 只認「指令本身是 git commit」：行首或 && ; | 之後。
# 原本用 `"git commit" in cmd`，結果寫進檔案的文字、heredoc 內容
# 只要提到這四個字也會誤觸發。
if not re.search(r"(^|[;&|\n])\s*git\s+(-C\s+\S+\s+)?commit\b", cmd):
    sys.exit(0)

msg = (
    "【commit 前自問，缺一項就先補】"
    "①有重現過問題？ ②有測試釘住，且故意弄壞實作時測試會紅？ "
    "③flutter analyze lib test 乾淨、全量測試跑完且貼過結果？ "
    "④PROGRESS 記了（問題、原因、怎麼修、怎麼驗）？ "
    "⑤回報時要寫「還沒驗什麼」，不可留空。"
    "沒證據不說修好了。"
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": msg,
    }
}, ensure_ascii=False))
