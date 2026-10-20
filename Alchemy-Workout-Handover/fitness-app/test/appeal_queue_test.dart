// 申訴要到得了管理員手上（`[BE-13]`，2026-09-25）。
//
// ## 在此之前：申訴送不出這台裝置
//
// `fileAppeal()` 只把案件加進本機的 `appeals` 清單 —— 而那個清單連
// 存檔都沒有。使用者寫了理由、按下送出、看到「已送出」，重新整理就沒了，
// **而且從頭到尾沒有任何管理員看得到**。
//
// 這比檢舉那次更徹底：檢舉至少寫進了 Firestore（只是沒人讀），
// 申訴連寫都沒寫。
//
// ## 申訴成立的後果也要傳到當事人
//
// `upholdAppeal()` 原本整段包在 `if (c.appellant == displayName)` 裡 ——
// 也就是**只撤銷得了自己的處罰**。撤銷處罰與退回違規次數都是改別人的
// 文件，而那兩份都是管理員可寫、當事人唯讀。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/appeal_data.dart';
import 'package:fitness_app/data/punishment_data.dart';
import 'package:fitness_app/data/violation_data.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakeAppeals implements AppealSource {
  final List<CloudAppeal> filed = [];
  List<CloudAppeal> cloud = [];
  int reads = 0;
  bool throwOnRead = false;
  final List<(String id, bool upheld, String handler)> verdicts = [];

  @override
  Future<void> file(CloudAppeal a) async => filed.add(a);

  @override
  Future<List<CloudAppeal>> queue({int limit = 100}) async {
    reads++;
    if (throwOnRead) throw StateError('permission-denied');
    return cloud;
  }

  @override
  Future<void> judge(String id,
          {required bool upheld, required String handlerName}) async =>
      verdicts.add((id, upheld, handlerName));

  @override
  Future<List<ApprovedBlock>> approvedBlockedTexts(String uid) async =>
      const [];
}

class _FakePunishments implements PunishmentSource {
  final List<String> revoked = [];
  @override
  Future<void> revoke(String uid) async => revoked.add(uid);
  @override
  Future<Punishment?> of(String uid) async => null;
  @override
  Future<void> issue(String uid, Punishment p, {required String name}) async {}
  @override
  Future<void> markAppealed(String uid, AppealState state) async {}
}

class _FakeViolations implements ViolationSource {
  final List<String> decremented = [];
  @override
  Future<int> decrement(String uid) async {
    decremented.add(uid);
    return 0;
  }

  @override
  Future<int> countOf(String uid) async => 0;
  @override
  Future<int> increment(String uid, {required String name}) async => 1;
}

/// 處罰時間要相對於「今天」。曾經寫死 2026-09-20，滿 30 天那天
/// `canAppealAt` 正確地拒絕申訴，兩條測試就無故轉紅。
DateTime _tenDaysAgo() => appNow().subtract(const Duration(days: 10));

typedef _Wired = ({
  AppState s,
  _FakeAppeals appeals,
  _FakePunishments punishments,
  _FakeViolations violations,
});

_Wired _admin() {
  final appeals = _FakeAppeals();
  final punishments = _FakePunishments();
  final violations = _FakeViolations();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..displayName = '阿健'
    ..appealSource = appeals
    ..punishmentSource = punishments
    ..violationSource = violations;
  s.applyAdminClaim(true);
  return (
    s: s,
    appeals: appeals,
    punishments: punishments,
    violations: violations
  );
}

CloudAppeal _appeal({
  String id = 'u-阿昶__1000',
  String uid = 'u-阿昶',
  String name = '阿昶',
  int daysAgo = 2,
}) =>
    CloudAppeal(
      id: id,
      appellantUid: uid,
      appellantName: name,
      target: AppealTarget.punishment,
      subject: '社群功能停權',
      reason: '我沒有違規',
      filedAt: DateTime(2026, 9, 25).subtract(Duration(days: daysAgo)),
      daysSinceIncident: 3,
    );

