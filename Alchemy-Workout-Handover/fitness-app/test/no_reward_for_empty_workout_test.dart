// 沒做事的訓練不發獎勵（使用者裁決 2026-09-26）。
//
// 使用者實測後提出：「如果該訓練沒有完成任何一組或是訓練時間不足五分鐘，
// 不應該發送任何獎勵。」
//
// 在此之前，按下「開始訓練」再按「結束」就能換到經驗值與金幣 ——
// 那是「打開 App」的獎勵，不是訓練的獎勵。而且它是可重複的：
// 當日上限只管金幣，經驗值那一份每天發一次，等於每天白送。
//
// ## 為什麼兩個條件缺一不可
//
//   · 只看「有沒有完成一組」：隨手勾一組再結束也能領
//   · 只看「時長」：開著不動十分鐘也能領
//
// ## 不受影響的
//
// 能力值、累積訓練次數、連續天數**照舊** —— 那些不是獎勵，是紀錄。
// 一場短的訓練仍然發生過。訓練歷史那一側本來就有「一組都沒完成
// 不寫入」的判斷，與這裡是兩回事。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan get _plan => kAllPlans.firstWhere((p) => p.source != PlanSource.blank);

/// 開始一場訓練，完成 [done] 組，經過 [minutes] 分鐘後結算。
({AppState s, SettlementResult r}) _workout({
  required int done,
  required int minutes,
}) {
  final s = AppState(demo: false)..startWorkout(_plan);
  for (var i = 0; i < done; i++) {
    s.completeCurrentSet();
  }
  s.backdateSession(Duration(minutes: minutes));
  return (s: s, r: s.finishWorkout(EndKind.completed));
}

void main() {
  group('一組都沒完成', () {
    test('不發經驗值與金幣', () {
      final w = _workout(done: 0, minutes: 30);
      expect(w.r.rewards.exp, 0);
      expect(w.r.rewards.coins, 0);
    });

    test('不計排行榜分數', () {
      expect(_workout(done: 0, minutes: 30).r.rewards.leaderboardScore, isNull);
    });

    test('完成度算 0 —— 它會被寫進當日最高完成度', () {
      expect(_workout(done: 0, minutes: 30).r.rewards.completion, 0);
    });

    test('不推進「完成訓練」的每日任務', () {
      final s = _workout(done: 0, minutes: 30).s;
      final t = s.dailyTasks.where((t) => t.sourceEvent == '使用者已完成訓練');
      for (final task in t) {
        expect(task.progress, 0, reason: task.name);
      }
    });
  });

  group('不到 5 分鐘', () {
    test('做了幾組也不發 —— 開著不動十分鐘也能領是另一個洞', () {
      final w = _workout(done: 3, minutes: 2);
      expect(w.r.rewards.exp, 0);
      expect(w.r.rewards.coins, 0);
    });

    test('剛好 5 分鐘就發', () {
      final w = _workout(done: 3, minutes: 5);
      expect(w.r.rewards.exp, greaterThan(0));
    });

    test('門檻是 5 分鐘', () {
      expect(kMinRewardedWorkout, const Duration(minutes: 5));
    });
  });

  group('兩個條件都滿足才發', () {
    test('做了組、也夠久 → 照常發', () {
      final w = _workout(done: 3, minutes: 30);
      expect(w.r.rewards.exp, greaterThan(0));
      expect(w.r.rewards.coins, greaterThan(0));
    });
  });

  group('不受影響的東西 —— 做了組但太短，仍然是一次訓練', () {
    test('累積訓練次數照算', () {
      // 判準是「有沒有完成組」，不是「夠不夠 5 分鐘」。
      // 練了兩分鐘但做了三組，他確實練了 —— 只是不發獎勵。
      final before = AppState(demo: false).totalWorkouts;
      expect(_workout(done: 3, minutes: 2).s.totalWorkouts, before + 1);
    });

    test('能力值照算', () {
      final w = _workout(done: 3, minutes: 2);
      expect(w.r.gains, isNotEmpty, reason: '練了就是練了，只是不發獎勵');
    });

    test('照樣寫進訓練歷史', () {
      expect(_workout(done: 3, minutes: 2).s.history, isNotEmpty);
    });
  });

  // 2026-09-26 使用者裁決（第二次，推翻前一次）：
  // 「一組都沒完成的訓練不僅不要寫進訓練清單，也不要在任何地方被記錄下來」。
  //
  // 前一次的裁決只講獎勵，所以這裡原本有一條
  // 「累積訓練次數照算 —— 那是紀錄，不是獎勵」。後來使用者回報
  // 「教官申請的累計訓練次數跟訓練清單的不一樣」—— 正是那條造成的：
  // 次數 +1 而歷史沒有那一筆，每開關一次就再拉開一格。
  //
  // 完整的不變條件見 `test/workout_count_invariant_test.dart`。
  group('一組都沒完成 —— 任何地方都不留紀錄', () {
    test('累積訓練次數不加', () {
      final before = AppState(demo: false).totalWorkouts;
      expect(_workout(done: 0, minutes: 30).s.totalWorkouts, before);
    });

    test('不寫進訓練歷史', () {
      expect(_workout(done: 0, minutes: 30).s.history, isEmpty);
    });

    test('累積訓練天數與連續訓練天數都不動', () {
      final base = AppState(demo: false);
      final s = _workout(done: 0, minutes: 30).s;
      expect(s.totalWorkoutDays, base.totalWorkoutDays);
      expect(s.trainingStreakDays, base.trainingStreakDays);
    });
  });
}
