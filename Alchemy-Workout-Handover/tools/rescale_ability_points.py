#!/usr/bin/env python3
"""把**全部使用者**的能力值點數換算成新刻度（基準值 19.54、映射係數 14.33）。

背景（PROGRESS 3BG）：2026-10-19 能力值刻度重新校準（原 27.6／23.6），規格與平台設定本來寫
「係數調整不追溯既有點數」。使用者明確選了「全部重算，只往下換算」（推翻不追溯，同意 C 級以上的人掉等級）。

換算規則：  新 ＝ min(舊, round((舊 ÷ 23.6 ＋ 27.6 − 19.54) × 14.33))，不低於 10。
294 是不動點：294 以下**不動**（換算會把新手墊高，不要），294 以上往下換。
  舊 450→389　舊 650→510　舊 850→632　舊 920→674　舊 999→722

換算的欄位（users/{uid}/ability/state）：
  · points.<維>             ：照規則換算
  · pending.<維>            ：待兌現實測值也是點數尺度的絕對分數，照規則換算（0 維持 0）
  · snapshots.<N>.<維>      ：「N 天前」的快照，照規則換算（不換的話畫面上會一夜掉一大截）
  · decayTimers.<維>.cumulative：中斷累積退步量。退步下限由「中斷前點數 ＝ 現點數 ＋ cumulative」推導，
                              所以 新 cumulative ＝ max(0, 換算(舊點數＋舊cumulative) − 換算(舊點數))
  · abilityScale ＝ 2       ：已換算過的記號。**換算不是冪等的（再換一次會再降一次）**，有這個記號的使用者一律跳過
同步（public_profiles/{uid}，若有）：ability（六維）與 grade（綜合等級，六維平均後套預設六階門檻）。
不動：trainedDims、decayTimers 其他欄位、教官申請裡的能力值快照、已解鎖的成就（紀錄還在）。

預設是乾跑：讀全部使用者、印出「每人換算前後」的表、把原文件備份成 JSON，**不寫任何東西**。
帶 `--apply` 才寫；寫之前會要你輸入 yes 確認「所有人的 App 都關了」；寫完逐人讀回比對。

用法（在 Alchemy-Workout-Handover/ 底下）：
  GOOGLE_APPLICATION_CREDENTIALS=~/keys/<service-account>.json \\
      fitness-app/tools/.venv/bin/python tools/rescale_ability_points.py            # 乾跑
  …同一行加 --apply                                                                  # 真的寫

**執行前所有使用者的 App／網頁都要關掉**：App 記憶體裡還有舊點數，下一次自動存檔（有訓練、點數變了）
會把舊值寫回去。寫完之後請跑一次乾跑（或 --verify）確認沒有被寫回。
退回：備份檔 fitness-app/build/ability_rescale_backup_<時間>.json 有每人整份 ability/state 與 public_profiles 的 ability／grade。
"""
import argparse
import datetime
import json
import pathlib
import sys

DIMS = ('chest', 'back', 'legs', 'shoulders', 'arms', 'core')
OLD_B, OLD_M = 27.6, 23.6
NEW_B, NEW_M = 19.54, 14.33
MIN_POINTS, MAX_POINTS = 10, 999
SCALE_MARK = 2
#: 預設六階上界（E…S）。與 fitness-app/lib/domain/platform_config.dart 的 kDefaultTierUppers 一致。
TIER_UPPERS = (99, 249, 449, 649, 849, 999)
GRADES = ('E', 'D', 'C', 'B', 'A', 'S')
BUILD = pathlib.Path(__file__).resolve().parent.parent / 'fitness-app' / 'build'


def conv(p):
    """舊點數 → 新點數。只往下：不高於舊值，不低於 10。"""
    if not isinstance(p, (int, float)):
        return p
    p = int(p)
    new = round((p / OLD_M + OLD_B - NEW_B) * NEW_M)
    return max(MIN_POINTS, min(p, new))


def grade_of(points):
    for upper, g in zip(TIER_UPPERS, GRADES):
        if points <= upper:
            return g
    return GRADES[-1]


def overall_grade(pts):
    vals = [pts.get(d, MIN_POINTS) for d in DIMS]
    avg = round(sum(vals) / len(vals))
    return grade_of(avg)


def plan_for(ability, public):
    """回傳 (要寫的欄位 dict, 給人看的摘要)。ability 為整份 ability/state。"""
    points = ability.get('points') or {}
    new_points = {d: conv(v) for d, v in points.items()}
    out = {'points': new_points}

    pending = ability.get('pending')
    if isinstance(pending, dict):
        out['pending'] = {d: (conv(v) if v else v) for d, v in pending.items()}

    snaps = ability.get('snapshots')
    if isinstance(snaps, dict):
        out['snapshots'] = {
            k: {d: conv(v) for d, v in (m or {}).items()} if isinstance(m, dict) else m
            for k, m in snaps.items()}

    timers = ability.get('decayTimers')
    if isinstance(timers, dict):
        for d, t in timers.items():
            if not isinstance(t, dict) or not isinstance(t.get('cumulative'), (int, float)):
                continue
            cum = int(t['cumulative'])
            if cum <= 0 or d not in points:
                continue
            before = min(MAX_POINTS, int(points[d]) + cum)
            new_cum = max(0, conv(before) - new_points[d])
            out[f'decayTimers.{d}.cumulative'] = new_cum

    pub = {}
    if public is not None:
        if isinstance(public.get('ability'), dict):
            pub['ability'] = {d: conv(v) for d, v in public['ability'].items()}
        if 'grade' in public:
            pub['grade'] = overall_grade(new_points)
    return out, pub


