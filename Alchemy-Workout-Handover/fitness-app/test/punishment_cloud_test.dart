// 處罰要罰得到別人（`[BE-13]`，2026-09-25）。
//
// 在此之前 `upholdReport()` 裡是這一行：
//
//     if (c.accused == displayName) _issuePunishment(c, after);
//
// 也就是**管理員只罰得到自己**。判別人的檢舉成立，對方那邊什麼都
// 沒發生 —— 連他自己重開 App 都不知道。而 `AppState.punishment`
// 連存檔都沒有，只活在記憶體裡。
//
// 存檔也不是正確的家：存檔是本人寫得動的，被罰的人自己就能清掉。
// 所以與累計違規次數同一個形狀：`punishments/{uid}`，
// **管理員可寫、當事人唯讀**。
//
// 唯一的例外是申訴 —— 那是當事人發起的，所以他改得動 `appealed` 與
// `appealState` 這兩個欄位，但**只有這兩個**（規則用 `affectedKeys`
// 限住，與貼文 `likeCount` 同一個手法）。少了那層，他就能把自己的
// 處罰種類改成「警告」。

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/clock.dart';

import 'package:fitness_app/data/punishment_data.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakePunishments implements PunishmentSource {
  final Map<String, Punishment> issued = {};
  final List<(String uid, AppealState state)> appeals = [];
  bool throwOnRead = false;

  @override
  Future<Punishment?> of(String uid) async {
    if (throwOnRead) throw StateError('permission-denied');
    return issued[uid];
  }

  @override
  Future<void> issue(String uid, Punishment p,
      {required String name}) async =>
      issued[uid] = p;

  @override
  Future<void> markAppealed(String uid, AppealState state) async =>
      appeals.add((uid, state));

  final List<String> revoked = [];
  @override
  Future<void> revoke(String uid) async {
    revoked.add(uid);
    issued.remove(uid);
  }
}

({AppState s, _FakePunishments src}) _admin() {
  final src = _FakePunishments();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..displayName = '阿健'
    ..punishmentSource = src;
  s.applyAdminClaim(true);
  return (s: s, src: src);
}

/// 判一個人成立。[violations] 為裁決後的累計次數。
ReportCase _upheld(AppState s, int violations,
    {String accused = '阿昶', String? accusedUid = 'u-阿昶'}) {
  final c = ReportCase(
    id: 'R-1',
    targetKey: 'post:p1',
    target: ReportTarget.post,
    origin: CaseOrigin.userReport,
    content: '違規內容',
    reason: '不實內容',
    reporterCount: 1,
    accused: accused,
    accusedUid: accusedUid,
    accusedViolations: violations - 1,
    enteredAt: DateTime(2026, 9, 24),
    state: CaseState.reviewing,
  );
  // **只加這一件案子，不要墊別的。** `AppState._violations` 是
  // `late final`，第一次被讀到時由 `reports` 建出來
  // （`{for (final c in reports) c.accused: c.accusedViolations}`）——
  // 同一個人的多筆案件，後面那筆會蓋掉前面那筆。初版在這裡墊了
  // 幾筆假案件想把次數推上去，結果被最後一筆蓋成 1，級距就變成警告。
  s.reports.add(c);
  return c;
}

