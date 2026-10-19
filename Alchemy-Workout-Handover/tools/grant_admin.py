#!/usr/bin/env python3
"""互動版：給使用者管理員權限、調整權限組、或收回。

    python3 tools/grant_admin.py

照畫面提示依序輸入：①要做什麼 ②對方的 email ③權限組（有中文說明）。
**最後會顯示摘要，要你輸入 y 才會真的執行。** 想中途放棄：直接按 Ctrl+C。

底層沿用 `set_admin_claim.py`（憑證、列出管理員都在那裡），這支只負責「問答」與「安全檢查」：

- 授權／調整權限組時，**保留對方帳號上原有的其他 claim**，只動 `admin` 與 `adminScopes`。
  （舊腳本是整個覆蓋；目前只有管理員 claim，所以沒差，但這支不假設永遠如此。）
- 收回時只拿掉 `admin` 與 `adminScopes`，其他 claim 留著。
- **不允許收回最後一位管理員** —— 否則沒有人能再授權，要靠 Firebase 主控台以外的手段救。

## 憑證

跟 `set_admin_claim.py` 一樣：先 `source tools/.venv/bin/activate`，
再 `export GOOGLE_APPLICATION_CREDENTIALS=~/keys/你的金鑰.json`。
**金鑰絕不可進版控，也不要貼給任何人。**

## 設定完要重新登入

claim 是烘進登入憑證的 —— 對方要**重新登入**（或等約一小時）才會生效。
"""
import sys

import set_admin_claim as base

# 權限組：名稱要和 `lib/domain/admin.dart` 的 `AdminScope` 一致。順序＝畫面上的編號。
SCOPE_INFO = [
    ('contentReview', '內容審核',
     '審檢舉、申訴、教官申請、公開課表（待審佇列）'),
    ('productManage', '商品管理',
     '新增商品、修改商品資訊、下架商品'),
    ('platformConfig', '平台設定',
     '訓練計畫、動作、成就、獎勵、任務、各項門檻，以及管理員帳號相關設定'),
]
SCOPE_KEYS = [k for k, _, _ in SCOPE_INFO]
assert SCOPE_KEYS == base.SCOPES, '權限組名稱與 set_admin_claim.py 不一致'


# ---------------------------------------------------------------------------
# 純函式（不連網，有單元測試）
# ---------------------------------------------------------------------------

def parse_scopes(text):
    """把使用者輸入轉成權限組清單。回傳 (清單, 錯誤訊息)；成功時錯誤為 None。

    接受：編號（`1,2`、`1 2`）、英文名稱、中文名稱，或「全部」／`all`。
    **不接受空白** —— 授權時一定要明確選，不給預設值。
    """
    t = (text or '').strip()
    if not t:
        return None, '請至少選一個權限組（或輸入「全部」）。'
    if t.lower() in ('all', 'a') or t in ('全部', '全'):
        return list(SCOPE_KEYS), None

    names_zh = {zh: k for k, zh, _ in SCOPE_INFO}
    picked = []
    for raw in t.replace('，', ',').replace('、', ',').replace(' ', ',').split(','):
        tok = raw.strip()
        if not tok:
            continue
        if tok.isdigit():
            n = int(tok)
            if not 1 <= n <= len(SCOPE_KEYS):
                return None, f'沒有編號 {n}。可用編號：1 到 {len(SCOPE_KEYS)}。'
            key = SCOPE_KEYS[n - 1]
        elif tok in SCOPE_KEYS:
            key = tok
        elif tok in names_zh:
            key = names_zh[tok]
        else:
            return None, f'看不懂「{tok}」。請輸入編號、英文或中文名稱。'
        if key not in picked:
            picked.append(key)
    if not picked:
        return None, '請至少選一個權限組（或輸入「全部」）。'
    return picked, None


def claims_for_grant(existing, scopes):
    """授權後的 claim：保留原有的其他 claim，只動 admin／adminScopes。

    三個權限組全選時**不寫 adminScopes**，和舊腳本的「不給 --scopes ＝ 全開」一致
    （App 端沒有 adminScopes 就當三種全開）。
    """
    out = {k: v for k, v in (existing or {}).items()
           if k not in ('admin', 'adminScopes')}
    out['admin'] = True
    if sorted(scopes) != sorted(SCOPE_KEYS):
        out['adminScopes'] = list(scopes)
    return out


