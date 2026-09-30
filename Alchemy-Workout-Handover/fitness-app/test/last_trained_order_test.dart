import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/mock/mock_extra.dart';
import 'package:fitness_app/state/app_state.dart';

HistoryEntry entry(String plan, DateTime at, {double? completion}) =>
    HistoryEntry(at, plan, 500, 40, 200, const [], completion: completion);

void main() {
  // 使用者回報「該訓練的上次訓練還是顯示 2 天前、上次完成度還是 —」。
  // 那時雲端的訓練歷史順序是反的（舊的在前），而「最近的一場」取的是
  // 清單裡第一筆 —— 於是讀到的是最舊那場，而舊場次沒有完成度。
  group('「上次訓練」由日期決定，不由清單順序決定', () {
    test('歷史是新的在前時取到新的', () {
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty);
      s.history
        ..clear()
        ..addAll([
          entry(plan.name, DateTime(2026, 9, 26), completion: 0.9),
          entry(plan.name, DateTime(2026, 9, 24)),
        ]);
      expect(s.lastTrainedOf(plan), DateTime(2026, 9, 26));
      expect(s.lastCompletionOf(plan), 0.9);
    });

    test('歷史順序反過來時，答案要一樣', () {
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty);
      s.history
        ..clear()
        ..addAll([
          entry(plan.name, DateTime(2026, 9, 24)),
          entry(plan.name, DateTime(2026, 9, 26), completion: 0.9),
        ]);
      expect(s.lastTrainedOf(plan), DateTime(2026, 9, 26),
          reason: '最近的一場是日期最晚的，與它排在清單第幾筆無關');
      expect(s.lastCompletionOf(plan), 0.9,
          reason: '完成度要跟著同一場走，不是另一場的');
    });

    test('沒練過這份課表就是沒有 —— 不借別份課表的紀錄', () {
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.exercises.isNotEmpty);
      s.history
        ..clear()
        ..add(entry('別的課表', DateTime(2026, 9, 26), completion: 1.0));
      expect(s.lastTrainedOf(plan), isNull);
      expect(s.lastCompletionOf(plan), isNull);
    });
  });
}
