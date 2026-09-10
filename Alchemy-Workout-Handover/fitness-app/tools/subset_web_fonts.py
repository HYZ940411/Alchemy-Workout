#!/usr/bin/env python3
"""把 Web 版打包的 Noto Sans TC 縮成「這個 App 真的會用到的字」。

為什麼只有 Web 版做這件事
---------------------------
UI 設計規格書 §2.1 明訂「嵌入 Noto Sans TC，三個字重，完整字集不瘦身」。
那條規則在手機上是對的：安裝檔大一點無所謂，而使用者自己打的字
（貼文、私訊、自建動作名稱）不能變成豆腐。

Web 不一樣 —— 那 21 MB 是**每個第一次開網頁的人都要等的下載**
（gzip 後仍有 12.5 MB）。所以只在 Web 版做子集化，手機版一個位元組都不動。

罕用字怎麼辦
-------------
Flutter 引擎內建字型後備：它把 Noto Sans TC 切成 105 個 unicode-range
分段放在 fonts.gstatic.com，遇到任何已註冊字型都沒有的字元，會自動抓
對應的那一段（每段約 5 KB）。所以子集外的字**照樣顯示得出來**，
只是後備字型沒有字重變體，粗體會由引擎合成。

換句話說：**App 自己的介面文字**維持三個真字重（規格照舊），
使用者臨時打出的罕用字退化為單一字重。這是刻意的取捨，不是遺漏。

只改建置產物
-------------
本腳本**不動 assets/fonts/ 裡的原檔**，只覆寫 build/web 底下那一份。
`flutter build web` 重跑一次就回到完整字集，改壞了也救得回來。
"""

import re
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent

# 這個 App 會用到的字，從原始碼與資料檔裡直接掃出來 ——
# 手工維護一張字表必然會漏，而漏掉的那個字就是一個豆腐。
CJK = re.compile(r'[　-〿㐀-䶿一-鿿豈-﫿＀-￯]')

# 一定要留的：ASCII、常用標點、數字、單位符號。
ALWAYS = set(chr(c) for c in range(0x20, 0x7f))
ALWAYS |= set('　、。，．：；！？「」『』（）〈〉《》—…・～％℃±×÷≥≤°′″')
ALWAYS |= set('←→↑↓✓✗●○■□▲▼★☆')


def used_chars() -> set[str]:
    out = set(ALWAYS)
    for pat in ('lib/**/*.dart', 'assets/**/*.json', 'test/**/*.dart'):
        for p in ROOT.glob(pat):
            try:
                t = p.read_text(encoding='utf-8')
            except (UnicodeDecodeError, OSError):
                continue
            out |= set(CJK.findall(t))
    return out


def main(outdir: pathlib.Path) -> int:
    chars = used_chars()
    text = ''.join(sorted(chars))
    print(f'要保留的字元數：{len(chars)}')

    total_before = total_after = 0
    for src in sorted((ROOT / 'assets' / 'fonts').glob('NotoSansTC-*.ttf')):
        dst = outdir / src.name
        if not dst.exists():
            print(f'  跳過 {src.name}：{dst} 不存在', file=sys.stderr)
            continue

        before = dst.stat().st_size
        font = TTFont(str(src))

        # 原字型**本來就有**的那些字，才是子集化不該弄丟的。
        # 拿整份必留清單去比會誤報：像 ✗（U+2717）Noto Sans TC 根本沒有，
        # 它一直都是靠後備字型顯示的，與子集化無關。
        original = set()
        for t in font['cmap'].tables:
            original |= set(t.cmap.keys())
        expected = {c for c in chars if ord(c) in original}
        subsetter = subset.Subsetter(
            options=subset.Options(
                # 版面規則要留著：中文標點的擠壓、數字的等寬對齊，
                # 少了它們排版會走樣。
                layout_features=['*'],
                notdef_outline=True,
                name_IDs='*',
                recommended_glyphs=True,
            )
        )
        subsetter.populate(text=text)
        subsetter.subset(font)

        # **子集化完自己驗一次。** 少了這一步，某個字被漏掉不會有任何徵兆
        # —— 直到有人在畫面上看到一個豆腐，而那時已經上線了。
        cmap = set()
        for t in font['cmap'].tables:
            cmap |= set(t.cmap.keys())
        missing = sorted(c for c in expected if ord(c) not in cmap)
        if missing:
            print(f'  {src.name}: 子集化後少了 {len(missing)} 個字：'
                  f'{"".join(missing[:20])}', file=sys.stderr)
            return 2

        font.save(str(dst))
        after = dst.stat().st_size

        total_before += before
        total_after += after
        print(f'  {src.name}: {before // 1024} KB → {after // 1024} KB')

    if total_before == 0:
        print('沒有任何字型被處理 —— 先跑 flutter build web', file=sys.stderr)
        return 1
    print(f'合計：{total_before // 1024} KB → {total_after // 1024} KB '
          f'（省下 {100 - total_after * 100 // total_before}%）')
    return 0


if __name__ == '__main__':
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        ROOT / 'build' / 'web' / 'assets' / 'assets' / 'fonts'
    sys.exit(main(target))
