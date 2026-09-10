#!/usr/bin/env python3
"""從《健身計劃.csv》抽出每份課表的組數／次數／休息，產生一份待人工確認的表。

為什麼要有這支
----------------
CSV 裡的組數與次數寫在自由文字，而且有六七種寫法：
「重複 3 組」「執行 3 組」「各動作 10–12 次/組」「10 下*4 組」「40 秒訓練/20 秒休息」…
App 的 PlanExercise 需要的是每一組的目標次數與休息秒數 —— 兩者之間要有人接。

**這支只做「抽取」與「估算」，不做決定。** 每一列都標出處：
  明寫  = 原文就這樣寫，照抄
  估算  = 原文沒寫，由訓練時長回推（方法見 estimate_sets）
估算的那些一律要人看過才算數 —— 這是訓練處方，不是設定值。
"""

import csv
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
CSV = ROOT / '健身計劃.csv'

# --- 文字欄位裡的各種寫法 ------------------------------------------------

NUM = r'(\d+)(?:\s*[–\-~]\s*(\d+))?'          # 10 或 10–12

SETS = [
    re.compile(r'重複\s*' + NUM + r'\s*組'),
    re.compile(r'執行\s*' + NUM + r'\s*組'),
    re.compile(r'共\s*' + NUM + r'\s*組'),
    re.compile(NUM + r'\s*組\s*[×x*]'),        # 3 組 × 12 下
    re.compile(r'下\s*\*\s*' + NUM + r'\s*組'),  # 10 下 * 4 組
    # 循環式課表用「輪」或「循環」表達組數 —— 不補這幾條，
    # 「重複執行 3 個循環」會被當成沒寫，然後由時間預算估成 5 組。
    re.compile(r'重複執行\s*' + NUM + r'\s*個?循環'),
    re.compile(r'完成\s*' + NUM + r'\s*輪'),
    re.compile(r'共做\s*' + NUM + r'\s*輪'),
    re.compile(NUM + r'\s*(?:個)?循環'),
    re.compile(NUM + r'\s*輪'),
    # **沒有保底樣式。** 原本有一條 `NUM 組`，它會從不相干的敘述裡
    # 抓到數字；填一個錯的組數比留白更糟 —— 留白會被人看見，錯的不會。
]
REPS = [
    re.compile(r'每組\s*' + NUM + r'\s*[次下]'),
    re.compile(NUM + r'\s*[次下]\s*/\s*組'),
    re.compile(r'各動作\s*' + NUM + r'\s*[次下]'),
    re.compile(r'每個動作\s*' + NUM + r'\s*[次下]'),
    re.compile(r'組\s*[×x*]\s*' + NUM + r'\s*[次下]'),
    re.compile(NUM + r'\s*[次下]\s*[×x*]\s*\d+\s*組'),
    # 同上，不設保底。抽驗時它把「5 秒等長」讀成 5 下、
    # 把技術說明裡的「2 下」當成處方。
]
REST = [
    # **順序有意義**：組間 > 循環間 > 泛稱的休息。
    # 「動作間休息 30 秒、循環與循環之間休息 90 秒」這種寫法，
    # 若讓泛稱的樣式先命中，會把動作間的 30 秒當成組間休息。
    re.compile(r'組間休息\s*' + NUM + r'\s*(?:秒|s\b)'),
    re.compile(r'組間\s*' + NUM + r'\s*(?:秒|s\b)'),
    re.compile(r'循環與循環之間休息\s*' + NUM + r'\s*(?:秒|s\b)'),
    re.compile(r'輪與輪之間休息\s*' + NUM + r'\s*(?:秒|s\b)'),
    re.compile(r'休息\s*' + NUM + r'\s*(?:秒|s\b)'),
]

# 以分鐘寫的休息，要換算成秒。原本漏了這一步，
# 「休息 1.5 min」被讀成「休息 1 秒」。
REST_MIN = [
    re.compile(r'組間休息\s*' + NUM + r'\s*(?:分鐘|分|min)'),
    re.compile(r'休息\s*(\d+(?:\.\d+)?)()\s*(?:分鐘|分|min)'),
]
SECS = [
    re.compile(NUM + r'\s*秒\s*(?:訓練|工作)'),
    re.compile(r'（或\s*' + NUM + r'\s*秒）'),
    re.compile(NUM + r'\s*秒等長'),
]
# 總時長：取範圍的下界，保守
MINUTES = re.compile(r'(\d+)(?:\s*[–\-~]\s*\d+)?\s*(?:min|分鐘|分)')
WARMUP = re.compile(r'熱身\s*(\d+)')
COOLDOWN = re.compile(r'伸展\s*(\d+)')


