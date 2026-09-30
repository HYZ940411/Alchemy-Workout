#!/bin/bash
# 產生教官測驗題庫的覆核文件（PDF ＋ Word）。
#
# 覆核是待辦清單裡唯一的硬性上線阻擋，而要找的人不會去讀 Dart 原始碼，
# 所以得有一份印得出來、標得了意見的檔案。
#
# **不裝任何東西**：PDF 用 macOS 上本來就有的 Chrome 無介面列印，
# Word 用系統內建的 textutil。裝 pandoc／wkhtmltopdf 反而要先解中日韓
# 字型的問題，那是繞遠路。
#
# 用法：
#   cd fitness-app
#   ./tools/export_exam_bank.sh
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="build/exam_bank"
HTML="$OUT_DIR/exam_bank.html"
PDF="$OUT_DIR/健金術_教官測驗題庫_覆核用.pdf"
DOC="$OUT_DIR/健金術_教官測驗題庫_覆核用.doc"

mkdir -p "$OUT_DIR"
dart run tools/export_exam_bank.dart "$HTML"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ -x "$CHROME" ]; then
  # `--headless=new` 是現行的無介面模式；`--no-pdf-header-footer` 拿掉
  # 頁首頁尾那行網址（那是本機路徑，交給外部的人看沒有意義）。
  "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$PWD/$PDF" "file://$PWD/$HTML" 2>/dev/null
  echo "PDF  → $PDF"
else
  echo "⚠️ 找不到 Chrome，略過 PDF。HTML 可以自己用瀏覽器開後列印成 PDF。"
fi

# textutil 讀 HTML 產 .doc。Word、Pages、Google Docs 都開得起來，
# 而且是**可編輯**的 —— 覆核的人可以直接在檔案裡打字。
textutil -convert doc -output "$DOC" "$HTML"
echo "Word → $DOC"
