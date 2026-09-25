// 管理員看得到使用者送出的檢舉（2026-09-24）。
//
// ## 在此之前：寫進去了，沒有人讀
//
// `ReportSource` **只有 `file()`**，連一個讀的方法都沒有 ——
// 那個檔案的註解還寫著「讀取那一側屬於管理端，不在 App 裡」。
// 但管理端就在 App 裡（`screens/admin/`），只是身分那一段沒接。
//
// 所以使用者按的每一筆檢舉都確實寫進了 Firestore，而**沒有任何人讀它**。
// 而後台那一頁看起來一直都正常，因為它列的是編出來的假案件
// （2026-09-24 一併關掉了）。
//
// 這是「介面寫好了、線沒接」的第 N 次 —— 但這次連介面都缺一半，
// 所以 `data_source_wiring_test` 也抓不到：它驗的是「每支方法都有
// 呼叫端」，一支不存在的方法沒有方法可以沒有呼叫端。
//
// ## 併案為什麼在狀態層
//
// 多人檢舉同一標的要合併成一個案件。那需要看到所有人的那幾筆，
// 而檢舉佇列正是一般使用者不該讀得到的東西 —— 所以資料層逐筆回傳，
// 併案在拿得到全部資料的這一側做。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/report_data.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakeReports implements ReportSource {
  List<CloudReport> cloud = [];
  int reads = 0;
  bool throwOnRead = false;
  final List<(List<String> ids, bool upheld, String handler)> verdicts = [];

  @override
  Future<List<CloudReport>> queue({int limit = 100}) async {
    reads++;
    if (throwOnRead) throw StateError('permission-denied');
    return cloud;
  }

  @override
  Future<void> judge(List<String> ids,
          {required bool upheld, required String handlerName}) async =>
      verdicts.add((ids, upheld, handlerName));

  @override
  Future<void> file(CloudReport r) async {}
}

CloudReport _report({
  required String id,
  String targetKey = 'post:p1',
  String reporter = '小美',
  String reason = '不實內容',
  String accused = '阿昶',
  int daysAgo = 1,
}) =>
    CloudReport(
      id: id,
      targetKey: targetKey,
      target: ReportTarget.post,
      origin: CaseOrigin.userReport,
      content: '被檢舉的那段文字',
      reason: reason,
      accused: accused,
      reporterUid: 'u-$reporter',
      reporterName: reporter,
      at: DateTime(2026, 9, 24).subtract(Duration(days: daysAgo)),
    );

({AppState s, _FakeReports src}) _admin() {
  final src = _FakeReports();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..displayName = '阿健'
    ..reportSource = src;
  s.applyAdminClaim(true);
  return (s: s, src: src);
}

