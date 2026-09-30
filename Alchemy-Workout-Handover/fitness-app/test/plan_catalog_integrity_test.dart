// 課表目錄的結構性不變條件。
//
// 2026-09-29 把四份官方課表從寫死的 `kPlans` 搬進平台規格（`kLegacyPlanSpecs`）
// 之後，目錄由三段拼起來：平台課表、示範課表、空白課表。
// **拼錯最可能的症狀是同一份課表出現兩次** —— 而那不會拋任何例外，
// 只會讓清單多一列、讓 `firstWhere` 撈到不確定是哪一個的那一份。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/mock/platform_plans.g.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  test('目錄裡沒有重複的課表 ID', () {
    for (final demo in [true, false]) {
      final ids = AppState(demo: demo).platformPlans.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'demo=$demo 時有重複：'
              '${ids.where((x) => ids.where((y) => y == x).length > 1).toSet()}');
    }
  });

  test('搬上雲的四份沒有留在寫死的清單裡', () {
    const moved = ['p_push', 'p_pull', 'p_leg', 'p_power'];
    for (final id in moved) {
      expect(kPlans.any((p) => p.id == id), isFalse, reason: '$id 還留在 kPlans');
      expect(kDemoPlans.any((p) => p.id == id), isFalse);
      expect(kAllPlanSpecs.any((s) => s.id == id), isTrue, reason: '$id 不在規格裡');
    }
  });

  test('規格 = 27 份 CSV ＋ 4 份搬過來的，且互不重疊', () {
    expect(kPlatformPlans, hasLength(27));
    expect(kLegacyPlanSpecs, hasLength(4));
    expect(kAllPlanSpecs, hasLength(31));
    final csv = kPlatformPlans.map((s) => s.id).toSet();
    final legacy = kLegacyPlanSpecs.map((s) => s.id).toSet();
    expect(csv.intersection(legacy), isEmpty);
  });

  test('真帳號看不到假的「使用者自己的東西」', () {
    final real = AppState(demo: false).platformPlans.map((p) => p.id).toSet();
    // 一份他沒建過的自訂課表，和一份來自還沒有任何人的社群的熱門課表。
    expect(real.contains('p_custom'), isFalse);
    expect(real.contains('p_shared'), isFalse);
    // 空白課表是入口不是假資料，真帳號一樣要有。
    expect(real.contains('p_blank'), isTrue);
    // 四份官方課表是真內容，留著。
    expect(real.contains('p_push'), isTrue);

    // 示範模式仍然看得到，那兩條流程的示範沒有被弄丟。
    final demo = AppState().platformPlans.map((p) => p.id).toSet();
    expect(demo.contains('p_custom'), isTrue);
    expect(demo.contains('p_shared'), isTrue);
  });

  test('搬家沒有動到處方 —— 重量、組數、休息秒數一字不差', () {
    final byId = {for (final p in buildCsvPlans()) p.id: p};
    // 臥推 4 組 × 60kg × 8 下、休息 120 秒（課表指定值蓋過動作預設 150）。
    final bench = byId['p_push']!.exercises.first;
    expect(bench.exercise.id, 'bench');
    expect(bench.planned.length, 4);
    expect(bench.planned.first.targetWeight, 60);
    expect(bench.planned.first.targetReps, 8);
    expect(bench.restSeconds, 120);
    // 深蹲 5 組 × 80kg × 5 下。
    final squat = byId['p_leg']!.exercises.first;
    expect(squat.planned.length, 5);
    expect(squat.planned.first.targetWeight, 80);
    expect(squat.planned.first.targetReps, 5);
  });
}