def first(pats: list, text: str):
    """回傳 (值, 命中的原文)。範圍取下界 —— 訓練處方寧可保守。"""
    for p in pats:
        m = p.search(text)
        if m:
            return int(m.group(1)), m.group(0).strip()
    return None, None


# 循環／多區段課表的徵兆。這類課表**用 App 現在的模型表達不完整** ——
# PlanExercise 是「每個動作 N 組 × M 下」，而它們是
# 「6 個動作一輪、每個 40 秒、做 4 輪」，中間還夾著暖身與有氧區段。
# 標出來讓人決定要怎麼簡化，不要讓程式默默挑一組數字代表整份課表。
CIRCUIT = re.compile(r'循環|輪與輪|一輪|間歇|迴路|秒訓練|/\s*\d+\s*秒休息')


# 逐動作的處方：「3深蹲5 *12 下」「4登山者式6 *30 秒」。
# 這是全檔最精確的資料 —— 有它就不必用整份課表的單一組數去套每個動作。
PER_EX = re.compile(
    r'(\d)\s*([一-鿿]{2,8}?)\s*(\d+)\s*\*\s*(?:每側\s*)?'
    r'(\d+)(?:\s*[–\-]\s*\d+)?\s*(下|秒)')


def per_exercise(text, names):
    """回傳 {動作名: (組數, 次數或秒數, 是次還是秒)}。名字對不上就不採用 ——
    寧可退回整份課表的值，也不要把 A 動作的處方套到 B 動作頭上。"""
    out = {}
    for m in PER_EX.finditer(text):
        name = m.group(2)
        hit = [n for n in names if n == name or n.startswith(name)]
        if len(hit) == 1:
            out[hit[0]] = (int(m.group(3)), int(m.group(4)), m.group(5))
    return out


def plan_text(row: dict) -> str:
    return ' '.join(row[c] for c in
                    ['使用說明', '負荷大小', '預估運動時長', '技術特點', '課表介紹'])


def estimate_sets(total_min: int, n_ex: int, reps, 
                  secs, rest):
    """由時間預算回推組數。

    **方法寫在這裡，不埋在數字裡** ——
      1. 扣掉熱身與收操（原文有寫就用寫的，沒寫就各抓 5 分鐘）
      2. 剩下的時間平均分給每個動作
      3. 一組的耗時 ＝ 工作時間 ＋ 組間休息
         工作時間：原文有秒數就用；否則以每下 3 秒估（2 秒離心 ＋ 1 秒向心，
         這是課表文字裡反覆出現的節奏）
      4. 組數 ＝ 每個動作可用時間 ÷ 一組耗時，夾在 2–5 組之間

    夾在 2–5：低於 2 組不成訓練刺激，高於 5 組對這份資料的級別都太多
    （原文明寫的值全部落在 2–6 之間，這個範圍是從資料本身來的，不是我訂的）。
    """
    work = secs if secs else (reps or 10) * 3
    per_set = work + rest
    usable_sec = max(total_min * 60, 60) / max(n_ex, 1)
    return max(2, min(5, round(usable_sec / per_set)))


# 各級別的預設次數。**取自這份資料本身**，不是我憑空訂的 ——
# 把 27 份課表裡明寫的次數依級別分組取中位數，得到下面這幾個值。
# 用在原文真的沒寫次數的那 21 列。
# 值＝該級別所有明寫次數的中位數（我一開始憑印象填的兩個與資料不符：
# 精銳級寫成 8、功能重啟級寫成 8，實際是 5 與 6）。
LEVEL_REPS = {
    '學員級': 10,        # n=29，中位數 10，範圍 3–12
    '戰士級': 12,        # n=51，中位數 12，範圍 8–12
    '精銳級': 5,         # n=3， 全部都是 5（RPE 9–10，低次數高強度）
    '功能重啟級': 6,      # n=19，全部都是 6（控制與耐力，不追求力竭）
}


