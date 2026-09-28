// 暱稱重構**階段二**：違規記點、教官案件、體驗評分改以 uid 判定
//（2026-09-28）。
//
// 階段一（0s）把「這是不是我的貼文」收束成一個定義。這一階段收的是
// 另外三處 —— 它們共同的形狀是「**拿暱稱當身分**」，而暱稱會改、會撞名。
//
// 三處各自的後果：
//   · 違規記點 → 記到別人頭上，而處罰級距依這個數字決定
//   · 教官案件 → **教官資格發給錯的人**
//   · 體驗評分 → 改名後找不到自己的舊評分，同一個對象可以再評一次
//
// 團隊成員與申訴人查過了，**本來就帶 uid**。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/novice_wrapup.dart';
import 'package:fitness_app/data/report_data.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

/// **要給 `myUid`** —— `_isMe` 在沒有 uid 可比時會退回比暱稱，
/// 那正是這一階段要取代的東西。沒設的話測到的是那條退路，不是新行為。
AppState admin() => AppState()
  ..myUid = 'u-我'
  ..applyAdminClaim(true, scopes: [for (final s in AdminScope.values) s.name]);

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('違規記點以 uid 為鍵', () {
    test('同名的兩個人各記各的', () {
      final s = admin();
      s.applyCloudReports([
        for (final uid in ['u-1', 'u-2'])
          CloudReportForTest.of(uid: uid, name: '同名的人', key: 'post:$uid'),
      ]);
      for (final key in ['post:u-1', 'post:u-1']) {
        final c = s.reports.firstWhere((x) => x.targetKey == key);
        if (c.state == CaseState.pending) s.reviewReport(c);
        s.upholdReport(c);
      }
      expect(s.violationsOf('u-1', name: '同名的人'), 1);
      expect(s.violationsOf('u-2', name: '同名的人'), 0,
          reason: '同名不同人，不該被連坐');
    });

    test('沒有 uid 的舊案件不記點 —— 不留一個寫不回去的數字', () {
      final s = admin();
      s.applyCloudReports([
        CloudReportForTest.of(uid: null, name: '舊案件的人', key: 'post:old'),
      ]);
      final c = s.reports.firstWhere((x) => x.targetKey == 'post:old');
      s.reviewReport(c);
      final out = s.upholdReport(c);
      expect(out.recordedForAccused, isFalse);
      expect(s.violationsOf(null, name: '舊案件的人'), 0);
    });
  });

  group('教官案件以 uid 判定', () {
    test('同名的別人被核准，我不會變成教官', () {
      final s = admin();
      s.instructorStage = InstructorStage.pendingReview;
      final other = InstructorCase(
        id: 'IC-x',
        applicant: s.displayName, // 撞名
        applicantUid: 'u-別人',
        aiScores: const {},
        weighted: 80,
        concerns: const [],
        answers: const [],
        enteredAt: DateTime.now(),
      );
      s.instructorCases.insert(0, other);

      s.decideInstructor(other, true);
      expect(s.isInstructor, isFalse, reason: '那是同名的另一個人');
      expect(s.instructorStage, InstructorStage.pendingReview);
    });

    test('真的是我的案件，核准之後我就是教官', () {
      final s = admin();
      s.instructorStage = InstructorStage.pendingReview;
      final mine = InstructorCase(
        id: 'IC-me',
        applicant: s.displayName,
        applicantUid: s.myUid,
        aiScores: const {},
        weighted: 80,
        concerns: const [],
        answers: const [],
        enteredAt: DateTime.now(),
      );
      s.instructorCases.insert(0, mine);

      s.decideInstructor(mine, true);
      expect(s.instructorStage, InstructorStage.approved);
      expect(s.isInstructor, isTrue);
    });
  });

  group('體驗評分以 uid 找回自己那一筆', () {
    test('改了暱稱還找得到，不會變成可以再評一次', () {
      final s = AppState()..myUid = 'u-我';
      expect(s.rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 4), isTrue);
      final before = s.experienceRatings.length;

      s.displayName = '改過的名字';

      // 找得到 → 這一次是「修改」，不是「再新增一筆」。
      expect(s.ratingFor(RatingTarget.noviceTask, kNoviceTaskId), isNotNull);
      s.rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 5);
      expect(s.experienceRatings.length, before, reason: '終身僅一筆');
      expect(s.ratingFor(RatingTarget.noviceTask, kNoviceTaskId)!.stars, 5);
    });
  });
}

/// 造一筆雲端檢舉。
extension CloudReportForTest on Object {
  static CloudReport of({
    required String? uid,
    required String name,
    required String key,
  }) =>
      CloudReport(
        id: 'doc-$key',
        targetKey: key,
        target: ReportTarget.post,
        origin: CaseOrigin.userReport,
        content: '內容',
        reason: '騷擾',
        accused: name,
        accusedUid: uid,
        reporterUid: 'u-me',
        reporterName: '我',
        at: DateTime.now(),
      );
}
