#!/usr/bin/env python3
"""唯讀：把正式環境的平台資料跟本地種子比一比（[BE-12]／[BE-18] 稽核用）。

**不寫任何東西。** 用途是回答「雲端到底有沒有那筆資料」——
2026-09-29 那一夜連問了三次（評分沒上去、後台改的東西沒上去、成就 ID 遷移），
每次都現寫一段，所以留成一支。

用法：
  cd fitness-app && dart run tools/export_platform_defs.dart build/platform_defs.json
  cd .. && GOOGLE_APPLICATION_CREDENTIALS=~/keys/<service-account>.json \
           fitness-app/tools/.venv/bin/python tools/check_platform_data.py

`tools/.venv` 需要 `firebase-admin`（2026-09-29 已裝）。
金鑰不進版控 —— 由環境變數指定，見 firestore_upload.py。
"""
import json
import pathlib
import sys

from firestore_upload import get_db

SEED = (pathlib.Path(__file__).resolve().parent.parent
        / 'fitness-app' / 'build' / 'platform_defs.json')

# 平台五集合之外也常要看的幾個。種子裡沒有，只印筆數。
OTHERS = ['experience_ratings', 'public_profiles', 'teams', 'follows']


def main():
    db = get_db()

    if SEED.exists():
        seed = json.loads(SEED.read_text(encoding='utf-8'))
        for coll, want in seed.items():
            cloud = {d.id: d.to_dict() for d in db.collection(coll).stream()}
            same = sum(1 for k, v in cloud.items() if want.get(k) == v)
            extra = [k for k in cloud if k not in want]
            missing = [k for k in want if k not in cloud]
            print(f'{coll}: 雲端 {len(cloud)} / 種子 {len(want)}'
                  f'　·　一致 {same}'
                  f'　·　雲端多 {len(extra)}　·　雲端少 {len(missing)}')
            for k in extra[:3]:
                print(f'    雲端多出來：{k}')
            for k in missing[:3]:
                print(f'    雲端沒有：{k}')
    else:
        print(f'（沒有 {SEED}，跳過與種子的比對）')

    print()
    for coll in OTHERS:
        n = db.collection(coll).count().get()[0][0].value
        print(f'{coll}: {int(n)} 筆')


if __name__ == '__main__':
    main()