def fill_gaps(rows):
    """把「（待填）」補上級別預設值。

    **只補次數，不改任何原文明寫的值。** 補的那些一律標成「級別預設」，
    在 App 裡也看得出來 —— 這是訓練處方，讀的人有權知道哪個數字
    是課表作者寫的、哪個是推出來的。
    """
    for r in rows:
        if r['每組次數'] == '（待填）':
            r['每組次數'] = LEVEL_REPS.get(r['級別'], 10)
            r['次數來源'] = f"級別預設（{r['級別']}）"


def main() -> int:
    rows = list(csv.DictReader(open(CSV, encoding='utf-8-sig')))
    out = []
    for i, r in enumerate(rows):
        text = plan_text(r)
        exercises = [re.sub(r'\(https?://[^)]*\)', '', p).strip()
                     for p in r['健身動作'].split(',')]
        exercises = [e for e in exercises if e]

        sets, sets_src = first(SETS, text)
        reps, reps_src = first(REPS, text)
        rest, rest_src = first(REST, text)
        if rest is None:
            for p_ in REST_MIN:
                m = p_.search(text)
                if m:
                    rest = int(round(float(m.group(1)) * 60))
                    rest_src = m.group(0).strip()
                    break
        secs, secs_src = first(SECS, text)

        dur = MINUTES.search(r['預估運動時長'])
        total = int(dur.group(1)) if dur else 30
        wu = WARMUP.search(text)
        cd = COOLDOWN.search(text)
        total_main = total - (int(wu.group(1)) if wu else 5) \
                           - (int(cd.group(1)) if cd else 5)
        total_main = max(total_main, 5)

        if rest is None:
            rest, rest_src = 60, None          # 課表文字最常見的預設
        if sets is None:
            sets = estimate_sets(total_main, len(exercises), reps, secs, rest)
            sets_src = None

        per = per_exercise(r['預估運動時長'], exercises)

        for j, name in enumerate(exercises, 1):
            e_sets, e_reps, e_secs, e_src = sets, reps, secs, sets_src
            if name in per:
                n_set, n_val, unit = per[name]
                e_sets = n_set
                e_reps = n_val if unit == '下' else None
                e_secs = n_val if unit == '秒' else None
                e_src = f'逐動作明寫：{n_set} 組 × {n_val} {unit}'
            out.append({
                '課表編號': i,
                '級別': r['選取'],
                '課表名稱': r['計劃名稱'],
                '動作序': j,
                '動作名稱': name,
                '組數': e_sets,
                '組數來源': '明寫' if e_src else '估算',
                '組數依據': e_src or
                    f'時長{total}分−熱身收操→主訓練{total_main}分 ÷ {len(exercises)}動作',
                '每組次數': e_reps if e_reps else
                    ('' if e_secs else '（待填）'),
                '次數來源': ('明寫' if (reps_src or name in per) else '未寫'),
                '每組秒數': e_secs or '',
                '組間休息秒': rest,
                '休息來源': '明寫' if rest_src else '預設60',
                '原文依據': ((reps_src or '') + ' ' + (secs_src or '')).strip(),
                '備註': '循環／多區段課表 —— 單一組數次數無法完整表達，需人工決定如何簡化'
                        if CIRCUIT.search(text) else '',
            })

    # 補完剩下的空格。方法寫在 fill_gaps 裡，每一列照樣標得出來源。
    fill_gaps(out)

    dst = ROOT / '健身計劃-組數次數.csv'
    with open(dst, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)

    stated = sum(1 for o in out if o['組數來源'] == '明寫')
    print(f'產出 {len(out)} 列（27 份課表 × 各自的動作）→ {dst.name}')
    print(f'  組數：明寫 {stated} 列，估算 {len(out) - stated} 列')
    print(f'  次數：明寫 {sum(1 for o in out if o["次數來源"] == "明寫")} 列')
    print(f'  休息：明寫 {sum(1 for o in out if o["休息來源"] == "明寫")} 列')
    return 0


if __name__ == '__main__':
    sys.exit(main())
