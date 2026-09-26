// 訓練品質評分的時點：**申請之後，不是打開頁面就算**（2026-09-26）。
//
// ## 這一條改過兩次，第二次是被使用者糾正的
//
// 使用者先回報「已訓練 7 次，三維分數仍全是 0」。我當時改成「讀到就
// 算一份」—— 分數確實不再是 0 了，但**那違反規格的時序**，使用者當場
// 指出來：「評分應該要等階級跟訓練次數達標之後，按下申請再分析」。
//
// 查 `教官申請流程.md`，他是對的：
//
//   使用者已申請教官權限
//     → 系統「初審教官資格」（階級 ≥ 20 且累積訓練次數 ≥ 50）
//       → 系統「分析歷史訓練品質」→ AI 已產出訓練品質評分
//
// 而且「本 Event 的請求識別碼 ＝ 使用者 ID ＋ **教官申請 ID**，
// 同一筆申請只評分一次」、「評分結果寫入教官申請 Aggregate，永久保存」。
//
// **評分屬於一筆申請，不屬於這個人。** 沒有申請就沒有評分 ——
// 不是「評了但還沒看」，也不是 0 分。
//
// ## 所以原本的問題是什麼
//
// 不是「沒算」，是**把「沒有分數」畫成了 0** —— 而 0 看起來像一個
// 很低的分數，使用者會以為自己被評了 0 分。
// 修法是把它畫成「尚未評分」。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan get _plan => kPlans.firstWhere((p) => p.source != PlanSource.blank);

/// 練 [n] 場，每場完成一組、時長足夠。
AppState _trained(int n) {
  final s = AppState(demo: false);
  for (var i = 0; i < n; i++) {
    s.startWorkout(_plan);
    s.completeCurrentSet();
    s.backdateSession(const Duration(minutes: 30));
    s.finishWorkout(EndKind.completed);
  }
  return s;
}

void main() {
  group('還沒申請就沒有評分', () {
    test('練了很多次也一樣 —— 評分屬於一筆申請，不屬於這個人', () {
      final s = _trained(7);
      expect(s.quality, isNull);
      expect(s.qualityScored, isFalse);
    });

    test('讀分數不會偷偷觸發評分', () {
      final s = _trained(7);
      s.qualityScore; // 只是讀它
      expect(s.quality, isNull, reason: '讀一下不該產生一筆評分');
    });

    test('畫面據此顯示「尚未評分」，而不是 0', () {
      // 這是整條的重點：0 看起來像「被評了 0 分」。
      final s = _trained(7);
      expect(s.qualityScored, isFalse);
      expect(s.qualityScore, 0, reason: '底層是 0，但畫面不該直接畫它');
    });
  });

  group('申請之後才評分', () {
    test('重新申請會評分', () {
      final s = _trained(7)
        ..instructorStage = InstructorStage.rejected
        ..lastExamAt = null;

      expect(s.reapplyInstructor(), isTrue);

      expect(s.qualityScored, isTrue);
      expect(s.qualityScore, greaterThan(0));
    });

    test('評分依這個人自己的訓練紀錄', () {
      final busy = _trained(7)
        ..instructorStage = InstructorStage.rejected
        ..lastExamAt = null;
      final idle = AppState(demo: false)
        ..instructorStage = InstructorStage.rejected
        ..lastExamAt = null;
      busy.reapplyInstructor();
      idle.reapplyInstructor();

      expect(busy.qualityScore, greaterThan(idle.qualityScore));
    });

    test('沒有訓練紀錄 → 0 分並說明「無從評分」', () {
      final s = AppState(demo: false)
        ..instructorStage = InstructorStage.rejected
        ..lastExamAt = null;
      s.reapplyInstructor();

      expect(s.qualityScored, isTrue, reason: '評過了，只是分數是 0');
      expect(s.quality!.concerns.join(), contains('沒有任何訓練紀錄'));
    });
  });

  group('訓練紀錄變了，評分就過期', () {
    test('結算時讓它失效 —— 下次申請重新評，不沿用舊的', () {
      final s = _trained(3)
        ..instructorStage = InstructorStage.rejected
        ..lastExamAt = null;
      s.reapplyInstructor();
      expect(s.quality, isNotNull);

      s.startWorkout(_plan);
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 30));
      s.finishWorkout(EndKind.completed);

      // 規格：任何重試皆產生新的一筆教官申請，並**重跑** AI 品質評分。
      expect(s.quality, isNull);
    });

    test('一組都沒完成的訓練不進歷史，也就不影響評分', () {
      final s = _trained(3)
        ..instructorStage = InstructorStage.rejected
        ..lastExamAt = null;
      s.reapplyInstructor();
      final before = s.qualityScore;

      s.startWorkout(_plan);
      s.backdateSession(const Duration(minutes: 30));
      s.finishWorkout(EndKind.completed); // 沒完成任何一組

      s.instructorStage = InstructorStage.rejected;
      s.lastExamAt = null;
      s.reapplyInstructor();

      expect(s.qualityScore, before);
    });
  });

  _planLastTrained();
}

/// 課表的「上次訓練／上次完成度」（2026-09-26）。
///
/// 原本兩個都寫死在 `kPlans` 裡 —— 一個從來沒練過「拉日」的人會看到
/// 「上次訓練 5 天前　完成度 70%」。移除之後日期改由訓練歷史推導，
/// 但**完成度推導不出來**：訓練歷史只存了做了哪幾組，沒存「計畫有幾組」。
/// 使用者回報「上次完成度都是 —」。
///
/// 修法是在結算時把完成度一起存進訓練歷史。
/// **2026-09-26 之前的場次沒有這個數字，仍然是空值** —— 那是誠實的。
void _planLastTrained() {
  group('上次訓練與完成度', () {
    test('沒練過就兩個都是空的 —— 不是假資料', () {
      final s = AppState(demo: false);
      expect(s.lastTrainedOf(_plan), isNull);
      expect(s.lastCompletionOf(_plan), isNull);
    });

    test('練過之後日期讀得到', () {
      expect(_trained(1).lastTrainedOf(_plan), isNotNull);
    });

    test('完成度也讀得到 —— 不再是「—」', () {
      final c = _trained(1).lastCompletionOf(_plan);
      expect(c, isNotNull);
      expect(c, inInclusiveRange(0, 1));
    });

    test('只做一組的完成度低於全部做完', () {
      final s = _trained(1);
      expect(s.lastCompletionOf(_plan), lessThan(1.0));
    });

    test('取最近的那一場，不是最早的', () {
      final s = _trained(1);
      final first = s.lastCompletionOf(_plan);

      // 再練一場，這次多做兩組。
      s.startWorkout(_plan);
      s.completeCurrentSet();
      s.completeCurrentSet();
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 30));
      s.finishWorkout(EndKind.completed);

      expect(s.lastCompletionOf(_plan), greaterThan(first!));
    });

    test('一組都沒完成的場次不進歷史，所以不會蓋掉上一次', () {
      final s = _trained(1);
      final before = s.lastCompletionOf(_plan);

      s.startWorkout(_plan);
      s.backdateSession(const Duration(minutes: 30));
      s.finishWorkout(EndKind.completed);

      expect(s.lastCompletionOf(_plan), before);
    });
  });
}
