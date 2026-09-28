// 累積訓練天數：註冊當天練的那幾場也要算（2026-09-28）。
//
// 使用者實測截圖：**累積訓練次數 3、累積訓練天數 0、連續訓練天數 0**。
// 練了三次卻零天，那不可能。
//
// 根因：判斷「今天是不是第一場」問的是 `lastTrainedDate != today`，
// 而 `resetToNewAccount()` 把 `lastTrainedDate` 設成 `registeredOn`＝今天。
// 那個初始值本身是對的（它是給退步門檻用的：「從未訓練者的四道門檻自
// 註冊日的日界起算」），錯在**同一個欄位被拿去回答另一個問題**。
//
// 規格（`02_Aggregate定義.md` §47）：
//     累積訓練天數 | 單調遞增；該當地日期首次「訓練已結算」時 +1，
//                   同日後續場次不再 +1

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

void train(AppState s, {bool anySet = true}) {
  s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
  if (anySet) s.completeCurrentSet();
  s.finishWorkout(anySet ? EndKind.completed : EndKind.endedEarly);
}

/// 一個**今天剛註冊**的帳號 —— 使用者實測時就是這個狀態。
AppState fresh() => AppState()..resetToNewAccount();

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('註冊當天', () {
    test('第一場就要計一天', () {
      final s = fresh();
      expect(s.totalWorkoutDays, 0);
      train(s);
      expect(s.totalWorkouts, 1);
      expect(s.totalWorkoutDays, 1, reason: '這正是使用者踩到的那一格');
      expect(s.trainingStreakDays, 1);
    });

    test('同一天練三場：次數 3、天數 1', () {
      final s = fresh();
      for (var i = 0; i < 3; i++) {
        train(s);
      }
      expect(s.totalWorkouts, 3);
      expect(s.totalWorkoutDays, 1);
      expect(s.trainingStreakDays, 1);
    });
  });

  test('隔天再練，天數與連續天數各 +1', () {
    final s = fresh();
    train(s);
    s.demoClockOffset += const Duration(days: 1);
    train(s);
    expect(s.totalWorkouts, 2);
    expect(s.totalWorkoutDays, 2);
    expect(s.trainingStreakDays, 2);
  });

  test('隔了三天，天數照加但連續重來', () {
    final s = fresh();
    train(s);
    s.demoClockOffset += const Duration(days: 3);
    train(s);
    expect(s.totalWorkoutDays, 2);
    expect(s.trainingStreakDays, 1, reason: '超過 36 小時，連續歸零重算');
  });

  test('一組都沒完成的訓練三樣都不動', () {
    final s = fresh();
    train(s, anySet: false);
    expect(s.totalWorkouts, 0);
    expect(s.totalWorkoutDays, 0);
    expect(s.trainingStreakDays, 0);
  });

  _repairGroup();

  // 這兩個數字在開發者模式的「訓練次數對帳」裡是並排的 ——
  // 就是為了讓這種漂移一眼看得出來。
  test('天數永遠不會大於次數', () {
    final s = fresh();
    for (var d = 0; d < 4; d++) {
      train(s);
      train(s);
      s.demoClockOffset += const Duration(days: 1);
    }
    expect(s.totalWorkoutDays, lessThanOrEqualTo(s.totalWorkouts));
    expect(s.totalWorkoutDays, 4);
    expect(s.totalWorkouts, 8);
  });
}

// 根因修好了，但**修不了已經漏掉的那幾天** —— 那一天的訓練已經寫進歷史，
// 計數器卻永遠少了 1。使用者實測：修完之後再練三次，天數仍然是 0
//（因為歷史裡今天已經有紀錄，新的那幾場不算「今天第一場」）。
//
// 所以 `repairLoadedState()` 要補：歷史是證據，有證據卻沒算到的補上去。
void _repairGroup() {
  group('載入時由歷史修補漏掉的天數', () {
    test('練過卻記成 0 天 —— 載入後補回來', () {
      final a = fresh();
      for (var i = 0; i < 3; i++) {
        train(a);
      }
      final snap = a.toSnapshot();
      // 模擬舊版留下的壞資料：歷史有三筆（同一天），天數卻是 0。
      snap['totalWorkoutDays'] = 0;
      snap['trainingStreakDays'] = 0;

      final b = AppState()..applySnapshot(snap);
      expect(b.history.length, 3, reason: '前提：歷史帶得過去');
      expect(b.totalWorkoutDays, 1, reason: '同一天三場算一天');
      // 連續訓練天數**不補** —— 它可以被合法地調低（永久停權經申訴撤銷
      // 時要重設），從歷史往上補會把那個動作默默抵銷掉。
      // 它本來就會自己好：下一次訓練是該日第一場就重新算。
      expect(b.trainingStreakDays, 0);
    });

    test('只增不減 —— 存檔比歷史多就不動它', () {
      final a = fresh();
      train(a);
      final snap = a.toSnapshot();
      snap['totalWorkoutDays'] = 99;

      final b = AppState()..applySnapshot(snap);
      expect(b.totalWorkoutDays, 99,
          reason: '單調遞增；算多了是 reconcileWorkoutCount() 的事');
    });

    test('沒有訓練歷史時不會憑空補出天數', () {
      final a = fresh();
      final b = AppState()..applySnapshot(a.toSnapshot());
      expect(b.history, isEmpty);
      expect(b.totalWorkoutDays, 0);
    });
  });
}
