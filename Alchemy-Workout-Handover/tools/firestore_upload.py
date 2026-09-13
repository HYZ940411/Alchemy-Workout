#!/usr/bin/env python3
"""平台資料上傳 Firestore 的共用工具（[BE-12]）。

用 service account（Admin SDK）寫入，**完全繞過 firestore.rules** ——
這是「管理端寫入」的種子上傳路徑（一般使用者只能讀）。

金鑰不進版控：由環境變數 GOOGLE_APPLICATION_CREDENTIALS 指定 service account
JSON 路徑；未設定則退回應用預設憑證（ADC，例如 `gcloud auth application-default
login` 或執行在 GCP 上的服務帳號）。

import_exercises.py、gen_platform_plans.py、upload_platform_data.py 共用本模組，
避免三處各自初始化 firebase-admin。
"""
import os
import sys

PROJECT_ID = 'alchemy-workout'


def get_db(project_id: str = PROJECT_ID):
    """取得 Firestore client。firebase-admin 缺席或憑證缺席時給可讀的錯誤。"""
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        sys.exit('需要 firebase-admin，請先 `pip install firebase-admin`。')

    if not firebase_admin._apps:
        cred_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        if cred_path and os.path.exists(cred_path):
            firebase_admin.initialize_app(
                credentials.Certificate(cred_path), {'projectId': project_id})
        else:
            # 退回應用預設憑證（ADC）。缺席時 firestore 呼叫會自己報錯。
            firebase_admin.initialize_app(options={'projectId': project_id})
    return firestore.client()


def upsert(db, collection: str, docs: dict) -> int:
    """把 docs（doc_id -> dict）整份覆寫進 collection。

    用 `set()`（upsert，整份覆寫）＋ WriteBatch 分批（Firestore 單批上限 500）。
    doc id 穩定，故可重跑；重跑只覆寫不重複。
    """
    col = db.collection(collection)
    batch = db.batch()
    pending = total = 0
    for doc_id, data in docs.items():
        batch.set(col.document(str(doc_id)), data)
        pending += 1
        total += 1
        if pending >= 450:
            batch.commit()
            batch = db.batch()
            pending = 0
    if pending:
        batch.commit()
    print(f'  {collection}: upsert {total} 筆')
    return total
