#!/usr/bin/env python3
"""只上傳 Firestore 的 exercises（動作庫）集合。

`upload_platform_data.py` 一次上傳**五個**平台集合（動作庫、訓練計畫、成就定義、
每日任務池、平台設定），用打包資料整份覆寫 —— 後台有人改過其他四個集合的話會被蓋掉。
動作權重調整（2026-10-17）只動動作庫，所以另寫這支：**只碰 exercises，其他集合一律不動。**

預設是乾跑：不連 Firestore、不需要金鑰，只印出「會上傳什麼」。
帶 `--apply` 才真的寫（需要 service account，見 firestore_upload.py）。

用法：
  cd fitness-app && dart run tools/export_platform_defs.dart build/platform_defs.json
  cd .. && python3 tools/upload_exercises_only.py                  # 乾跑，先看
  GOOGLE_APPLICATION_CREDENTIALS=~/keys/<service-account>.json \\
      python3 tools/upload_exercises_only.py --apply               # 真的上傳

注意：
  · 用 set() 整份覆寫每一筆（與 upload_platform_data.py 相同）。後台對這 527 筆動作做過的
    編輯（係數、休息秒數…）會被打包資料蓋掉 —— 上傳前請先跑 check_platform_data.py 看差異。
  · 不會刪除雲端上「打包資料裡沒有」的動作（例如管理員在後台新增的）。
    它們的係數不會更新，需要的話在後台逐筆改。
"""
import json
import pathlib
import sys

DEFAULT = (pathlib.Path(__file__).resolve().parent.parent
           / 'fitness-app' / 'build' / 'platform_defs.json')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    apply = '--apply' in sys.argv
    path = pathlib.Path(args[0]) if args else DEFAULT
    if not path.exists():
        sys.exit(f'找不到 {path}；'
                 f'請先在 fitness-app/ 下 `dart run tools/export_platform_defs.dart build/platform_defs.json`。')
    data = json.loads(path.read_text(encoding='utf-8'))
    docs = data.get('exercises')
    if not docs:
        sys.exit(f'{path} 裡沒有 exercises。')

    cardio = sum(1 for d in docs.values() if d.get('type') == 'cardio')
    bodyweight = sum(1 for d in docs.values() if d.get('isBodyweight'))
    print(f'來源：{path}')
    print(f'exercises：{len(docs)} 筆（有氧 {cardio}、徒手型 {bodyweight}）')
    print('其他集合（plans、achievement_defs、daily_task_pool、platform_config…）：不碰。')
    for doc_id in ('bench', 'db_press', 'pullup'):
        d = docs.get(doc_id)
        if d:
            print(f'  樣本 {doc_id}：{d["name"]}　係數 {d["relativeIntensity"]}　徒手型 {d["isBodyweight"]}')

    if not apply:
        print('\n這是乾跑，沒有寫任何東西。要真的上傳請加 --apply。')
        return

    from firestore_upload import get_db, upsert
    n = upsert(get_db(), 'exercises', docs)
    print(f'共 upsert {n} 筆（只有 exercises）。')


if __name__ == '__main__':
    main()
