import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_equipment.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/main.dart';

/// 腿日用到腿部推蹬（機械式器材），而預設持有明細沒有機械式器材。
AppState _withBlockedPlan() {
  final s = AppState();
  final plan = s.platformPlans
      .firstWhere((p) => p.exercises.any((e) => e.exercise.id == 'legpress'));
  s.startWorkout(plan);
  return s;
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('比對粒度為細層 8 品項', () {
    test('所需器材未被涵蓋的動作會被挑出來', () {
      final s = _withBlockedPlan();
      final blocked = s.unavailableExercises();
      expect(blocked.map((e) => e.exercise.id), contains('legpress'));
      expect(s.missingEquipment(), contains('機械式器材'));
    });

    test('所需器材要「全部」具備才算涵蓋，不是有一項就算', () {
      final s = AppState();
      // p482 引體向上-彈力帶：需要彈力繩 ＋ 機械式器材。
      s.ownedEquipment
        ..clear()
        ..add('彈力繩');
      final plan = s.platformPlans.first;
      s.startWorkout(plan);
      s.addExerciseToSession(
          s.exerciseById('p482'), const [PlannedSet(0, 8)]);
      expect(s.unavailableExercises().map((e) => e.exercise.id),
          contains('p482'),
          reason: '只有彈力繩、沒有機械式器材，這個動作做不了');
      expect(s.missingEquipment(), contains('機械式器材'));
      expect(s.missingEquipment(), isNot(contains('彈力繩')));
    });

    test('所需器材全部具備的動作不被挑出來', () {
      final s = _withBlockedPlan();
      final ids = s.unavailableExercises().map((e) => e.exercise.id);
      expect(ids, isNot(contains('squat')), reason: '槓鈴深蹲的器材是有的');
    });

    test('持有器材明細為空值者，退回註冊填入的 3 級器材', () {
      final s = AppState();
      s.ownedEquipment.clear();
      s.equipmentTier = '健身房（全器材）';
      expect(s.availableEquipment, containsAll(kEquipmentItems));

      s.equipmentTier = '徒手';
      expect(s.availableEquipment, {'徒手'});
    });

    test('所需器材明細為空值者不參與比對，視為可執行', () {
      expect(requiredEquipment('不限'), isEmpty);
      expect(requiredEquipment(''), isEmpty);
      // 「＋」之後為配件，不屬模型值域，不參與比對。
      expect(requiredEquipment('槓鈴 ＋ 平板椅'), {'槓鈴'});

      final s = _withBlockedPlan();
      final blocked = s.unavailableExercises();
      for (final pe in blocked) {
        expect(requiredEquipment(pe.exercise.equipment), isNotEmpty);
      }
    });
  });

  group('解鎖預設僅對本次訓練有效', () {
    test('解鎖後全部器材視為可用，做不了的清單清空', () {
      final s = _withBlockedPlan();
      s.unlockSessionEquipment();
      expect(s.sessionEquipmentUnlocked, isTrue);
      expect(s.unavailableExercises(), isEmpty);
      expect(s.equipmentForFiltering, containsAll(kEquipmentItems));
    });

    test('未勾選套用至未來：不寫回持有器材明細', () {
      final s = _withBlockedPlan();
      final before = {...s.ownedEquipment};
      s.unlockSessionEquipment();
      expect(s.ownedEquipment, before, reason: '不改動任何設定');
    });

    test('訓練結束即失效', () {
      final s = _withBlockedPlan();
      s.unlockSessionEquipment();
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.sessionEquipmentUnlocked, isFalse);
      expect(s.equipmentForFiltering, isNot(contains('機械式器材')));
    });

    test('放棄訓練也失效', () {
      final s = _withBlockedPlan();
      s.unlockSessionEquipment();
      s.abandonWorkout();
      expect(s.sessionEquipmentUnlocked, isFalse);
    });

    test('下一次訓練不繼承上一次的解鎖', () {
      final s = _withBlockedPlan();
      s.unlockSessionEquipment();
      s.abandonWorkout();
      final plan = s.platformPlans
          .firstWhere((p) => p.exercises.any((e) => e.exercise.id == 'legpress'));
      s.startWorkout(plan);
      expect(s.sessionEquipmentUnlocked, isFalse);
      expect(s.unavailableExercises(), isNotEmpty);
    });
  });

  group('套用至未來所有訓練', () {
    test('勾選時把缺少的器材寫回持有器材明細', () {
      final s = _withBlockedPlan();
      expect(s.ownedEquipment, isNot(contains('機械式器材')));
      s.unlockSessionEquipment(applyToFuture: true);
      expect(s.ownedEquipment, contains('機械式器材'));
    });

    test('寫回後即使不解鎖也做得了，設定頁看得到改動', () {
      final s = _withBlockedPlan();
      s.unlockSessionEquipment(applyToFuture: true);
      s.abandonWorkout();
      final plan = s.platformPlans
          .firstWhere((p) => p.exercises.any((e) => e.exercise.id == 'legpress'));
      s.startWorkout(plan);
      expect(s.unavailableExercises(), isEmpty);
    });

    test('原本走 3 級退回者，寫回時一併落地退回的基準', () {
      final s = AppState();
      s.ownedEquipment.clear();
      s.equipmentTier = '居家器材（彈力繩、小啞鈴等）';
      final home = {...s.availableEquipment};
      expect(home, contains('啞鈴'));
      final plan = s.platformPlans
          .firstWhere((p) => p.exercises.any((e) => e.exercise.id == 'legpress'));
      s.startWorkout(plan);
      s.unlockSessionEquipment(applyToFuture: true);
      expect(s.ownedEquipment, containsAll(home),
          reason: '寫回一個品項不該讓可用器材反而變少');
      expect(s.ownedEquipment, contains('機械式器材'));
    });
  });

  group('進入訓練時自動跳出解鎖抽屜（畫面）', () {
    testWidgets('有動作做不了時跳出，且套用至未來預設不勾', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.fitness_center).last);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('腿日：深蹲主導'), 300);
      await t.pumpAndSettle();
      await t.tap(find.text('腿日：深蹲主導'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('開始訓練'), 300);
      await t.pumpAndSettle();
      await t.tap(find.text('開始訓練'));
      await t.pumpAndSettle();

      expect(find.text('本次訓練器材已解鎖'), findsOneWidget);
      expect(find.text('套用至未來所有訓練'), findsOneWidget);
      expect(find.textContaining('這次解鎖只對本次訓練有效'), findsOneWidget,
          reason: '預設不勾，說明文字要講的是「不會被改動」');
      expect(find.textContaining('會把'), findsNothing);
    });
  });
}
