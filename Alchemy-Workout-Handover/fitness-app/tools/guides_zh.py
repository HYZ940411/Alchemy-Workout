#!/usr/bin/env python3
"""動作教學文字的中譯工作台。

三個子命令：
  dump  <start> <count>   印出待譯的原文（含動作中文名，供判斷術語）
  merge <json-file>       把一批譯文合併進 exercise_guides.zh.json
  status                  還剩幾筆沒譯
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'assets/data/exercise_guides.json'
DST = ROOT / 'assets/data/exercise_guides.zh.json'
GEN = ROOT / 'lib/mock/platform_exercises.g.dart'


def names():
    """動作 ID → 中文名。譯文用得到：同一個英文詞在不同動作下譯法不同。"""
    src = GEN.read_text(encoding='utf-8')
    out = {}
    for m in re.finditer(r"id: '([^']+)',\s*\n?\s*name: '([^']+)'", src):
        out[m.group(1)] = m.group(2)
    return out


def load_dst():
    return json.loads(DST.read_text(encoding='utf-8')) if DST.exists() else {}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'status'
    src = json.loads(SRC.read_text(encoding='utf-8'))
    dst = load_dst()

    if cmd == 'status':
        todo = [k for k in src if k not in dst]
        print(f'已譯 {len(dst)} / {len(src)}，還剩 {len(todo)} 筆')
        if todo:
            print('下一筆：', todo[0])
        return

    if cmd == 'dump':
        start, count = int(sys.argv[2]), int(sys.argv[3])
        nm = names()
        todo = [k for k in src if k not in dst][start:start + count]
        out = {}
        for k in todo:
            v = dict(src[k])
            # 去掉 BOM 與首尾空白，譯文不必跟著帶
            for f in ('setup', 'howto', 'tips'):
                v[f] = v.get(f, '').replace('﻿', '').strip()
            v['_name'] = nm.get(k, '?')
            out[k] = v
        print(json.dumps(out, ensure_ascii=False, indent=1))
        return

    if cmd == 'merge':
        batch = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
        for k, v in batch.items():
            if k not in src:
                raise SystemExit(f'未知的動作 ID：{k}')
            dst[k] = {f: v.get(f, '') for f in ('setup', 'howto', 'tips')}
        ordered = {k: dst[k] for k in src if k in dst}
        DST.write_text(
            json.dumps(ordered, ensure_ascii=False, indent=1) + '\n',
            encoding='utf-8')
        print(f'已合併 {len(batch)} 筆，累計 {len(ordered)} / {len(src)}')
        return

    raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
