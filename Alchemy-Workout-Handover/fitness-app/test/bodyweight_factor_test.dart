// 徒手動作的體重係數（使用者裁決 B，2026-10-16 —— 暫行止血規則）。
//
// 使用者回報「練個徒手動作加分超多」。實測：新帳號伏地挺身 3 組 × 10 下、不加負重，
// 單組分數 999（到頂），比 60 kg 槓鈴臥推的 670 還高。原因：規格寫
// 「代入重量 ＝ 體重 × 體重係數 ＋ 外加負重」，程式卻把整個體重（係數 1.0）當成在推。
//
// 暫行規則：引體向上類 1.0，其餘徒手動作 0.6。逐動作的係數表待內容團隊給（QA-04）。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

Exercise _ex(AppState s, bool Function(Exercise) test) =>
    s.platformExercises.firstWhere(test);

/// 練一場只有一個動作的訓練，回傳那個動作所屬維度的「單組實測分數」。
int _measured(Exercise e, {double added = 0, int reps = 10, double bw = 70}) {
  final s = AppState(demo: false)
    ..resetToNewAccount()
    ..bodyweightKg = bw;
  final plan = WorkoutPlan(
    id: 'p',
    name: 'p',
    source: PlanSource.privateCustom,
    exercises: [
      PlanExercise(
          exercise: e, planned: [PlannedSet(added, reps), PlannedSet(added, reps)])
    ],
  );
  s.beginWorkout(plan);
  if (e.isBodyweight && added > 0) s.setAddedLoad(e, true);
  for (var i = 0; i < 2; i++) {
    s.editCurrentSet(weight: added, reps: reps);
    s.completeCurrentSet();
    s.advanceDemoClock(const Duration(seconds: 40));
  }
  s.backdateSession(const Duration(minutes: 10));
  final r = s.finishWorkout(EndKind.completed);
  return r.measured[e.dim!]!;
}

void main() {
  final s0 = AppState();

  group('係數本身', () {
    test('引體向上各變體 1.0', () {
      final pulls = s0.platformExercises
          .where((e) => e.isBodyweight && e.name.contains('引體向上'))
          .toList();
      expect(pulls, isNotEmpty, reason: '前提：動作庫有引體向上');
      for (final e in pulls) {
        expect(e.bodyweightFactor, 1.0, reason: e.name);
      }
    });

    test('其餘徒手動作 0.6（伏地挺身、仰臥起坐…）', () {
      final others = s0.platformExercises
          .where((e) => e.isBodyweight && !e.name.contains('引體向上'));
      expect(others.length, greaterThan(100));
      for (final e in others) {
        expect(e.bodyweightFactor, 0.6, reason: e.name);
      }
      expect(_ex(s0, (e) => e.name == '伏地挺身').bodyweightFactor, 0.6);
    });

    test('非徒手動作不受影響（固定 1.0）', () {
      final barbell = _ex(s0, (e) => !e.isBodyweight);
      expect(barbell.bodyweightFactor, 1.0);
    });
  });

  group('算進能力值的重量', () {
    test('伏地挺身不加負重：用「體重 × 0.6」算，不是整個體重', () {
      final e = _ex(s0, (x) => x.name == '伏地挺身');
      final expected = measuredScore(
          weightKg: 70 * 0.6,
          reps: 10,
          relativeIntensity: e.relativeIntensity,
          bodyweightKg: 70,
          isMale: AppState().isMale);
      expect(_measured(e), expected);
      final old = measuredScore(
          weightKg: 70,
          reps: 10,
          relativeIntensity: e.relativeIntensity,
          bodyweightKg: 70,
          isMale: AppState().isMale);
      expect(_measured(e), lessThan(old), reason: '以前的算法偏高');
    });

    test('外加負重照樣加在上面', () {
      final e = _ex(s0, (x) => x.name == '站姿提踵'); // 沒到頂的動作才看得出差別
      final base = _measured(e);
      final loaded = _measured(e, added: 10);
      expect(loaded, greaterThan(base));
      final expected = measuredScore(
          weightKg: 70 * 0.6 + 10,
          reps: 10,
          relativeIntensity: e.relativeIntensity,
          bodyweightKg: 70,
          isMale: AppState().isMale);
      expect(loaded, expected);
    });

    test('引體向上還是用整個體重（1.0）', () {
      final e = _ex(s0, (x) => x.name == '引體向上');
      final expected = measuredScore(
          weightKg: 70,
          reps: 10,
          relativeIntensity: e.relativeIntensity,
          bodyweightKg: 70,
          isMale: AppState().isMale);
      expect(_measured(e), expected);
    });

    test('使用者回報的情形：徒手伏地挺身不再比 60 kg 槓鈴臥推高', () {
      final push = _ex(s0, (x) => x.name == '伏地挺身');
      final bench = _ex(
          s0, (x) => x.name.contains('臥推') && x.name.contains('槓鈴') && !x.isBodyweight);
      expect(_measured(push), lessThanOrEqualTo(_measured(bench, added: 60)),
          reason: '以前 999 對 670，伏地挺身不加負重就贏過 60 kg 槓鈴');
    });
  });
}