def fmt_points(pts):
    return ' '.join(f'{d[:2]}{pts.get(d, "-")}' for d in DIMS)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--yes', action='store_true', help='略過「所有 App 都關了嗎」的互動確認（不建議）')
    ap.add_argument('--verify', metavar='LOG', help='拿一份換算紀錄（ability_rescale_log_*.json）對照雲端現值，找出被寫回舊值的人')
    a = ap.parse_args()

    from firestore_upload import get_db
    db = get_db()

    if a.verify:
        log = json.loads(pathlib.Path(a.verify).read_text(encoding='utf-8'))
        wrong = 0
        for row in log:
            ref = db.collection('users').document(row['uid']).collection('ability').document('state')
            cur = (ref.get().to_dict() or {}).get('points') or {}
            # 換算後使用者可能又練了、點數往上走了 —— 只抓「比換算後更高、且等於或接近舊值」的可疑情形
            back = [d for d, v in row['after'].items()
                    if row['before'].get(d) != v and cur.get(d) == row['before'].get(d)]
            if back:
                wrong += 1
                print(f'{row["uid"]}：{",".join(back)} 又變回換算前的值 —— 可能被開著的 App 寫回去了')
            else:
                print(f'{row["uid"]}：沒有被寫回舊值')
        print(f'\n可疑 {wrong} 位。')
        return

    users = []
    for u in db.collection('users').stream():
        ref = u.reference.collection('ability').document('state')
        snap = ref.get()
        if not snap.exists:
            continue
        pref = db.collection('public_profiles').document(u.id)
        psnap = pref.get()
        users.append((u.id, ref, snap.to_dict(), pref, psnap.to_dict() if psnap.exists else None))
    print(f'找到 {len(users)} 位有能力值資料的使用者。\n')

    BUILD.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = BUILD / f'ability_rescale_backup_{stamp}.json'
    backup.write_text(json.dumps(
        {uid: {'ability_state': ab, 'public_profile': pub} for uid, _r, ab, _p, pub in users},
        ensure_ascii=False, indent=2, default=str), encoding='utf-8')
    print(f'已備份全部人的 ability/state 與 public_profiles → {backup}\n')

    todo = []
    for uid, ref, ab, pref, pub in users:
        name = (pub or {}).get('displayName', '')
        if ab.get('abilityScale') == SCALE_MARK:
            print(f'{uid} {name}：已換算過（abilityScale＝{SCALE_MARK}），跳過。')
            continue
        changes, pub_changes = plan_for(ab, pub)
        before = ab.get('points') or {}
        after = changes['points']
        diff = [d for d in DIMS if before.get(d) != after.get(d)]
        print(f'{uid} {name}')
        print(f'   前：{fmt_points(before)}')
        print(f'   後：{fmt_points(after)}　（變動 {len(diff)} 維）')
        if pub_changes.get('grade'):
            print(f'   公開檔案綜合等級 → {pub_changes["grade"]}')
        todo.append((uid, ref, ab, pref, pub, changes, pub_changes))

    if not a.apply:
        print(f'\n這是乾跑，沒有寫任何東西（{len(todo)} 位待換算）。'
              f'要真的寫請加 --apply（先確認所有人的 App 都關了）。')
        return
    if not todo:
        print('\n沒有要換算的使用者。')
        return
    if not a.yes:
        ans = input(f'\n即將換算 {len(todo)} 位使用者的能力值。所有人的 App／網頁都關了嗎？輸入 yes 繼續：')
        if ans.strip() != 'yes':
            sys.exit('已取消，沒有寫任何東西。')

    log = []
    bad = 0
    for uid, ref, ab, pref, pub, changes, pub_changes in todo:
        ref.update({**changes, 'abilityScale': SCALE_MARK})
        if pub_changes:
            pref.update(pub_changes)
        after = ref.get().to_dict()
        ok = (after.get('abilityScale') == SCALE_MARK
              and all(after.get('points', {}).get(d) == v for d, v in changes['points'].items()))
        bad += 0 if ok else 1
        print(f'{uid}：已寫入，讀回{"一致" if ok else "「不一致」！"}')
        log.append({'uid': uid, 'before': ab.get('points'), 'after': changes['points'], 'ok': ok})
    logf = BUILD / f'ability_rescale_log_{stamp}.json'
    logf.write_text(json.dumps(log, ensure_ascii=False, indent=2, default=str), encoding='utf-8')
    print(f'\n完成：{len(todo)} 位，讀回不一致 {bad} 位。紀錄 → {logf}')
    print('請稍後再跑一次乾跑：應該全部顯示「已換算過」；若有人被寫回舊值（abilityScale 不見），'
          '代表他的 App 當時還開著。')


if __name__ == '__main__':
    main()
