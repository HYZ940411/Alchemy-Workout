// 自訂訓練「儲存後重新整理還在不在」（第二批第 4 項）。
//
// 實測：建好一份自訂訓練、存檔、重新載入，`customPlans` 是空的 ——
// 整份根本沒進存檔，畫面上卻寫著「已儲存」。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/data/store_firestore.dart';
import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> _fresh(Store st) async {
  final s = AppState(demo: false);
  await s.hydrate(st);
  return s;
}

/// 一個已有帳號的 store。
Future<MemoryStore> _account() async {
  final st = MemoryStore();
  final seed = AppState(demo: false);
  await seed.hydrate(MemoryStore());
  seed.signUpCompleted = true;
  await st.save(seed.toSnapshot());
  return st;
}

List<PlanExercise> _exercises(AppState s) {
  final strength = s.platformExercises.firstWhere(
      (e) => e.type == ExerciseType.strength && !e.isBodyweight);
  final cardio =
      s.platformExercises.firstWhere((e) => e.type == ExerciseType.cardio);
  return [
    PlanExercise(
      exercise: strength,
      planned: const [PlannedSet(60, 8), PlannedSet(62.5, 6)],
      restSeconds: 120,
    ),
    PlanExercise(
      exercise: cardio,
      planned: const [PlannedSet(0, 600)],
      unit: PlanUnit.seconds,
    ),
  ];
}

void main() {
  test('建立自訂訓練 → 存檔 → 重新載入，內容一樣', () async {
    final st = await _account();
    final s = await _fresh(st);
    s.addPlan('我的推日', _exercises(s));
    await s.saveNow();

    final back = await _fresh(st);
    expect(back.customPlans.where((p) => p.isMine), hasLength(1));
    final p = back.customPlans.single;
    expect(p.name, '我的推日');
    expect(p.state, CustomPlanState.saved);
    expect(p.exercises, hasLength(2));
    expect(p.exercises[0].planned.map((x) => (x.targetWeight, x.targetReps)),
        [(60.0, 8), (62.5, 6)]);
    expect(p.exercises[0].restSeconds, 120);
    expect(p.exercises[1].unit, PlanUnit.seconds);
    expect(p.exercises[0].exercise.id, _exercises(s)[0].exercise.id);
    expect(p.totalSets, 3);
  });

  test('編輯之後再存，重新載入是編輯後的樣子', () async {
    final st = await _account();
    final s = await _fresh(st);
    s.addPlan('原名', _exercises(s));
    final p = s.customPlans.single;
    p.name = '改過的名字';
    p.exercises = [p.exercises.first];
    s.saveNow();
    await s.saveNow();

    final back = await _fresh(st);
    expect(back.customPlans.single.name, '改過的名字');
    expect(back.customPlans.single.exercises, hasLength(1));
  });

  test('刪除之後重新載入不會又冒出來', () async {
    final st = await _account();
    final s = await _fresh(st);
    s.addPlan('要刪的', _exercises(s));
    s.addPlan('留著的', _exercises(s));
    await s.saveNow();
    s.customPlans.removeWhere((p) => p.name == '要刪的');
    await s.saveNow();

    final back = await _fresh(st);
    expect(back.customPlans.map((p) => p.name), ['留著的']);
  });

  test('名額與鎖定狀態重新載入後不變', () async {
    final st = await _account();
    final s = await _fresh(st);
    final quota = s.customPlanQuota;
    for (var i = 0; i < quota + 2; i++) {
      s.addPlan('第 $i 份', _exercises(s));
    }
    await s.saveNow();
    final lockedBefore = s.quotaLockedPlanIds;

    final back = await _fresh(st);
    expect(back.myPlanCount, quota + 2);
    expect(back.customPlanQuota, quota);
    expect(back.quotaLockedPlanIds, lockedBefore,
        reason: '被鎖的是同幾份（建立順序決定）');
  });

  test('已申請公開、被退回的狀態與理由也保留', () async {
    final st = await _account();
    final s = await _fresh(st);
    s.addPlan('送審的', _exercises(s));
    final p = s.customPlans.single;
    p.state = CustomPlanState.rejected;
    p.rejectReason = '動作說明不足';
    p.appliedAt = DateTime(2026, 10, 1);
    await s.saveNow();

    final back = await _fresh(st);
    expect(back.customPlans.single.state, CustomPlanState.rejected);
    expect(back.customPlans.single.rejectReason, '動作說明不足');
    expect(back.customPlans.single.appliedAt, DateTime(2026, 10, 1));
  });

  test('目前選的課表是自訂訓練時，重新載入後仍選著它', () async {
    final st = await _account();
    final s = await _fresh(st);
    s.addPlan('我的課', _exercises(s));
    s.currentPlan = s.customPlans.single.toWorkoutPlan();
    await s.saveNow();

    final back = await _fresh(st);
    expect(back.currentPlan?.name, '我的課');
  });

  test('找不到的動作只跳過那一筆，整份課表不消失', () async {
    final st = await _account();
    final s = await _fresh(st);
    s.addPlan('混合', _exercises(s));
    await s.saveNow();
    final snap = await st.load();
    ((snap!['customPlans'] as List).first['exercises'] as List)[0]['exerciseId'] =
        'ex-已下架';
    await st.save(snap);

    final back = await _fresh(st);
    expect(back.customPlans, hasLength(1));
    expect(back.customPlans.single.exercises, hasLength(1));
  });

  test('舊存檔沒有這個欄位時，不動現有的自訂訓練', () async {
    final st = await _account(); // 這份存檔不含 customPlans 以外的版本差異
    final snap = (await st.load())!..remove('customPlans');
    await st.save(snap);
    final s = await _fresh(st);
    expect(s.customPlans, isEmpty);
  });

  test('Firestore 版存檔：陣列裡不能再放陣列，寫得進去也讀得回來', () async {
    final db = FakeFirebaseFirestore();
    final st = FirestoreStore(uid: 'u1', firestore: db);
    final seed = AppState(demo: false);
    await seed.hydrate(MemoryStore());
    seed.signUpCompleted = true;
    await st.save(seed.toSnapshot());

    final s = await _fresh(st);
    s.addPlan('雲端課表', _exercises(s));
    await s.saveNow();

    final back = await _fresh(FirestoreStore(uid: 'u1', firestore: db));
    expect(back.customPlans.single.name, '雲端課表');
    expect(back.customPlans.single.totalSets, 3);
  });
}
