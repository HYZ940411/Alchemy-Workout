#!/usr/bin/env python3
"""把**單一帳號**某一維的能力值點數壓低到指定值（能力值刻度重新校準後的個案修正）。

背景（PROGRESS 3BG）：2026-10-19 基準值／映射係數重新校準，既有點數**不追溯**，
舊刻度下算出來偏高的點數會留著（例如 HYZ 的胸 920 → S）。使用者選「只修一個帳號」。
這支只做這一件事，不是批次重算。

**只往下壓，不往上抬**：目前點數 ≤ 目標值就什麼都不改。
**同時把該維的「待兌現實測值」清成 0** —— 舊刻度的待兌現值（可能是 999）留著，
下一場訓練會把點數又補回去。

預設是乾跑：只讀這一份文件（1 次讀取）、印出會改什麼、把原文件備份成 JSON，**不寫任何東西**。
帶 `--apply` 才真的寫；只改 `points.<維>` 與 `pending.<維>` 兩個欄位，其他欄位不動。

用法（在 Alchemy-Workout-Handover/ 底下）：
  GOOGLE_APPLICATION_CREDENTIALS=~/keys/<service-account>.json \\
      fitness-app/tools/.venv/bin/python tools/lower_ability_points.py \\
      --uid <使用者 uid> --dim chest --to 650            # 乾跑
  …同一行加 --apply                                       # 真的寫

**執行前，這個帳號所有裝置上的 App／網頁都要先關掉**：App 的記憶體裡還留著舊點數，
下一次自動存檔會把舊值寫回去，剛壓低的數字就白做了。寫完再重新打開。

維度：chest／back／legs／shoulders／arms／core。
文件：users/{uid}/ability/state（見 fitness-app/lib/data/store_firestore.dart）。
退回：備份檔在 fitness-app/build/ability_state_backup_<uid>_<時間>.json，把 points／pending 照抄回去即可。
"""
import argparse
import datetime
import json
import pathlib
import sys

DIMS = ('chest', 'back', 'legs', 'shoulders', 'arms', 'core')
BUILD = pathlib.Path(__file__).resolve().parent.parent / 'fitness-app' / 'build'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--uid', required=True)
    ap.add_argument('--dim', required=True, choices=DIMS)
    ap.add_argument('--to', required=True, type=int, help='目標點數（10–999）')
    ap.add_argument('--apply', action='store_true')
    a = ap.parse_args()
    if not 10 <= a.to <= 999:
        sys.exit('--to 須在 10 到 999 之間。')

    from firestore_upload import get_db
    db = get_db()
    ref = db.collection('users').document(a.uid).collection('ability').document('state')
    snap = ref.get()
    if not snap.exists:
        sys.exit(f'找不到 users/{a.uid}/ability/state —— uid 對嗎？')
    data = snap.to_dict()

    points = data.get('points') or {}
    pending = data.get('pending') or {}
    cur = points.get(a.dim)
    pend = pending.get(a.dim)
    print(f'帳號 {a.uid}　維度 {a.dim}')
    print(f'  目前點數：{cur}　待兌現實測值：{pend}　目標：{a.to}')
    print('  六維目前點數：' + '　'.join(f'{d} {points.get(d)}' for d in DIMS))

    BUILD.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = BUILD / f'ability_state_backup_{a.uid}_{stamp}.json'
    backup.write_text(json.dumps(data, ensure_ascii=False, indent=2, default=str),
                      encoding='utf-8')
    print(f'  已備份整份 ability/state → {backup}')

    if not isinstance(cur, (int, float)):
        sys.exit('這一維沒有點數，什麼都不改。')
    if cur <= a.to:
        print(f'\n目前點數 {cur} 已不高於目標 {a.to}（只往下壓、不往上抬），什麼都不改。')
        return

    changes = {f'points.{a.dim}': a.to, f'pending.{a.dim}': 0}
    print(f'\n會改：points.{a.dim} {cur} → {a.to}；pending.{a.dim} {pend} → 0')
    print('其他欄位（trainedDims、snapshots、decayTimers 與其他五維）不動。')
    if not a.apply:
        print('\n這是乾跑，沒有寫任何東西。要真的寫請加 --apply（先確認這個帳號的 App 都關掉了）。')
        return

    ref.update(changes)
    after = ref.get().to_dict()
    print(f'\n已寫入。讀回確認：points.{a.dim} ＝ {after["points"].get(a.dim)}　'
          f'pending.{a.dim} ＝ {after["pending"].get(a.dim)}')


if __name__ == '__main__':
    main()
