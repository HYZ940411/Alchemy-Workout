// 結算畫面要把「為什麼沒發獎勵」講對（使用者 2026-10-19 回報）。
//
// 使用者練了一場推日，不到 5 分鐘，經驗值與金幣都是 0 —— 那是 2026-09-26 的裁決
// （一組都沒完成、或不到 5 分鐘一律不發獎勵），程式是對的。但畫面寫的是
// 「經驗值當日已發放」，那句話只適用於「今天已經領過」；金幣那行只有「+0」，
// 排行榜那行寫「空白課表不計入個人排行榜分數」。三個地方都沒說真正的原因，
// 使用者因此以為是壞了。
//
// 判準與結算共用 `isRewardable`，畫面不再自己猜。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/screens/settlement_screen.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan get _plan => kAllPlans.firstWhere((p) => p.source == PlanSource.official);

/// 開始一場訓練，完成 [done] 組，經過 [minutes] 分鐘後結算。
({AppState s, SettlementResult r}) _workout(AppState s,
    {required int done, required int minutes}) {
  s.startWorkout(_plan);
  for (var i = 0; i < done; i++) {
    s.completeCurrentSet();
  }
  s.backdateSession(Duration(minutes: minutes));
  return (s: s, r: s.finishWorkout(EndKind.completed));
}

Future<void> _show(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 2400 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: SettlementScreen()),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('判準', () {
    test('一組都沒完成 → 不發，原因是沒完成', () {
      expect(isRewardable(doneSets: 0, duration: const Duration(minutes: 30)), isFalse);
      expect(rewardWithheldReason(doneSets: 0, duration: const Duration(minutes: 30)),
          contains('沒有完成任何一組'));
    });

    test('不到 5 分鐘 → 不發，原因寫 5 分鐘', () {
      const d = Duration(minutes: 4, seconds: 59);
      expect(isRewardable(doneSets: 3, duration: d), isFalse);
      expect(rewardWithheldReason(doneSets: 3, duration: d), contains('不到 5 分鐘'));
    });

    test('剛好 5 分鐘、有完成組 → 發，沒有原因', () {
      const d = Duration(minutes: 5);
      expect(isRewardable(doneSets: 1, duration: d), isTrue);
      expect(rewardWithheldReason(doneSets: 1, duration: d), isNull);
    });

    test('結算實際發不發，與判準一致（全新帳號，經驗值當日第一次）', () {
      for (final (done, minutes) in [(0, 30), (3, 2), (3, 5), (3, 30)]) {
        final w = _workout(AppState(demo: false), done: done, minutes: minutes);
        final ok = isRewardable(doneSets: done, duration: Duration(minutes: minutes));
        expect(w.r.rewards.exp > 0, ok, reason: '$done 組 $minutes 分鐘');
        expect(w.r.noRewardReason == null, ok, reason: '$done 組 $minutes 分鐘');
      }
    });
  });

  group('畫面', () {
    testWidgets('不到 5 分鐘：講真正的原因，不再說「經驗值當日已發放」', (t) async {
      final s = AppState(demo: false);
      _workout(s, done: 3, minutes: 2);
      await _show(t, s);
      expect(find.text('經驗值當日已發放'), findsNothing,
          reason: '那句話只適用「今天已經領過」');
      expect(find.text('本場不發經驗值'), findsOneWidget);
      // 金幣、排行榜兩處都講原因。
      expect(find.textContaining('本場不到 5 分鐘'), findsNWidgets(2));
    });

    testWidgets('一組都沒完成：講沒完成', (t) async {
      final s = AppState(demo: false);
      _workout(s, done: 0, minutes: 30);
      await _show(t, s);
      expect(find.text('經驗值當日已發放'), findsNothing);
      expect(find.textContaining('沒有完成任何一組'), findsNWidgets(2));
    });

    testWidgets('夠久：照常顯示經驗值，沒有「不發」的說明', (t) async {
      final s = AppState(demo: false);
      _workout(s, done: 3, minutes: 30);
      await _show(t, s);
      expect(find.textContaining('經驗值 +'), findsOneWidget);
      expect(find.textContaining('本場不到 5 分鐘'), findsNothing);
      expect(find.text('本場不發經驗值'), findsNothing);
    });

    testWidgets('今天第二場（夠久）：經驗值才是「當日已發放」', (t) async {
      final s = AppState(demo: false);
      _workout(s, done: 3, minutes: 30);
      _workout(s, done: 3, minutes: 30);
      await _show(t, s);
      expect(find.text('經驗值當日已發放'), findsOneWidget,
          reason: '這才是那句話該出現的情形');
      expect(find.text('本場不發經驗值'), findsNothing);
    });
  });
}