void main() {
  group('罰得到別人', () {
    test('判別人成立 → 處罰寫到他的 uid 底下', () {
      final a = _admin();
      final c = _upheld(a.s, 1);

      a.s.upholdReport(c);

      // 在此之前這裡什麼都不會發生 —— 那一行是
      // `if (c.accused == displayName) _issuePunishment(...)`。
      expect(a.src.issued.keys, ['u-阿昶']);
      expect(a.src.issued['u-阿昶']!.reason, '不實內容');
      expect(a.src.issued['u-阿昶']!.evidence, '違規內容');
    });

    test('罰別人不會動到我自己的處罰狀態', () {
      final a = _admin();
      a.s.upholdReport(_upheld(a.s, 1));
      expect(a.s.punishment, isNull, reason: '被罰的是別人');
    });

    test('罰到自己時本機那一份也要動', () {
      final a = _admin();
      final c = _upheld(a.s, 1, accused: '阿健', accusedUid: 'u-me');

      a.s.upholdReport(c);

      expect(a.s.punishment, isNotNull);
      expect(a.src.issued.keys, ['u-me']);
    });

    test('級距依累計次數 —— 第一次是警告', () {
      final a = _admin();
      a.s.upholdReport(_upheld(a.s, 1));
      expect(a.src.issued['u-阿昶']!.kind, PunishmentKind.warning);
    });

    test('第三次起是社群功能停權，而且有到期時戳', () {
      final a = _admin();
      a.s.upholdReport(_upheld(a.s, 3));

      final p = a.src.issued['u-阿昶']!;
      expect(p.kind, PunishmentKind.communitySuspended);
      expect(p.expiresAt, isNotNull, reason: '限期處罰要寫到期時戳');
    });

    test('舊案件沒有 uid → 罰不了，理由同記點', () {
      final a = _admin();
      a.s.upholdReport(_upheld(a.s, 1, accusedUid: null));

      // 寫到暱稱底下的話，撞名就罰到別人頭上。
      expect(a.src.issued, isEmpty);
    });

    test('駁回不開處罰', () {
      final a = _admin();
      final c = _upheld(a.s, 1);
      a.s.dismissReport(c);
      expect(a.src.issued, isEmpty);
    });
  });

  group('自己的處罰要讀回來', () {
    test('登入時從雲端讀，不從存檔讀', () async {
      final a = _admin();
      a.src.issued['u-me'] = Punishment(
        kind: PunishmentKind.communitySuspended,
        reason: '不實內容',
        evidence: '',
        // **相對於現在算，不寫死日期。**
        // 原本是 `issuedAt: 2026-09-20`／`expiresAt: 2026-09-27` ——
        // 到了 2026-09-27 當天這條處罰就過期了，`communityBlockedReason`
        // 變成空值，測試無緣無故變紅。那天真的到了。
        issuedAt: appNow().subtract(const Duration(days: 7)),
        violationCount: 3,
        nextConsequence: '社群功能停權 30 天',
        expiresAt: appNow().add(const Duration(days: 23)),
      );

      await a.s.loadMyPunishment();

      // 存檔是本人寫得動的 —— 被罰的人自己就能清掉。
      expect(a.s.punishment?.kind, PunishmentKind.communitySuspended);
      expect(a.s.communityBlockedReason, isNotNull, reason: '真的要擋住功能');
    });

    test('沒有紀錄＝沒有受罰', () async {
      final a = _admin();
      await a.s.loadMyPunishment();
      expect(a.s.punishment, isNull);
    });

    test('讀不到就維持現狀 —— 不把人鎖在門外', () async {
      final a = _admin()..src.throwOnRead = true;
      await a.s.loadMyPunishment();
      expect(a.s.punishment, isNull);
    });
  });

  group('申訴寫回雲端', () {
    test('申訴後標記上去 —— 不寫的話重整就能再申訴一次', () {
      final a = _admin();
      a.s.punishment = Punishment(
        kind: PunishmentKind.warning,
        reason: '不實內容',
        evidence: '',
        issuedAt: a.s.now,
        violationCount: 1,
        nextConsequence: '社群功能停權 7 天',
      );

      a.s.fileAppeal('我沒有違規');

      expect(a.s.punishment!.appealed, isTrue);
      expect(a.src.appeals, [('u-me', AppealState.pending)]);
    });

    test('同一處罰限申訴一次', () {
      final a = _admin();
      a.s.punishment = Punishment(
        kind: PunishmentKind.warning,
        reason: '',
        evidence: '',
        issuedAt: a.s.now,
        violationCount: 1,
        nextConsequence: '',
      );

      a.s.fileAppeal('第一次');
      a.s.fileAppeal('第二次');

      expect(a.src.appeals, hasLength(1));
    });
  });
}
