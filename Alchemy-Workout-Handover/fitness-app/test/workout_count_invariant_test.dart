import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

/// **累積訓練次數與訓練歷史的筆數，必須一起動。**
///
/// 使用者回報「教官申請的累計訓練次數跟訓練清單的不一樣」。
/// 原因是兩者各自寫了一份條件：次數無條件 +1，歷史則要求「有完成的組」。
/// 於是每一次「按下開始、放著、按結束」都讓落差再拉開一格 ——
/// 而累積訓練次數同時是教官初審門檻（≥50 次），開關五十次就過得了。
///
/// 2026-09-26 使用者裁決：**一組都沒完成的訓練不在任何地方被記錄**。
/// 現在兩者讀同一個旗標，這一份測試釘住「它們不會再漂開」。
void main() {
  final plan = kPlans.firstWhere((p) => p.id == 'p_push');

  /// 練一場，回傳（次數變化，歷史筆數變化）。
  (int, int) run(AppState s,
      {required int sets, Duration elapsed = const Duration(minutes: 10)}) {
    final w0 = s.totalWorkouts;
    final h0 = s.history.length;
    s.startWorkout(plan);
    for (var i = 0; i < sets; i++) {
      s.completeCurrentSet();
    }
    if (elapsed > Duration.zero) s.backdateSession(elapsed);
    s.finishWorkout(EndKind.completed);
    return (s.totalWorkouts - w0, s.history.length - h0);
  }

  group('不變條件：次數與歷史筆數同步', () {
    test('一組都沒完成 —— 兩邊都不動', () {
      final s = AppState();
      expect(run(s, sets: 0), (0, 0));
    });

    test('做了一組 —— 兩邊都 +1', () {
      final s = AppState();
      expect(run(s, sets: 1), (1, 1));
    });

    test('不到 5 分鐘但做了組 —— 仍然算一次訓練', () {
      // 發獎勵比「算一次訓練」嚴，但他確實練了。
      final s = AppState();
      expect(run(s, sets: 2, elapsed: Duration.zero), (1, 1));
    });

    test('三種終止方式在有完成組的前提下都計入', () {
      for (final kind in EndKind.values) {
        final s = AppState();
        final w0 = s.totalWorkouts;
        final h0 = s.history.length;
        s.startWorkout(plan);
        s.completeCurrentSet();
        s.backdateSession(const Duration(minutes: 10));
        s.finishWorkout(kind);
        expect(s.totalWorkouts - w0, 1, reason: '$kind 應計入累積訓練次數');
        expect(s.history.length - h0, 1, reason: '$kind 應寫入訓練歷史');
      }
    });

    test('連開十場，其中一半是空的 —— 兩邊的總變化仍然相等', () {
      final s = AppState();
      final w0 = s.totalWorkouts;
      final h0 = s.history.length;
      for (var i = 0; i < 10; i++) {
        run(s, sets: i.isEven ? 0 : 2);
      }
      expect(s.totalWorkouts - w0, s.history.length - h0);
      expect(s.totalWorkouts - w0, 5, reason: '只有做了組的那五場算');
    });
  });

  group('空場次不在任何地方留下痕跡', () {
    test('不加累積訓練天數，也不動連續訓練天數', () {
      final s = AppState();
      final days = s.totalWorkoutDays;
      final streak = s.trainingStreakDays;
      final last = s.lastTrainedDate;
      run(s, sets: 0);
      expect(s.totalWorkoutDays, days);
      expect(s.trainingStreakDays, streak,
          reason: '開關一次就能續命的話，連續訓練天數就不是訓練的紀錄了');
      expect(s.lastTrainedDate, last);
    });

    test('不發任何獎勵', () {
      final s = AppState();
      final exp = s.totalExp;
      final coins = s.coins;
      run(s, sets: 0);
      expect(s.totalExp, exp);
      expect(s.coins, coins);
    });

    test('不動能力值', () {
      final s = AppState();
      final before = Map.of(s.points);
      run(s, sets: 0);
      expect(s.points, before);
    });

    test('做了組的那一場，這些才會動', () {
      final s = AppState();
      final days = s.totalWorkoutDays;
      final exp = s.totalExp;
      run(s, sets: 3);
      expect(s.totalWorkoutDays, greaterThan(days));
      expect(s.totalExp, greaterThan(exp));
    });
  });

  group('教官初審門檻不可用「開關」刷出來', () {
    // 累積訓練次數 ≥50 是教官初審門檻。開場即關閉原本是一條刷新路徑 ——
    // 規格在 AI 自動優化那裡已經明文堵過同一條路。
    test('開關一百次，累積訓練次數不動', () {
      final s = AppState();
      final before = s.totalWorkouts;
      for (var i = 0; i < 100; i++) {
        run(s, sets: 0);
      }
      expect(s.totalWorkouts, before);
    });
  });
}
