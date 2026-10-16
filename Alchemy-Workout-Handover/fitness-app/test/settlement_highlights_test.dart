// 結算頁的「亮點」只列這場訓練造成的（2026-10-16 使用者回報）。
//
// 實測：練完一場，亮點出現「成就解鎖：分享 1／10／25 次」「按讚 1 次」—— 跟訓練無關。
// 原因：結算列的是 `_syncAchievements()` 這次新解鎖的全部；互動計數若在別處變了
// 卻沒判定解鎖，那些成就要等到下一次訓練結束才冒出來。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

AppState _freshAccount() {
  final s = AppState(demo: false)..resetToNewAccount();
  final plan = s.platformPlans.firstWhere(
      (p) => p.source == PlanSource.official && p.exercises.length >= 2);
  s.beginWorkout(plan);
  s.completeCurrentSet();
  return s;
}

Set<String> _names(Iterable<Achievement> l) =>
    {for (final a in l) '${a.category}${a.threshold}'};

void main() {
  test('互動計數在訓練前就達標：不會變成這場訓練的亮點，但成就照樣解鎖', () {
    final s = _freshAccount();
    // 計數變了，沒人叫它判定解鎖（任何一條漏掉判定的路徑都是這個形狀）。
    s.interactionTotals['分享'] = 26;
    s.interactionTotals['按讚'] = 3;
    expect(s.achievements.where((a) => a.category == '分享' && a.unlocked),
        isEmpty,
        reason: '前提：確實還沒解鎖');

    final r = s.finishWorkout(EndKind.endedEarly);
    expect(_names(r.newlyUnlocked).where((n) => n.startsWith('分享')), isEmpty);
    expect(_names(r.newlyUnlocked).where((n) => n.startsWith('按讚')), isEmpty);
    // 沒有被吞掉：解鎖紀錄在，成就頁看得到、領得到。
    expect(
        s.achievements
            .where((a) => a.category == '分享' && a.threshold <= 25)
            .every((a) => a.unlocked),
        isTrue);
  });

  test('這場訓練造成的解鎖仍然會列在亮點', () {
    final s = _freshAccount();
    final r = s.finishWorkout(EndKind.endedEarly);
    expect(_names(r.newlyUnlocked), contains('累積訓練1'),
        reason: '第一場訓練完成 → 累積訓練 1 天，這才是這場的亮點');
  });
}
