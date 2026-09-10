// 全部組做完之後，訓練中頁該長什麼樣。
//
// 游標原本停在最後一組上不動，於是在 13/13 組、完成度 100% 的情況下，
// 畫面仍顯示「目前動作　第 3/3 組」與一整組可編輯的步進器，
// 而「所有組皆已處理，可以結束訓練了」那句永遠不會出現。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

AppState started() {
  final s = AppState();
  s.startWorkout(s.platformPlans.first);
  return s;
}

/// 把每一組都勾完。防作弊要求相鄰兩組不得連續低於 30 秒。
void finishAll(AppState s) {
  var guard = 0;
  while (s.currentRecord != null && guard++ < 60) {
    s.advanceDemoClock(const Duration(seconds: 45));
    if (!s.completeCurrentSet()) break;
  }
}

void main() {
  group('狀態', () {
    test('全部做完後就沒有「目前這一組」了', () {
      final s = started();
      expect(s.currentRecord, isNotNull);
      finishAll(s);
      expect(s.session!.progress, 1.0, reason: '前提：真的全部做完了');
      expect(s.currentRecord, isNull,
          reason: '13/13 組還顯示「第 3/3 組」與可編輯的步進器，是矛盾的');
    });

    test('做完之後再加練，游標會落到新動作上', () {
      final s = started();
      finishAll(s);
      expect(s.currentRecord, isNull);

      final ex = kExercises.first;
      s.addExerciseToSession(ex, const [PlannedSet(20, 10)]);
      expect(s.currentRecord, isNotNull, reason: '加了動作卻沒有目前這一組，就練不下去');
      expect(s.session!.exercises.last.exercise.id, ex.id);
      expect(s.currentRecord!.state, SetState.pending);
    });

    test('取消最後一組，游標回到那一組', () {
      final s = started();
      finishAll(s);
      final lastEx = s.session!.records.length - 1;
      final lastSet = s.session!.records[lastEx].length - 1;
      expect(s.uncheckSet(lastEx, lastSet), isTrue);
      expect(s.currentRecord, isNotNull, reason: '取消之後要能重做');
      expect(s.session!.progress, lessThan(1.0));
    });
  });

  group('畫面', () {
    testWidgets('全部做完，顯示「可以結束訓練了」而非步進器', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.fitness_center).last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('推日：胸肩三頭'), 300);
      await t.tap(find.text('推日：胸肩三頭'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('開始訓練'), 300);
      await t.tap(find.text('開始訓練'));
      await t.pumpAndSettle();

      final s = AppScope.of(t.element(find.byType(Scaffold).first));
      finishAll(s);
      await t.pumpAndSettle();

      expect(find.textContaining('所有組皆已處理'), findsOneWidget);
      expect(find.text('取消該組'), findsNothing,
          reason: '沒有「目前這一組」的時候不該還有一顆取消它的按鈕');

      // 游標推到界外之後，這一區若照樣顯示就會寫出「第 4 / 3 組」。
      expect(find.text('目前動作'), findsNothing,
          reason: '全部做完了就沒有「目前」動作');
      final total = s.session!.exercises.last.planned.length;
      expect(find.textContaining('第 ${total + 1} /'), findsNothing,
          reason: '組序不該超過總組數');
    });

    testWidgets('全部做完不該掉進「自由訓練」的空狀態', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.fitness_center).last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('推日：胸肩三頭'), 300);
      await t.tap(find.text('推日：胸肩三頭'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('開始訓練'), 300);
      await t.tap(find.text('開始訓練'));
      await t.pumpAndSettle();

      final s = AppScope.of(t.element(find.byType(Scaffold).first));
      finishAll(s);
      await t.pumpAndSettle();

      expect(find.text('自由訓練'), findsNothing,
          reason: '這是一份有課表的訓練，只是做完了');
    });
  });
}
