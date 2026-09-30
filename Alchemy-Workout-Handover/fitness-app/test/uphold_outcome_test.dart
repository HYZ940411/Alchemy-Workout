// 「檢舉成立」要說出實際發生了什麼（2026-09-28）。
//
// 使用者雙人實測 T8：判成立之後**貼文兩邊都還在**、被檢舉者也沒有收到
// 處罰，而案件從佇列裡消失了。
//
// 事後查出他當時走的是**開發者模式的示範後台**（假案件），
// 所以那一輪本身是假警報。但它暴露了一件真的事：
//
// **管理員按下「成立並處罰」之後，畫面只說「已處罰：警告」——
// 那是照著級距算出來的字，不是照著結果印的。**
// 下架了幾則、記點記到誰身上，一個字都沒說。
// 於是「真的成立了」與「什麼都沒發生」在畫面上長得一模一樣。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/report_data.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

AppState admin() => AppState()
  ..applyAdminClaim(true, scopes: [for (final s in AdminScope.values) s.name]);

CloudReport reportOn({
  required String targetKey,
  required ReportTarget target,
  required String accused,
  String? accusedUid,
  String content = '內容',
}) =>
    CloudReport(
      id: 'doc-$targetKey',
      targetKey: targetKey,
      target: target,
      origin: CaseOrigin.userReport,
      content: content,
      reason: '騷擾',
      accused: accused,
      accusedUid: accusedUid,
      reporterUid: 'u-me',
      reporterName: '我',
      at: DateTime.now(),
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('下架成功時說出下架了幾則', () {
    final s = admin();
    final post = s.posts.firstWhere((p) => !p.deleted);
    s.applyCloudReports([
      reportOn(
        targetKey: 'post:${post.id}',
        target: ReportTarget.post,
        accused: post.author,
        accusedUid: post.authorUid,
      ),
    ]);
    final c = s.reports.firstWhere((x) => x.targetKey == 'post:${post.id}');
    s.reviewReport(c);
    final out = s.upholdReport(c);

    expect(out.removed, 1);
    expect(out.violationsAfter, greaterThan(0));
    expect(out.summary, contains('已下架 1 則'));
    expect(s.posts.firstWhere((p) => p.id == post.id).deleted, isTrue);
  });

  // **這是要抓的那一種**：案件在，但那則內容不在這台裝置的清單裡。
  // 原本它與成功長得一模一樣。
  test('找不到那則內容時，說「沒有下架任何內容」', () {
    final s = admin();
    s.applyCloudReports([
      reportOn(
        targetKey: 'post:不存在的貼文',
        target: ReportTarget.post,
        accused: '某人',
        accusedUid: 'u-x',
      ),
    ]);
    final c = s.reports.firstWhere((x) => x.targetKey == 'post:不存在的貼文');
    s.reviewReport(c);
    final out = s.upholdReport(c);

    expect(out.removed, 0);
    expect(out.summary, contains('沒有下架任何內容'));
  });

  test('舊案件沒有對方的 uid 時，講出「記點寫不進他的紀錄」', () {
    final s = admin();
    final post = s.posts.firstWhere((p) => !p.deleted);
    s.applyCloudReports([
      reportOn(
        targetKey: 'post:${post.id}',
        target: ReportTarget.post,
        accused: post.author,
        // 2026-09-25 之前送出的案件沒有這個欄位。
      ),
    ]);
    final c = s.reports.firstWhere((x) => x.targetKey == 'post:${post.id}');
    s.reviewReport(c);
    final out = s.upholdReport(c);

    expect(out.recordedForAccused, isFalse);
    expect(out.summary, contains('記點寫不進'));
  });

  test('帳號類本來就不下架 —— 不要報成「找不到內容」', () {
    final s = admin();
    s.applyCloudReports([
      reportOn(
        targetKey: 'account:某人',
        target: ReportTarget.account,
        accused: '某人',
        accusedUid: 'u-y',
      ),
    ]);
    final c = s.reports.firstWhere((x) => x.targetKey == 'account:某人');
    s.reviewReport(c);
    final out = s.upholdReport(c);

    expect(out.removed, -1);
    expect(out.summary, contains('帳號類不下架內容'));
    expect(out.summary, isNot(contains('沒有下架任何內容')));
  });

  group('拒絕執行時也要說出理由', () {
    // **權限組不足**，不是「不是管理員」—— `canReview` 看的是
    // `contentReview` 這一組，不是 `adminClaim` 本身。
    test('沒有內容審核那一組權限', () {
      final s = AppState()
        ..applyAdminClaim(true, scopes: [AdminScope.productManage.name]);
      final c = s.reports.first;
      final out = s.upholdReport(c);
      expect(out.refusedWhy, isNotNull);
      expect(out.summary, contains('權限'));
    });

    test('案件不在審視中', () {
      final s = admin();
      final c = s.reports.firstWhere((x) => x.state == CaseState.pending);
      final out = s.upholdReport(c); // 沒先 reviewReport
      expect(out.refusedWhy, isNotNull);
      expect(out.summary, contains('審視中'));
    });
  });
}
