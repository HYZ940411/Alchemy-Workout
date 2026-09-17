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

# 級別 → 適用經驗（註冊問卷的三級值域）。
#
# 功能重啟級對三級都適用（2026-09-18 使用者裁決）：功能性課表是活動度與
# 復健性質，跟訓練年資無關 —— 練了五年的人肩頸痛一樣該做。只標「新手」
# 的話，中階／進階使用者在退步或受傷後推薦不到它。
EXPERIENCE = {
    '學員級': ['新手（未滿 6 個月）'],
    '戰士級': ['中階（6 個月–2 年）'],
    '精銳級': ['進階（2 年以上）'],
    '功能重啟級': ['新手（未滿 6 個月）', '中階（6 個月–2 年）', '進階（2 年以上）'],
}

# 課表 → 適用目標（註冊問卷的常見目標四值）。
#
# **這一份是判斷，不是資料。** 《健身計劃.csv》沒有目標欄，所以每一列的
# 依據都取自該課表自己寫的「訓練效果(重點)」欄 —— 不是照名字猜的。
# 草案於 2026-09-18 由使用者逐列審核通過。
#
# 鍵為課表編號（＝ CSV 的列序，也就是 id 的 csvNN）。用編號而非名稱：
# 「無器材－核心」有三份（學員／戰士／精銳），名稱撞號。
#
# 空清單代表「不特別針對任何目標」，而 recommendPlan 會視為全部符合 ——
# 目前 27 份都有值，沒有留空的。
G_MUSCLE, G_LOSE = '增肌', '減重'
G_HABIT, G_FITNESS = '培養運動習慣', '提升體能'
GOALS = {
    0:  [G_MUSCLE, G_HABIT],            # 無器材-胸部：「胸肌肌肥大與發力感」
    1:  [G_HABIT, G_FITNESS],           # 無器材-肩膀：暖身與活動度、輕度肌耐力
    2:  [G_HABIT, G_FITNESS],           # 無器材-背部：腰背伸展力量與耐力、改善駝背
    3:  [G_LOSE, G_FITNESS, G_HABIT],   # 無器材-腿部：「快速提升心率…有氧負荷」
    4:  [G_LOSE, G_FITNESS, G_HABIT],   # 無器材-全身：同上
    5:  [G_LOSE, G_FITNESS],            # 代謝優化：「促進減脂與代謝效率」
    6:  [G_MUSCLE],                     # 肌力強化：「提升肌肉量與肌力」
    7:  [G_FITNESS],                    # 體能續航：「提升肌耐力…日常生活體能」
    8:  [G_MUSCLE],                     # 上半身-胸肩背：推力強化
    9:  [G_MUSCLE, G_FITNESS],          # 下半身-核心臀腿：強化肌群＋耐力
    10: [G_HABIT],                      # 功能性-肩頸
    11: [G_HABIT],                      # 功能性-腰背
    12: [G_HABIT, G_FITNESS],           # 功能性-足踝：「行走跑跳更穩」
    13: [G_HABIT],                      # 核心（學員）：基礎神經連結、預防腰痛
    14: [G_MUSCLE],                     # 核心（戰士）：大重量訓練的穩定性
    15: [G_MUSCLE, G_FITNESS],          # 核心（精銳）：全鏈剛性與爆發力傳導
    16: [G_FITNESS, G_HABIT],           # 橫向基礎與抗擾穩定：核心抗側屈、本體感覺
    17: [G_FITNESS],                    # 多維變向：動力鏈傳導效率、肌力平衡
    18: [G_FITNESS],                    # 動力鏈極限：輸出功率、高心率下的精準度
    19: [G_MUSCLE],                     # 槓鈴-胸部
    20: [G_MUSCLE, G_HABIT],            # 槓鈴-肩部：垂直剛性＋改善體態
    21: [G_MUSCLE],                     # 槓鈴-背部
    22: [G_LOSE, G_HABIT],              # 上肢動力鏈：「高效代謝…提升基礎代謝率」
    23: [G_LOSE, G_HABIT],              # 下肢動力鏈：「增加下肢代謝率」
    24: [G_MUSCLE, G_LOSE],             # 啞鈴-全身：基礎力量＋熱量消耗
    25: [G_FITNESS, G_MUSCLE],          # 壺鈴＆滑輪機：後側鏈、多平面移動
    26: [G_MUSCLE],                     # 固定式機械：「肌肥大效果」
}


def dart_list(xs) -> str:
    return '[' + ', '.join(dq(x) for x in xs) + ']'

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


def collapse(s: str) -> str:
    """換行壓成空白 —— 這些欄位是說明文字，不是排版。
    .g.dart 與 Firestore 兩個出口共用，確保雲端與後備的文字完全一致。"""
    return re.sub(r'\s+', ' ', (s or '')).strip()


def dq(s: str) -> str:
    """Dart 單引號字串。"""
    s = collapse(s)
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
    plans_struct = []  # [BE-12] 同一批資料的結構化形式，供上傳 Firestore
    for i, p in enumerate(plans):
        rows = by_plan.get(i, [])
        items = []
        items_struct = []
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
            items_struct.append({
                'exerciseId': eid, 'sets': sets, 'amount': reps,
                'unit': unit, 'restSeconds': int(r['組間休息秒']),
            })

        if not items:
            continue
        lvl = p['選取']
        rank = RANK.get(lvl)
        plans_struct.append({
            'id': f'csv{i:02d}',
            'name': collapse(p['計劃名稱']),
            'level': collapse(lvl),
            'requiredRank': rank,  # None 或 int
            'equipmentTier': tier(p['計劃名稱']),
            'suitableExperience': EXPERIENCE.get(lvl, []),
            'suitableGoals': GOALS.get(i, []),
            'duration': collapse(p['預估運動時長']),
            'intro': collapse(p['課表介紹']),
            'howTo': collapse(p['使用說明']),
            'load': collapse(p['負荷大小']),
            'effect': collapse(p['訓練效果(重點)']),
            'technique': collapse(p['技術特點']),
            'reference': collapse(p['來源/根據']),
            'items': items_struct,
        })
        out += [
            '  PlatformPlanSpec(',
            f"    id: 'csv{i:02d}',",
            f'    name: {dq(p["計劃名稱"])},',
            f'    level: {dq(lvl)},',
            f'    requiredRank: {rank if rank else "null"},',
            f'    equipmentTier: {dq(tier(p["計劃名稱"]))},',
            f'    suitableExperience: {dart_list(EXPERIENCE.get(lvl, []))},',
            f'    suitableGoals: {dart_list(GOALS.get(i, []))},',
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

    # [BE-12] 第二個出口：上傳 Firestore 的 plans 集合。
    # 預設只產生 .g.dart；帶 --upload 才寫雲端。
    if '--upload' in sys.argv:
        sys.path.insert(0, str(REPO / 'tools'))
        from firestore_upload import get_db, upsert
        docs = {p['id']: {k: v for k, v in p.items() if k != 'id'}
                for p in plans_struct}
        upsert(get_db(), 'plans', docs)

    if skipped:
        print(f'對不到動作 {len(skipped)} 個：')
        for s in skipped[:10]:
            print('   ✗', s)
        return 1
    print('所有動作都對得上動作庫 ✓')
    return 0


if __name__ == '__main__':
    sys.exit(main())