def claims_after_revoke(existing):
    """收回後的 claim：拿掉 admin／adminScopes，其他留著。沒有其他的就回 None。"""
    out = {k: v for k, v in (existing or {}).items()
           if k not in ('admin', 'adminScopes')}
    return out or None


def would_remove_last_admin(admin_uids, target_uid):
    """收回 target 之後會不會一個管理員都不剩。"""
    return target_uid in admin_uids and len(set(admin_uids) - {target_uid}) == 0


def describe_scopes(scopes):
    zh = {k: z for k, z, _ in SCOPE_INFO}
    return '、'.join(f'{zh[s]}（{s}）' for s in scopes)


# ---------------------------------------------------------------------------
# 互動
# ---------------------------------------------------------------------------

def _ask(prompt):
    try:
        return input(prompt).strip()
    except (EOFError, KeyboardInterrupt):
        print('\n已放棄，什麼都沒有改。')
        sys.exit(0)


def _admin_users(auth):
    found = []
    page = auth.list_users()
    while page:
        for u in page.users:
            if (u.custom_claims or {}).get('admin') is True:
                found.append(u)
        page = page.get_next_page()
    return found


def _current_scopes(user):
    return (user.custom_claims or {}).get('adminScopes') or list(SCOPE_KEYS)


def main():
    auth = base._auth()

    print('=== 管理員權限設定 ===\n')
    admins = _admin_users(auth)
    print(f'目前有 {len(admins)} 位管理員：')
    for u in admins:
        print(f'  · {u.email or u.uid}　{describe_scopes(_current_scopes(u))}')
    print()

    print('要做什麼？')
    print('  1  授權／調整權限組　　給某人管理員身分，或改他的權限組')
    print('  2  收回　　　　　　　　拿掉某人的管理員身分')
    print('  3  只看名單，不改　　　（上面已經列出了）')
    action = _ask('請輸入 1、2 或 3：')
    if action == '3':
        print('只看名單，沒有改任何東西。')
        return
    if action not in ('1', '2'):
        sys.exit('看不懂，請輸入 1、2 或 3。什麼都沒有改。')

    email = _ask('\n對方的 email（這個帳號必須先在 App 登入過一次）：')
    if not email or '@' not in email:
        sys.exit('email 看起來不對。什麼都沒有改。')
    try:
        user = auth.get_user_by_email(email)
    except Exception:
        sys.exit(f'找不到帳號 {email}。\n這個帳號必須先在 App 裡登入過一次，Firebase Auth 才有它。')

    is_admin_now = (user.custom_claims or {}).get('admin') is True
    print(f'\n找到帳號：{user.email or user.uid}（uid {user.uid}）')
    print('目前：' + (f'管理員，{describe_scopes(_current_scopes(user))}'
                      if is_admin_now else '不是管理員'))

    if action == '2':
        if not is_admin_now:
            print('他本來就不是管理員，不需要收回。什麼都沒有改。')
            return
        if would_remove_last_admin({u.uid for u in admins}, user.uid):
            sys.exit('這是最後一位管理員，不能收回 —— 收回之後就沒有人能再授權了。什麼都沒有改。')
        print('\n【摘要】收回管理員身分：')
        print(f'  帳號：{user.email or user.uid}')
        new_claims = claims_after_revoke(user.custom_claims)
    else:
        print('\n權限組（可複選，用編號，例如 1,2；全選輸入「全部」）：')
        for i, (key, zh, note) in enumerate(SCOPE_INFO, 1):
            print(f'  {i}  {zh}（{key}）— {note}')
        print('  ※「評分彙總」不屬於任何權限組，任何生效中的管理員都看得到。')
        while True:
            scopes, err = parse_scopes(_ask('請選擇：'))
            if err is None:
                break
            print('  ' + err)
        print('\n【摘要】' + ('調整權限組：' if is_admin_now else '授權為管理員：'))
        print(f'  帳號：{user.email or user.uid}')
        print(f'  權限：{describe_scopes(scopes)}')
        new_claims = claims_for_grant(user.custom_claims, scopes)

    if _ask('\n確定要執行嗎？輸入 y 才會執行，其他任何輸入都放棄：').lower() != 'y':
        print('已放棄，什麼都沒有改。')
        return

    auth.set_custom_user_claims(user.uid, new_claims)
    print('\n已完成。')
    print('⚠️ 對方要**重新登入**（或等約一小時）才會生效。')
    print('\n完成後的名單：')
    base.list_admins(auth)


if __name__ == '__main__':
    main()
