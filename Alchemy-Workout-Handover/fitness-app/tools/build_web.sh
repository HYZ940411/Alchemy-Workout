#!/usr/bin/env bash
# Web 版建置。
#
# 比 `flutter build web` 多一步：把打包進去的 Noto Sans TC 換成
# 「這個 App 真的會用到的字」的子集。理由與作法見 tools/subset_web_fonts.py。
#
# **一定要用這支，不要直接跑 flutter build web** ——
# 直接跑出來的字型是完整字集，首次載入會多背 11.5 MB（gzip 後）。
set -euo pipefail

cd "$(dirname "$0")/.."

VENV=tools/.venv
if [ ! -x "$VENV/bin/python" ]; then
  echo "→ 建立字型工具的 venv（只做一次）"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q fonttools brotli
fi

# 建置前先把可用記憶體印出來。
#
# dart2js 曾在 Codespaces 上以 `exit code -15`（SIGTERM）死掉 ——
# 那不是編譯錯誤，是行程被系統殺掉，幾乎都是記憶體不夠。
# 訊息裡完全看不出這件事，所以先把數字擺在這裡。
if command -v free >/dev/null 2>&1; then
  echo "→ 可用記憶體：$(free -h | awk '/^Mem:/ {print $7 " / " $2}')"
fi

# `--no-wasm-dry-run`：Flutter 預設會**額外編一次 wasm** 只為了檢查
# 相容性，我們沒有要出 wasm 版，那一趟純粹是多花一份記憶體與時間。
# 這個專案在 2 核心的 Codespace 上就是死在這裡。
echo "→ flutter build web --release --no-wasm-dry-run"
flutter build web --release --no-wasm-dry-run

echo "→ 子集化字型"
"$VENV/bin/python" tools/subset_web_fonts.py

echo
echo "→ 首次載入的實際傳輸量（gzip 後）"
total=0
for f in build/web/main.dart.js build/web/assets/assets/fonts/*.ttf; do
  [ -f "$f" ] || continue
  gz=$(gzip -c "$f" | wc -c | tr -d ' ')
  total=$((total + gz))
  printf "   %-52s %5d KB\n" "${f#build/web/}" $((gz / 1024))
done
printf "   %-52s %5d KB（另加 CanvasKit 約 2–3 MB）\n" "小計" $((total / 1024))
echo
echo "完成 → build/web"
