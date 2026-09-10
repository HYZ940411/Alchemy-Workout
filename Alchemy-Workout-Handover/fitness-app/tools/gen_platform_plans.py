#!/usr/bin/env python3
"""把《健身計劃.csv》＋《健身計劃-組數次數.csv》產生成平台課表。

輸出 lib/mock/platform_plans.g.dart —— **請勿手改**，改資料來源再重跑。

三個對應的判斷都寫在下面，不埋在數字裡：
  級別 → 階級門檻、器材、每組目標重量、時間型動作怎麼表達。
"""

import csv
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = ROOT.parent
SRC = REPO / '健身計劃.csv'
VOL = REPO / '健身計劃-組數次數.csv'
DST = ROOT / 'lib' / 'mock' / 'platform_plans.g.dart'

EQUIP = ('槓鈴', '啞鈴', '彈力帶', '滑輪機', '器械', '史密斯架', '壺鈴', '繩索')
SEP = re.compile(r'\s*[-。·]\s*(?=(?:%s))' % '|'.join(EQUIP))

# 級別 → 階級門檻。
#
# **27 份全部不設限**（2026-09-09 使用者裁示）。級別仍然標示在課表上，
# 但只作為難度提示，不擋人。
#
# 理由：Beta 期間多數測試者階級都低，設了門檻等於大半內容沒人看得到，
# 也就收不到那些課表的回饋。回歸課表本來就不該鎖 ——
# 「退步的人才需要，鎖了等於需要的人打不開」。
#
# 之後要加回門檻，把下面的值改掉再重跑即可；
# 原本的設計是戰士級 20（沿用教官初審門檻）、精銳級 45（自訂訓練名額里程碑）。
RANK = {'學員級': None, '功能重啟級': None, '戰士級': None, '精銳級': None}

# 名稱裡有器材字樣就是健身房課表，否則徒手。
def tier(name: str) -> str:
    if '無器材' in name:
        return '徒手'
    if any(e in name for e in EQUIP) or '機械' in name:
        return '健身房'
    return '徒手'


def norm(n: str) -> str:
    n = re.sub(r'\(https?://[^)]*\)', '', n).strip()
    return re.sub(r'\s+', ' ', SEP.sub(' · ', n)).strip()


def dq(s: str) -> str:
    """Dart 單引號字串。換行壓成空白 —— 這些欄位是說明文字，不是排版。"""
    s = re.sub(r'\s+', ' ', (s or '')).strip()
    return "'" + s.replace('\\', r'\\').replace("'", r"\'").replace('$', r'\$') + "'"


def main() -> int:
    plans = list(csv.DictReader(open(SRC, encoding='utf-8-sig')))
    vol = list(csv.DictReader(open(VOL, encoding='utf-8-sig')))

    src = (ROOT / 'lib' / 'mock' / 'platform_exercises.g.dart').read_text('utf-8')
    lib = dict(re.findall(r"id: '([^']+)',\s*\n\s*name: '([^']+)'", src))
    by_name = {v: k for k, v in lib.items()}
    cardio = set(re.findall(
        r"id: '([^']+)',\s*\n\s*name: '[^']+',\s*\n\s*dim: [^,]+,\s*\n"
        r"\s*type: ExerciseType\.cardio", src))

    by_plan = {}
    for v in vol:
        by_plan.setdefault(int(v['課表編號']), []).append(v)

    out = [
        '// 平台訓練計畫 —— 由《健身計劃.csv》產生，請勿手改。',
        '// 重新產生：python3 tools/gen_platform_plans.py',
        '//',
        '// 27 份課表，四個級別。組數／次數／休息的來源見 健身計劃-組數次數.csv，',
        '// 每一列都標得出是課表作者明寫的、由時長估算的，還是取級別中位數的。',
        '//',
        '// **目標重量一律為 0**：這份資料以 RPE（自覺強度）開處方，不指定公斤數。',
        '// 徒手動作本來就不需要；器械動作則由使用者依 RPE 自行決定 ——',
        '// 替一個沒見過的人填一個具體重量，比留白危險。',
        "import '../domain/platform_plan.dart';",
        '',
        'const kPlatformPlans = <PlatformPlanSpec>[',
    ]

    skipped = []
    for i, p in enumerate(plans):
        rows = by_plan.get(i, [])
        items = []
        for r in rows:
            name = norm(r['動作名稱'])
            eid = by_name.get(name)
            if eid is None:
                skipped.append(f'{p["計劃名稱"]} / {name}')
                continue
            sets = int(r['組數'])
            if r['每組秒數']:
                reps, unit = int(r['每組秒數']), 'seconds'
            else:
                reps, unit = int(r['每組次數']), 'reps'
            items.append(
                f"      PlanItemSpec('{eid}', {sets}, {reps}, "
                f"PlanUnit.{unit}, {r['組間休息秒']}),")

        if not items:
            continue
        lvl = p['選取']
        rank = RANK.get(lvl)
        out += [
            '  PlatformPlanSpec(',
            f"    id: 'csv{i:02d}',",
            f'    name: {dq(p["計劃名稱"])},',
            f'    level: {dq(lvl)},',
            f'    requiredRank: {rank if rank else "null"},',
            f'    equipmentTier: {dq(tier(p["計劃名稱"]))},',
            f'    duration: {dq(p["預估運動時長"])},',
            f'    intro: {dq(p["課表介紹"])},',
            f'    howTo: {dq(p["使用說明"])},',
            f'    load: {dq(p["負荷大小"])},',
            f'    effect: {dq(p["訓練效果(重點)"])},',
            f'    technique: {dq(p["技術特點"])},',
            f'    reference: {dq(p["來源/根據"])},',
            '    items: [',
            *items,
            '    ],',
            '  ),',
        ]
    out += [']', ';', '']

    DST.write_text('\n'.join(out).replace(']\n;', '];'), encoding='utf-8')
    n = sum(1 for line in out if line.startswith('  PlatformPlanSpec('))
    print(f'產生 {n} 份課表 → {DST.relative_to(ROOT)}')
    if skipped:
        print(f'對不到動作 {len(skipped)} 個：')
        for s in skipped[:10]:
            print('   ✗', s)
        return 1
    print('所有動作都對得上動作庫 ✓')
    return 0


if __name__ == '__main__':
    sys.exit(main())
