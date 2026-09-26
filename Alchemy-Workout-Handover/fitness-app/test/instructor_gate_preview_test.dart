// 教官申請頁的初審分數要算得出來（2026-09-26）。
//
// 使用者實測：**已訓練 7 次，三維分數仍全是 0。**
//
// 根因：`instructor_apply_screen` 讀的是 `s.qualityScore`，而那是
// `quality?.weighted ?? 0` —— `quality` 只在 `reapplyInstructor()` 與
// `advanceInstructorApplication()` 進「初審中」時才被算出來。
// **光是打開那一頁不會觸發評分。**
//
// 而那一頁是個 Read Model：它要在「還沒申請」的時候就告訴你門檻過了沒。
// 那就必須有分數可讀。
//
// 修法是讀到就算（規則，不連網）。**不在這裡呼叫 Gemini** —— 模型那趟
// 要花錢也要時間，而規格把「AI 已產出訓練品質評分」綁在一筆申請上
// （同一筆申請只評分一次）。預覽用規則、真的申請時才問模型。

import 'package:flutter_test/flutter_test.dart';

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
  test('沒有訓練紀錄 → 0，而那是對的（無從評分）', () {
    final s = AppState(demo: false);
    expect(s.qualityScore, 0);
    expect(s.quality!.concerns.join(), contains('沒有任何訓練紀錄'));
  });

  test('練過就算得出分數 —— 不必先按下申請', () {
    final s = _trained(7);
    // 使用者實測的情形：練了 7 次，打開那一頁卻是 0。
    expect(s.qualityScore, greaterThan(0));
    expect(s.sanityScore, greaterThan(0));
  });

  test('讀分數不必事先呼叫 rescore', () {
    final s = _trained(3);
    expect(s.quality, isNull, reason: '前提：還沒算過');
    s.qualityScore; // 只是讀它
    expect(s.quality, isNotNull, reason: '讀到就該算出來');
  });

  test('預覽走規則，不連網', () {
    final s = _trained(3);
    s.qualityScore; // 讀到才會算
    expect(s.quality!.source, 'rules');
  });

  test('又練了一場 → 分數重算，不是沿用舊的', () {
    final s = _trained(3);
    s.qualityScore; // 先讀一次，讓它算出來
    expect(s.quality, isNotNull);

    s.startWorkout(_plan);
    s.completeCurrentSet();
    s.backdateSession(const Duration(minutes: 30));
    s.finishWorkout(EndKind.completed);

    // 訓練紀錄變了，評分就過期了。
    expect(s.quality, isNull, reason: '結算時要讓它失效');
    // **不斷言數字一定不同** —— 多練一場相似的訓練，四捨五入後可能
    // 剛好一樣（實測就是 75 → 75）。要釘的是「有沒有重算」，
    // 而那由上面那行 isNull 加下面這行涵蓋。
    expect(s.qualityScore, greaterThan(0));
    expect(s.quality, isNotNull, reason: '讀到就重算出來');
    // 場次變多了，規律性那一維一定看得到差別。
    expect(s.quality!.concerns, isNot(contains('訓練場次過少')));
  });

  test('一組都沒完成的訓練不進歷史，也就不影響評分', () {
    final s = _trained(3);
    final before = s.qualityScore;

    s.startWorkout(_plan);
    s.backdateSession(const Duration(minutes: 30));
    s.finishWorkout(EndKind.completed); // 沒完成任何一組

    expect(s.qualityScore, before);
  });
}