void main() {
  group('只有管理員讀得動', () {
    test('一般使用者不會去讀 —— 讀了也會被規則拒絕', () async {
      final src = _FakeReports();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..reportSource = src;

      await s.loadReportQueue();

      expect(src.reads, 0, reason: '不該白跑一趟被拒絕的查詢');
    });

    test('沒有內容審核權限的管理員也不讀', () async {
      final src = _FakeReports();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..reportSource = src;
      s.applyAdminClaim(true, scopes: ['productManage']);

      await s.loadReportQueue();

      expect(src.reads, 0);
    });

    test('有權限的管理員讀得到', () async {
      final a = _admin();
      a.src.cloud = [_report(id: 'r1')];

      await a.s.loadReportQueue();

      expect(a.src.reads, 1);
      expect(a.s.reports, hasLength(1));
      expect(a.s.reports.single.accused, '阿昶');
      expect(a.s.reports.single.content, '被檢舉的那段文字');
    });

    test('讀不到就維持現狀，不清空', () async {
      final a = _admin();
      a.src.cloud = [_report(id: 'r1')];
      await a.s.loadReportQueue();
      expect(a.s.reports, hasLength(1));

      a.src.throwOnRead = true;
      await a.s.loadReportQueue();

      // 空佇列與讀取失敗在畫面上長得一模一樣，
      // 而後者不該被畫成「沒有待審案件」。
      expect(a.s.reports, hasLength(1));
    });
  });

  group('併案：多人檢舉同一標的算一案', () {
    test('三個人檢舉同一則貼文 → 一個案件，三位檢舉者', () async {
      final a = _admin();
      a.src.cloud = [
        _report(id: 'r1', reporter: '小美', daysAgo: 3),
        _report(id: 'r2', reporter: '阿良', daysAgo: 2),
        _report(id: 'r3', reporter: '小柯', daysAgo: 1),
      ];

      await a.s.loadReportQueue();

      expect(a.s.reports, hasLength(1));
      final c = a.s.reports.single;
      expect(c.reporterCount, 3);
      expect([for (final r in c.reporters) r.name], ['小美', '阿良', '小柯']);
    });

    test('不同標的各自成案', () async {
      final a = _admin();
      a.src.cloud = [
        _report(id: 'r1', targetKey: 'post:p1'),
        _report(id: 'r2', targetKey: 'post:p2'),
      ];

      await a.s.loadReportQueue();
      expect(a.s.reports, hasLength(2));
    });

    test('內容與進入時間取最早那一筆', () async {
      final a = _admin();
      a.src.cloud = [
        _report(id: 'r2', reporter: '後來的', reason: '後來的事由', daysAgo: 1),
        _report(id: 'r1', reporter: '最早的', reason: '最早的事由', daysAgo: 5),
      ];

      await a.s.loadReportQueue();

      final c = a.s.reports.single;
      expect(c.reason, '最早的事由');
      expect(c.enteredAt, DateTime(2026, 9, 19));
    });

    test('等最久的排前面', () async {
      final a = _admin();
      a.src.cloud = [
        _report(id: 'r1', targetKey: 'post:新的', daysAgo: 1),
        _report(id: 'r2', targetKey: 'post:舊的', daysAgo: 9),
      ];

      await a.s.loadReportQueue();
      expect(a.s.reports.first.targetKey, 'post:舊的');
    });

    test('重讀不會長出第二個案件', () async {
      final a = _admin();
      a.src.cloud = [_report(id: 'r1')];
      await a.s.loadReportQueue();
      await a.s.loadReportQueue();
      expect(a.s.reports, hasLength(1));
    });

    test('重讀不會把審視中的案件打回待審 —— 管理員可能正開著它', () async {
      final a = _admin();
      a.src.cloud = [_report(id: 'r1')];
      await a.s.loadReportQueue();
      a.s.reviewReport(a.s.reports.single);
      expect(a.s.reports.single.state, CaseState.reviewing);

      await a.s.loadReportQueue();

      expect(a.s.reports.single.state, CaseState.reviewing);
      expect(a.s.reports.single.handlerName, '阿健');
    });
  });

  group('裁決寫回雲端', () {
    test('成立 → 那個標的的每一份文件都標成 upheld', () async {
      final a = _admin();
      a.src.cloud = [
        _report(id: 'r1', reporter: '小美'),
        _report(id: 'r2', reporter: '阿良'),
      ];
      await a.s.loadReportQueue();
      a.s.reviewReport(a.s.reports.single);

      a.s.upholdReport(a.s.reports.single);

      // 不寫回的話，下次登入那幾筆還是 pending —— 同一個案件會一直回來。
      expect(a.src.verdicts, hasLength(1));
      expect(a.src.verdicts.single.$1, ['r1', 'r2']);
      expect(a.src.verdicts.single.$2, isTrue);
      expect(a.src.verdicts.single.$3, '阿健');
    });

    test('駁回 → 標成 dismissed', () async {
      final a = _admin();
      a.src.cloud = [_report(id: 'r1')];
      await a.s.loadReportQueue();
      a.s.reviewReport(a.s.reports.single);

      a.s.dismissReport(a.s.reports.single);

      expect(a.src.verdicts.single.$2, isFalse);
    });

    test('沒接雲端的案件不會寫出空的裁決', () {
      final a = _admin();
      final c = ReportCase(
        id: 'local',
        targetKey: 'post:只在本機',
        target: ReportTarget.post,
        origin: CaseOrigin.userReport,
        content: '',
        reason: '',
        reporterCount: 1,
        accused: '阿昶',
        accusedViolations: 0,
        enteredAt: DateTime(2026, 9, 24),
      );
      a.s.reports.add(c);
      a.s.reviewReport(c);

      a.s.upholdReport(c);

      expect(a.src.verdicts, isEmpty);
    });
  });
}
