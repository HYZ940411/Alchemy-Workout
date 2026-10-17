#!/usr/bin/env python3
"""唯讀：備份雲端的 exercises 集合，並比對「後台有沒有人改過」。

**不寫任何東西。** 在 `upload_exercises_only.py --apply` 之前跑：
  1. 把雲端 exercises 整份存成 JSON（格式與上傳腳本吃的種子相同，要退回時直接餵回去）。
  2. 跟「舊的打包資料」比 —— 不一樣的就是後台有人改過，上傳會把它蓋掉。
  3. 跟「新的打包資料」比 —— 看上傳之後會動幾筆。

用法（在 Alchemy-Workout-Handover/ 底下）：
  # 1. 準備新、舊兩份種子（舊的是上一個 commit 的打包資料，見 PROGRESS 3AO）
  cd fitness-app && dart run tools/export_platform_defs.dart build/platform_defs.json && cd ..
  #    舊種子的做法見該節或對話裡的步驟
  # 2. 備份＋比對
  GOOGLE_APPLICATION_CREDENTIALS=~/keys/<service-account>.json \\
      fitness-app/tools/.venv/bin/python tools/backup_exercises.py

要退回：
  GOOGLE_APPLICATION_CREDENTIALS=... fitness-app/tools/.venv/bin/python \\
      tools/upload_exercises_only.py fitness-app/build/exercises_backup_<時間>.json --apply
  （退回只會把備份裡有的動作寫回去；上傳後才新增的動作不會被刪。）
"""
import datetime
import json
import pathlib
import sys

from firestore_upload import get_db

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / 'fitness-app' / 'build'
NEW_SEED = BUILD / 'platform_defs.json'
OLD_SEED = BUILD / 'platform_defs_old.json'


def with_retry(fn, tries=6, base=2.0):
    """雲端回 429（Quota exceeded）時退避重試。

    2026-09-30 的紀錄：Admin SDK 讀取曾一律回 429、幾秒後重試就成功（見 PROGRESS），
    所以這不一定是每日額度用完。只重試 429，其他錯誤照常丟出。
    """
    import time
    for i in range(tries):
        try:
            return fn()
        except Exception as e:  # noqa: BLE001
            name = type(e).__name__
            transient = 'ResourceExhausted' in name or '429' in str(e)
            if not transient or i == tries - 1:
                raise
            wait = min(30.0, base * 2 ** i)
            print(f'  …雲端回 429（{name}），{wait:.0f} 秒後重試（{i + 1}/{tries - 1}）')
            time.sleep(wait)


def load_exercises(path):
    if not path.exists():
        sys.exit(f'找不到 {path}')
    data = json.loads(path.read_text(encoding='utf-8'))
    return data['exercises']


def field_diff(a, b):
    """兩份文件差在哪些欄位，回傳「欄位：甲 → 乙」。"""
    out = []
    for k in sorted(set(a) | set(b)):
        if a.get(k) != b.get(k):
            out.append(f'{k}：{a.get(k)!r} → {b.get(k)!r}')
    return out


def main():
    old = load_exercises(OLD_SEED)
    new = load_exercises(NEW_SEED)
    db = get_db()
    cloud = with_retry(
        lambda: {d.id: d.to_dict() for d in db.collection('exercises').stream()})

    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = BUILD / f'exercises_backup_{stamp}.json'
    BUILD.mkdir(parents=True, exist_ok=True)
    backup.write_text(
        json.dumps({'exercises': cloud}, ensure_ascii=False, indent=2, sort_keys=True),
        encoding='utf-8')
    print(f'已備份雲端 exercises：{len(cloud)} 筆 → {backup}')
    print()

    same_old = [k for k, v in cloud.items() if k in old and old[k] == v]
    edited = [k for k, v in cloud.items() if k in old and old[k] != v]
    cloud_only = [k for k in cloud if k not in old]
    missing = [k for k in old if k not in cloud]
    already_new = [k for k, v in cloud.items() if k in new and new[k] == v]

    print(f'雲端 {len(cloud)} 筆；舊打包資料 {len(old)} 筆；新打包資料 {len(new)} 筆')
    print(f'  · 與舊打包資料一致（上傳覆寫沒有損失）：{len(same_old)}')
    print(f'  · 與舊打包資料不同（**後台有人改過，上傳會被蓋掉**）：{len(edited)}')
    print(f'  · 雲端有、打包資料沒有（上傳不會動它，也不會更新它的係數）：{len(cloud_only)}')
    print(f'  · 打包資料有、雲端沒有（上傳會新增）：{len(missing)}')
    print(f'  · 已經等於新打包資料（上傳後不會變）：{len(already_new)}')

    if edited:
        print('\n被改過的動作（舊打包 → 雲端現值，前 15 筆）：')
        for k in edited[:15]:
            print(f'  {k}　{old[k].get("name")}')
            for line in field_diff(old[k], cloud[k]):
                print(f'      {line}')
        if len(edited) > 15:
            print(f'  …另有 {len(edited) - 15} 筆，看備份檔。')
    if cloud_only:
        print('\n雲端獨有的動作（前 10 筆）：')
        for k in cloud_only[:10]:
            print(f'  {k}　{cloud[k].get("name")}　係數 {cloud[k].get("relativeIntensity")}')

    print('\n判讀：')
    print('  · 「被改過」為 0 → 可以直接 --apply。')
    print('  · 「被改過」> 0 → 先看上面列的內容，確認那些改動是不是你要保留的；'
          '要保留的就別蓋，或上傳後再到後台補回。')


if __name__ == '__main__':
    main()
