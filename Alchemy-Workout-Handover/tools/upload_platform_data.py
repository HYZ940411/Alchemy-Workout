#!/usr/bin/env python3
"""上傳 Dart 端匯出的平台資料種子 JSON 到 Firestore（[BE-12]）。

搭配 fitness-app/tools/export_platform_defs.dart，上傳全部五個平台集合
（動作庫、訓練計畫、成就定義、每日任務池、平台設定）。種子取自打包在本地的
正典資料（BundledPlatformData），保證雲端與 App 打包內容一致 —— 理由見該 .dart
檔的註解（import_exercises.py 重跑會因 OVERRIDES 失配而產出漂移的動作 ID）。

用法：
  cd fitness-app && dart run tools/export_platform_defs.dart build/platform_defs.json
  cd .. && python3 tools/upload_platform_data.py fitness-app/build/platform_defs.json

service account 由環境變數 GOOGLE_APPLICATION_CREDENTIALS 指定（見 firestore_upload.py）。
"""
import json
import pathlib
import sys

from firestore_upload import get_db, upsert

DEFAULT = (pathlib.Path(__file__).resolve().parent.parent
           / 'fitness-app' / 'build' / 'platform_defs.json')


def main():
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    if not path.exists():
        sys.exit(f'找不到 {path}；'
                 f'請先在 fitness-app/ 下 `dart run tools/export_platform_defs.dart`。')
    data = json.loads(path.read_text(encoding='utf-8'))
    db = get_db()
    total = 0
    for collection, docs in data.items():
        total += upsert(db, collection, docs)
    print(f'共 upsert {total} 筆。')


if __name__ == '__main__':
    main()
