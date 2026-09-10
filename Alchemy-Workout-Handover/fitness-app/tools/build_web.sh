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

echo "→ flutter build web --release"
flutter build web --release

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
