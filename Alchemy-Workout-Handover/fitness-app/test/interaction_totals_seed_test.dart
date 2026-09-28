// 示範用的互動種子值不可以留在真帳號上（2026-09-28）。
//
// 使用者實測：貼文 0、粉絲 0、關注 0、訓練 6 次，**按讚卻是 145**，
// 而且「按讚 1／10／25／50／100 次」五個成就一開始就已領取 ——
// 他一個讚都沒按過。
//
// 根因：`applySnapshot` 還原 `interactionTotals` 時**只覆寫存檔裡有的鍵**，
// 沒有先清空。新帳號在 `resetToNewAccount()` 裡被清空、存進去的是 `{}`，
// 讀回來時 `{}` 不是 null 但迴圈一圈都沒跑 —— 種子值原封不動留著。
//
// 旁邊的 `interactCounts` 與 `snapshots` 本來就是先 clear 再 addAll。
// 這一處是唯一的例外。
//
// **而那只是一半。** 真正讓成就被白拿的是**順序**：成就的還原在第 489 行
// 就呼叫 `syncAchievementsAfterLoad()` 補跑解鎖判定，而互動計數在第 520 行
// 才還原 —— 重算當下讀到的是建構子留下的示範種子 143。
// 計數後來被清空了，**但成就是單調遞增的，錯誤解鎖撤不回來**。
// 補跑的判定已移到 `applySnapshot` 的最後（且在 `repairLoadedState()` 之後，
// 因為它會補回累積訓練天數，那是累積訓練成就的依據）。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  _orderGroup();

  test('新帳號的存檔讀回來，互動計數是空的', () {
    final a = AppState()..resetToNewAccount();
    expect(a.interactionTotals, isEmpty, reason: '前提：重設有清掉');

    final b = AppState()..applySnapshot(a.toSnapshot());
    for (final k in kInteractionKinds) {
      expect(b.interactionTotals[k] ?? 0, 0, reason: k);
    }
  });

  test('新帳號不會白拿互動成就', () {
    final a = AppState()..resetToNewAccount();
    final b = AppState()..applySnapshot(a.toSnapshot());
    final got = b.achievements
        .where((x) => kInteractionKinds.contains(x.category) && x.unlocked);
    expect(got, isEmpty, reason: '一個讚都沒按過，不該有已解鎖的按讚成就');
  });

  test('存檔裡有值時照樣讀得回來', () {
    final a = AppState()..resetToNewAccount();
    a.interactionTotals['按讚'] = 7;
    final b = AppState()..applySnapshot(a.toSnapshot());
    expect(b.interactionTotals['按讚'], 7);
  });

  test('存檔裡少一個鍵時，那個鍵是 0，不是示範值', () {
    final a = AppState()..resetToNewAccount();
    a.interactionTotals['按讚'] = 3;
    final snap = a.toSnapshot();
    // 「留言」不在存檔裡 —— 舊版存檔就長這樣。
    (snap['interactionTotals'] as Map).remove('留言');

    final b = AppState()..applySnapshot(snap);
    expect(b.interactionTotals['按讚'], 3);
    expect(b.interactionTotals['留言'] ?? 0, 0,
        reason: '沒存到不等於「沿用示範值 41」');
  });
}

// 成就的補跑判定要在**所有欄位都還原完之後**才跑。
void _orderGroup() {
  test('補跑解鎖判定時，讀到的是還原後的數字而不是示範種子', () {
    final a = AppState()..resetToNewAccount();
    a.interactionTotals['按讚'] = 12;
    final b = AppState()..applySnapshot(a.toSnapshot());

    final likes = b.achievements.where((x) => x.category == '按讚');
    // 12 次：1 與 10 該解，25 不該。
    expect(likes.where((x) => x.threshold <= 10).every((x) => x.unlocked), isTrue);
    expect(likes.where((x) => x.threshold >= 25).any((x) => x.unlocked), isFalse,
        reason: '示範種子是 143，讀到它的話 25／50／100 都會被解開');
  });

  test('累積訓練成就讀的是修補後的天數', () {
    final a = AppState()..resetToNewAccount();
    a.startWorkout(a.platformPlans.first);
    final snap = a.toSnapshot();
    // 舊版存檔的壞資料：歷史有紀錄、天數卻是 0（見 1C）。
    snap['totalWorkoutDays'] = 0;
    final b = AppState()..applySnapshot(snap);
    expect(b.totalWorkoutDays, greaterThanOrEqualTo(0));
  });
}
