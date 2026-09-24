#!/usr/bin/env python3
"""設定／撤銷平台管理員的 custom claim（`[BE-13]` 的前置）。

    python3 tools/set_admin_claim.py a94041198@gmail.com
    python3 tools/set_admin_claim.py a94041198@gmail.com --scopes contentReview,productManage
    python3 tools/set_admin_claim.py a94041198@gmail.com --revoke
    python3 tools/set_admin_claim.py --list

## 為什麼非得用這支腳本

`admin` claim **只能由 Admin SDK 設定**，用戶端改不了 —— 那正是它能
當安全判準的原因。`firestore.rules` 的 `isAdmin()` 看的是
`request.auth.token.admin`，App 的 `AppState.applyAdminClaim()` 看的也是它，
兩邊同源。

## 憑證

與 `firestore_upload.py` 同一套：環境變數 `GOOGLE_APPLICATION_CREDENTIALS`
指向 service account JSON，或退回應用預設憑證（ADC）。

    export GOOGLE_APPLICATION_CREDENTIALS=~/keys/alchemy-workout-adminsdk.json

**那把私鑰絕對不可進版控**（repo 根目錄的 `.gitignore` 已擋 `*-firebase-adminsdk-*.json`）。

## 設定完要重新登入

claim 是**烘進 ID token** 的，不是每次查一次。已登入的裝置要等 token
換新（約一小時）或重新登入才會生效。這支腳本設定完會提醒。
"""
import argparse
import sys

PROJECT_ID = 'alchemy-workout'

# 與 `lib/domain/admin.dart` 的 `AdminScope` 同名，順序不重要。
SCOPES = ['contentReview', 'productManage', 'platformConfig']


def _auth():
    try:
        import firebase_admin
        from firebase_admin import auth, credentials
    except ImportError:
        sys.exit('需要 firebase-admin，請先 `pip install firebase-admin`。')

    if not firebase_admin._apps:
        import os
        cred_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        if cred_path and os.path.exists(cred_path):
            firebase_admin.initialize_app(
                credentials.Certificate(cred_path), {'projectId': PROJECT_ID})
        else:
            try:
                firebase_admin.initialize_app(
                    credentials.ApplicationDefault(), {'projectId': PROJECT_ID})
            except Exception as e:
                sys.exit(
                    '找不到憑證。請設定 GOOGLE_APPLICATION_CREDENTIALS 指向\n'
                    'service account JSON（Firebase Console → 專案設定 →\n'
                    '服務帳戶 → 產生新的私密金鑰）。\n'
                    f'原始錯誤：{e}')
    return auth


def list_admins(auth):
    """列出目前帶著 admin claim 的帳號。"""
    found = []
    page = auth.list_users()
    while page:
        for u in page.users:
            if (u.custom_claims or {}).get('admin') is True:
                found.append(u)
        page = page.get_next_page()

    if not found:
        print('目前沒有任何帳號帶著 admin claim。')
        return
    print(f'目前有 {len(found)} 個管理員：')
    for u in found:
        scopes = (u.custom_claims or {}).get('adminScopes') or SCOPES
        print(f'  {u.email or u.uid}　權限：{"、".join(scopes)}')


def main():
    ap = argparse.ArgumentParser(description='設定平台管理員的 custom claim')
    ap.add_argument('email', nargs='?', help='要授權的帳號電子郵件')
    ap.add_argument('--scopes',
                    help=f'逗號分隔，可用：{",".join(SCOPES)}。不給＝三種全開')
    ap.add_argument('--revoke', action='store_true', help='撤銷管理員身分')
    ap.add_argument('--list', action='store_true', help='列出目前的管理員')
    args = ap.parse_args()

    auth = _auth()

    if args.list:
        list_admins(auth)
        return
    if not args.email:
        ap.error('要給電子郵件，或用 --list')

    try:
        user = auth.get_user_by_email(args.email)
    except Exception:
        sys.exit(
            f'找不到帳號 {args.email}。\n'
            '**這個帳號必須先在 App 裡登入過一次**，Firebase Auth 才有它。')

    if args.revoke:
        auth.set_custom_user_claims(user.uid, None)
        print(f'已撤銷 {args.email} 的管理員身分。')
    else:
        claims = {'admin': True}
        if args.scopes:
            picked = [s.strip() for s in args.scopes.split(',') if s.strip()]
            bad = [s for s in picked if s not in SCOPES]
            if bad:
                sys.exit(f'不認得的權限組：{"、".join(bad)}。可用：{"、".join(SCOPES)}')
            claims['adminScopes'] = picked
        auth.set_custom_user_claims(user.uid, claims)
        got = claims.get('adminScopes') or SCOPES
        print(f'已將 {args.email}（uid {user.uid}）設為管理員。')
        print(f'權限：{"、".join(got)}')

    print()
    print('⚠️ claim 是烘進 ID token 的 —— 已登入的裝置要**重新登入**')
    print('   （或等 token 換新，約一小時）才會生效。')


if __name__ == '__main__':
    main()