void main() {
  group('送出申訴要上雲', () {
    test('申訴寫進雲端，案件 ID 帶著處罰的時戳', () {
      final a = _admin();
      final issuedAt = _tenDaysAgo();
      a.s.punishment = Punishment(
        kind: PunishmentKind.communitySuspended,
        reason: '不實內容',
        evidence: '',
        issuedAt: issuedAt,
        violationCount: 3,
        nextConsequence: '',
      );

      a.s.fileAppeal('我沒有違規');

      expect(a.appeals.filed, hasLength(1));
      final f = a.appeals.filed.single;
      // 同一筆處罰只能申訴一次 —— 由主鍵保證，不靠客戶端先查再寫。
      expect(f.id, 'u-me__${issuedAt.millisecondsSinceEpoch}');
      expect(f.appellantUid, 'u-me');
      expect(f.reason, '我沒有違規');
      // 申訴對象取的是**處罰種類的名稱**（`punishmentKindNames`），
      // 不是級距標籤 —— 所以沒有天數。天數在 `punishments/{uid}` 的
      // `expiresAt` 上，管理員要看得從那邊拿。
      expect(f.subject, '社群功能停權');
    });

    test('同一筆處罰按兩次只送一筆', () {
      final a = _admin();
      a.s.punishment = Punishment(
        kind: PunishmentKind.warning,
        reason: '',
        evidence: '',
        issuedAt: _tenDaysAgo(),
        violationCount: 1,
        nextConsequence: '',
      );

      a.s.fileAppeal('第一次');
      a.s.fileAppeal('第二次');

      expect(a.appeals.filed, hasLength(1));
    });

    test('沒有處罰就不能申訴', () {
      final a = _admin();
      a.s.fileAppeal('我要申訴');
      expect(a.appeals.filed, isEmpty);
    });
  });

  group('管理員讀得到申訴佇列', () {
    test('一般使用者不會去讀', () async {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..appealSource = _FakeAppeals();
      final src = s.appealSource as _FakeAppeals;

      await s.loadAppealQueue();

      expect(src.reads, 0, reason: '不該白跑一趟被拒絕的查詢');
    });

    test('管理員讀得到', () async {
      final a = _admin();
      a.appeals.cloud = [_appeal()];

      await a.s.loadAppealQueue();

      expect(a.s.appeals, hasLength(1));
      expect(a.s.appeals.single.appellant, '阿昶');
      expect(a.s.appeals.single.reason, '我沒有違規');
      expect(a.s.appeals.single.appellantUid, 'u-阿昶');
    });

    test('等最久的排前面', () async {
      final a = _admin();
      a.appeals.cloud = [
        _appeal(id: '新的', daysAgo: 1),
        _appeal(id: '舊的', daysAgo: 9),
      ];

      await a.s.loadAppealQueue();
      expect(a.s.appeals.first.id, '舊的');
    });

    test('重讀不會長出第二筆', () async {
      final a = _admin();
      a.appeals.cloud = [_appeal()];
      await a.s.loadAppealQueue();
      await a.s.loadAppealQueue();
      expect(a.s.appeals, hasLength(1));
    });

    test('重讀不會把審視中的打回待審', () async {
      final a = _admin();
      a.appeals.cloud = [_appeal()];
      await a.s.loadAppealQueue();
      a.s.reviewAppeal(a.s.appeals.single);
      expect(a.s.appeals.single.state, CaseState.reviewing);

      await a.s.loadAppealQueue();

      expect(a.s.appeals.single.state, CaseState.reviewing);
    });

    test('讀不到就維持現狀，不清空', () async {
      final a = _admin();
      a.appeals.cloud = [_appeal()];
      await a.s.loadAppealQueue();

      a.appeals.throwOnRead = true;
      await a.s.loadAppealQueue();

      expect(a.s.appeals, hasLength(1));
    });
  });

  group('裁決的後果要傳到當事人', () {
    Future<AppealCase> pending(_Wired a) async {
      a.appeals.cloud = [_appeal()];
      await a.s.loadAppealQueue();
      final c = a.s.appeals.single;
      a.s.reviewAppeal(c);
      return c;
    }

    test('成立 → 撤銷他的處罰、退回一次違規', () async {
      final a = _admin();
      final c = await pending(a);

      a.s.upholdAppeal(c);

      // 在此之前這整段包在 `c.appellant == displayName` 裡 ——
      // 也就是只撤銷得了自己的處罰。
      expect(a.punishments.revoked, ['u-阿昶']);
      expect(a.violations.decremented, ['u-阿昶']);
    });

    test('成立 → 裁決寫回那筆申訴', () async {
      final a = _admin();
      final c = await pending(a);

      a.s.upholdAppeal(c);

      // 不寫回的話下次登入它還是 pending，同一筆會一直回來。
      expect(a.appeals.verdicts, [('u-阿昶__1000', true, '阿健')]);
    });

    test('駁回 → 不撤銷處罰，但裁決要寫回', () async {
      final a = _admin();
      final c = await pending(a);

      a.s.dismissAppeal(c);

      expect(a.punishments.revoked, isEmpty);
      expect(a.violations.decremented, isEmpty);
      expect(a.appeals.verdicts.single.$2, isFalse);
    });

    test('審視中才能裁決 —— 待審視狀態下按成立不生效', () async {
      final a = _admin();
      a.appeals.cloud = [_appeal()];
      await a.s.loadAppealQueue();

      a.s.upholdAppeal(a.s.appeals.single); // 沒先接手

      expect(a.appeals.verdicts, isEmpty);
      expect(a.punishments.revoked, isEmpty);
    });

    test('示範資料的假案件沒有 uid → 不會去撤銷任何人的處罰', () {
      final a = _admin();
      final c = AppealCase(
        id: 'AP-demo',
        appellant: '示範的人',
        target: AppealTarget.punishment,
        subject: '警告',
        reason: '',
        filedAt: DateTime(2026, 9, 24),
        daysSinceIncident: 1,
        state: CaseState.reviewing,
      );
      a.s.appeals.add(c);

      a.s.upholdAppeal(c);

      expect(a.punishments.revoked, isEmpty);
      expect(a.appeals.verdicts, isEmpty);
    });
  });
}
