// 處罰與申訴的雲端寫入不可以靜靜失敗（第二批第 6 項）。
//
// 管理員按「成立並處罰」，本機狀態馬上改了、畫面也說成功；但開立處罰、撤銷處罰、
// 退回違規次數、申訴與檢舉的裁決這幾筆寫入原本都是 `catchError((Object _) {})` ——
// 寫失敗的話，被罰的人那邊什麼都沒發生，管理員完全不知道。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/appeal_data.dart';
import 'package:fitness_app/data/punishment_data.dart';
import 'package:fitness_app/data/report_data.dart';
import 'package:fitness_app/data/violation_data.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

/// 每個寫入方法都炸。四種來源各一個類別：它們有同名但簽名不同的方法，
/// 不能合成一個。
class _BoomPunish implements PunishmentSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

class _BoomViolation implements ViolationSource {
  @override
  Future<int> increment(String uid, {required String name}) =>
      Future<int>.error(StateError('permission-denied'));
  @override
  Future<int> decrement(String uid) =>
      Future<int>.error(StateError('permission-denied'));
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

class _BoomAppeal implements AppealSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

class _BoomReport implements ReportSource {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<void>.error(StateError('permission-denied'));
}

AppState _admin() {
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..displayName = '阿健'
    ..punishmentSource = _BoomPunish()
    ..violationSource = _BoomViolation()
    ..appealSource = _BoomAppeal()
    ..reportSource = _BoomReport();
  s.applyAdminClaim(true);
  return s;
}

ReportCase _case(AppState s, {String? accusedUid = 'u-阿昶'}) {
  final c = ReportCase(
    id: 'R-1',
    targetKey: 'post:p1',
    target: ReportTarget.post,
    origin: CaseOrigin.userReport,
    content: '違規內容',
    reason: '不實內容',
    reporterCount: 1,
    accused: '阿昶',
    accusedUid: accusedUid,
    accusedViolations: 0,
    enteredAt: DateTime(2026, 9, 24),
    state: CaseState.reviewing,
  );
  s.reports.add(c);
  return c;
}

void main() {
  test('判檢舉成立，開立處罰寫失敗 → 看得見，而且畫面問得到', () async {
    final s = _admin();
    final c = _case(s);
    s.upholdReport(c);

    final r = await s.lastWrite('開立處罰');
    expect(r.ok, isFalse);
    expect(r.why, contains('permission-denied'));
    expect(s.cloudWriteReport['開立處罰'], startsWith('失敗'));
  });

  test('舊案件沒有被檢舉者的 uid → 處罰「沒送出」，不是靜靜略過', () async {
    final s = _admin();
    final c = _case(s, accusedUid: null);
    s.upholdReport(c);

    expect(s.cloudWriteReport['開立處罰'], startsWith('沒送出'));
    expect((await s.lastWrite('開立處罰')).ok, isFalse);
  });

  test('檢舉裁決寫失敗 → 看得見', () async {
    final s = _admin();
    final c = _case(s);
    s.debugSetReportDocIds(c.targetKey, ['d1']);
    s.dismissReport(c);
    await Future<void>.delayed(Duration.zero);

    expect(s.cloudWriteReport['檢舉裁決'], startsWith('失敗'));
  });

  test('申訴成立：撤銷處罰與退回違規次數寫失敗 → 各自看得見', () async {
    final s = _admin();
    final a = AppealCase(
      id: 'A-1',
      appellant: '阿昶',
      appellantUid: 'u-阿昶',
      target: AppealTarget.punishment,
      subject: '警告',
      reason: '誤判',
      filedAt: DateTime(2026, 9, 24),
      daysSinceIncident: 3,
      state: CaseState.reviewing,
    );
    s.appeals.add(a);
    s.upholdAppeal(a);
    await Future<void>.delayed(Duration.zero);

    expect(s.cloudWriteReport['撤銷處罰'], startsWith('失敗'));
    expect(s.cloudWriteReport['退回違規次數'], startsWith('失敗'));
    expect(s.cloudWriteReport['申訴裁決'], startsWith('失敗'));
  });

  test('使用者提出申訴，標記寫失敗 → 看得見（不然重新整理又能申訴一次）', () async {
    final s = _admin();
    s.punishment = Punishment(
      kind: PunishmentKind.warning,
      reason: '不實內容',
      evidence: '內容',
      issuedAt: s.now,
      violationCount: 1,
      nextConsequence: '警告',
    );
    s.fileAppeal('我覺得誤判');
    await Future<void>.delayed(Duration.zero);

    expect(s.cloudWriteReport['申訴標記'], startsWith('失敗'));
  });

  test('記一次違規寫失敗 → 看得見（次數決定處罰級距）', () async {
    final s = _admin();
    final c = _case(s);
    s.upholdReport(c);
    await Future<void>.delayed(Duration.zero);

    expect(s.cloudWriteReport['記一次違規'], startsWith('失敗'));
  });
}
