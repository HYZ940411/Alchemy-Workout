// 這一組的重量與次數：步進與直接輸入。
//
// 步進器一次只動一格，從 20 公斤改到 82.5 要按 125 次 —— 而重量是每組
// 都在改的東西。且原本步進是 ±1，一按就再也回不到 .5 的格子上，
// 於是「精度 0.5 公斤」在畫面上其實達不到。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> startWorkout(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
  // 走訓練分頁 → 選課表 → 詳情頁的「開始訓練」。
  // 首頁那顆進的是詳情頁，不是直接開練。
  await t.tap(find.byIcon(Icons.fitness_center).last);
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.text('推日：胸肩三頭'), 300);
  await t.pumpAndSettle();
  await t.tap(find.text('推日：胸肩三頭'));
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.text('開始訓練'), 300);
  await t.pumpAndSettle();
  await t.tap(find.text('開始訓練'));
  await t.pumpAndSettle();
  final s = AppScope.of(t.element(find.byType(Scaffold).first));
  expect(s.currentRecord, isNotNull, reason: '前置沒進到訓練中，後面全都測不到');
  return s;
}

/// 與 [anchor] 位在同一橫列的那顆圖示按鈕。
///
/// 不用 `find.ancestor(..., Row)`：ValueUnit 內部自己也是一個 Row，
/// 抓到的會是它，而不是步進器那一列。用座標比對最直接。
Finder _sameRowAs(WidgetTester t, Finder anchor, IconData icon) {
  final y = t.getCenter(anchor).dy;
  Element? best;
  var bestDy = double.infinity;
  for (final e in find.byIcon(icon).evaluate()) {
    final box = e.renderObject as RenderBox;
    final dy = (box.localToGlobal(box.size.center(Offset.zero)).dy - y).abs();
    if (dy < bestDy) {
      bestDy = dy;
      best = e;
    }
  }
  if (best == null || bestDy > 30) {
    throw StateError('找不到與 ${t.getCenter(anchor)} 同列的 $icon');
  }
  return find.byElementPredicate((e) => e == best);
}

void main() {
  group('數值的界線', () {
    test('重量收斂到 0.5 的格子上，且不為負', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.editCurrentSet(weight: 30.4);
      expect(s.currentRecord!.weight, 30.5);
      s.editCurrentSet(weight: 30.24);
      expect(s.currentRecord!.weight, 30.0);
      s.editCurrentSet(weight: -5);
      expect(s.currentRecord!.weight, 0, reason: '0 代表徒手，負數不是合法值');
    });

    test('次數是整數且至少 1 —— 不記錄次數為 0 的失敗組', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.editCurrentSet(reps: 0);
      expect(s.currentRecord!.reps, 1);
      s.editCurrentSet(reps: -3);
      expect(s.currentRecord!.reps, 1);
    });

    test('步進 0.5 —— 從 .5 的值出發仍落在 .5 的格子上', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.editCurrentSet(weight: 30.5);
      s.editCurrentSet(weight: s.currentRecord!.weight + 0.5);
      expect(s.currentRecord!.weight, 31.0);
      s.editCurrentSet(weight: s.currentRecord!.weight - 0.5);
      expect(s.currentRecord!.weight, 30.5, reason: '±1 的話這裡會變 30 或 32');
    });
  });

  group('按鈕真的走 0.5 一格', () {
    testWidgets('按加號，重量 +0.5 而不是 +1', (t) async {
      final s = await startWorkout(t);
      final before = s.currentRecord!.weight;

      final plus = _sameRowAs(t, find.text('kg').last, Icons.add);
      await t.tap(plus);
      await t.pumpAndSettle();
      expect(s.currentRecord!.weight, before + 0.5,
          reason: '模型訂的重量精度是 0.5 公斤，步進 1 就永遠踩不到 .5 的格子');
    });

    testWidgets('按減號，重量 −0.5', (t) async {
      final s = await startWorkout(t);
      final before = s.currentRecord!.weight;
      await t.tap(_sameRowAs(t, find.text('kg').last, Icons.remove));
      await t.pumpAndSettle();
      expect(s.currentRecord!.weight, before - 0.5);
    });
  });

  group('點數字直接輸入', () {
    testWidgets('點重量會跳出輸入框，打完就套用', (t) async {
      final s = await startWorkout(t);
      final before = s.currentRecord!.weight;

      await t.tap(find.text('kg').last);
      await t.pumpAndSettle();
      expect(find.text('這一組的重量'), findsOneWidget,
          reason: '點了數字沒反應 —— 只剩加減一格可用');

      await t.enterText(find.byType(TextField).last, '82.5');
      await t.tap(find.text('確定'));
      await t.pumpAndSettle();
      expect(s.currentRecord!.weight, 82.5);
      expect(s.currentRecord!.weight, isNot(before));
    });

    testWidgets('輸入不合精度的數字會被擋下並說明', (t) async {
      final s = await startWorkout(t);
      final before = s.currentRecord!.weight;

      await t.tap(find.text('kg').last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '82.3');
      await t.tap(find.text('確定'));
      await t.pumpAndSettle();
      expect(find.text('這一組的重量'), findsOneWidget, reason: '不該就這樣關掉');
      expect(s.currentRecord!.weight, before, reason: '擋下就不該改到值');
      expect(find.textContaining('0.5'), findsWidgets, reason: '要講得出為什麼');
    });

    testWidgets('點次數同樣可以直接輸入，且擋掉 0', (t) async {
      final s = await startWorkout(t);
      await t.tap(find.text('次').last);
      await t.pumpAndSettle();
      expect(find.text('這一組的次數'), findsOneWidget);

      await t.enterText(find.byType(TextField).last, '0');
      await t.tap(find.text('確定'));
      await t.pumpAndSettle();
      expect(find.text('這一組的次數'), findsOneWidget, reason: '0 次不是合法值');

      await t.enterText(find.byType(TextField).last, '12');
      await t.tap(find.text('確定'));
      await t.pumpAndSettle();
      expect(s.currentRecord!.reps, 12);
    });

    testWidgets('取消不改值', (t) async {
      final s = await startWorkout(t);
      final before = s.currentRecord!.weight;
      await t.tap(find.text('kg').last);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, '99');
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(s.currentRecord!.weight, before);
    });
  });
}
