// 能力值每週升格上限（使用者 2026-10-20 裁決）。
//
// 起因：「每場最多前進一個小節點」只限制每一場，不限制一天幾場。
// 實測同一天連開 10 場、每場只勾一組 500 公斤深蹲，深蹲 449 → … → 999（S 頂）。
//
// 規則：每個維度，每個日曆週（週一 04:00 換週），點數最多只能升到
// 「本週開始時所在小節點的下一個小節點上緣」。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan _squat500() => WorkoutPlan(
  id: 'cap',
  name: '上限測試',
  source: PlanSource.privateCustom,
  exercises: [
    PlanExercise(
      exercise: kPlatformExercises.firstWhere((e) => e.name == '深蹲 · 槓鈴'),
      planned: const [PlannedSet(500, 10)],
    ),
  ],
);

/// 開一場、勾一組 500 公斤、結算，回傳結算後的腿點數。
int _session(AppState s) {
  s.beginWorkout(_squat500());
  s.editCurrentSet(weight: 500, reps: 10);
  s.completeCurrentSet();
  s.finishWorkout(EndKind.completed);
  return s.points[Dim.legs]!;
}

/// 把示範時鐘釘在指定時刻，免得測試剛好跨過週一 04:00 而偶發失敗。
void _pinClock(DateTime at) => appClockOffset = at.difference(DateTime.now());

int _nextUpper(int p) => kNodes[nodeIndexOf(p) + 1].upper;

void main() {
  // 2026-10-21 是週三。
  final wed = DateTime(2026, 10, 21, 12);

  tearDown(resetAppClock);

  group('週界', () {
    test('週一 04:00 換週，週日深夜與週一凌晨仍屬上一週', () {
      final monday = DateTime(2026, 10, 19);
      expect(businessWeekStart(DateTime(2026, 10, 19, 4, 0)), monday);
      expect(
        businessWeekStart(DateTime(2026, 10, 19, 3, 59)),
        DateTime(2026, 10, 12),
      );
      expect(businessWeekStart(DateTime(2026, 10, 25, 23, 59)), monday);
      expect(businessWeekStart(DateTime(2026, 10, 26, 3, 59)), monday);
      expect(
        businessWeekStart(DateTime(2026, 10, 26, 4, 0)),
        DateTime(2026, 10, 26),
      );
    });
  });

  group('單看公式', () {
    test('本週基準 449（C 級頂）：實測再高，本週最多 514', () {
      final g = applySessionGain(
        current: 449,
        measured: 999,
        pending: 999,
        isFirstSessionForDim: false,
        weekBase: 449,
      );
      expect(g.newPoints, 514);
      expect(g.newPending, 999, reason: '沒升上去的實力照樣記著');
    });

    test('同一週分兩場補：第一場升到 480，第二場補到上限 514，不是鎖死', () {
      // 本週基準 449；上一場已經升到 480，這一場實測 999。
      final g = applySessionGain(
        current: 480,
        measured: 999,
        pending: 999,
        isFirstSessionForDim: false,
        weekBase: 449,
      );
      expect(g.newPoints, 514);
    });

    test('本週已到上限：再練不動', () {
      final g = applySessionGain(
        current: 514,
        measured: 999,
        pending: 999,
        isFirstSessionForDim: false,
        weekBase: 449,
      );
      expect(g.newPoints, 514);
      expect(g.delta, 0);
    });

    test('沒有本週基準（舊存檔）：與原本的「每場一格」相同', () {
      final g = applySessionGain(
        current: 449,
        measured: 999,
        pending: 0,
        isFirstSessionForDim: false,
      );
      expect(g.newPoints, 514);
    });

    test('首次訓練不受每週上限約束', () {
      final g = applySessionGain(
        current: 10,
        measured: 999,
        pending: 0,
        isFirstSessionForDim: true,
        weekBase: 10,
      );
      expect(g.newPoints, kFirstTimeCap);
    });

    test('每場一格仍然有效：基準很低、當前在更高節點時取較小者', () {
      // 回歸任務把點數推到基準之上的下一節點；本週不再往上。
      final g = applySessionGain(
        current: 584,
        measured: 999,
        pending: 999,
        isFirstSessionForDim: false,
        weekBase: 449,
      );
      expect(g.newPoints, 584);
    });
  });

  group('整場結算', () {
    test('同一天連開 12 場、每場都填 500 公斤：只有第一場有效，其後原地不動', () {
      _pinClock(wed);
      final s = AppState(demo: false);
      final seq = [for (var i = 0; i < 12; i++) _session(s)];
      expect(seq.first, inInclusiveRange(440, 450), reason: '首次訓練仍是封頂 450 附近');
      expect(seq.toSet().length, 1, reason: '同一週內第二場起不再升格：$seq');
      expect(
        s.pending[Dim.legs],
        greaterThan(seq.first),
        reason: '沒升上去的實力記在待兌現',
      );
    });

    test('下一個日曆週再練：升一個小節點，同一週再練不再升', () {
      _pinClock(wed);
      final s = AppState(demo: false);
      final first = _session(s);
      _pinClock(wed.add(const Duration(days: 7)));
      final second = _session(s);
      expect(second, _nextUpper(first), reason: '落點是下一個節點的上緣');
      expect(_session(s), second);
      _pinClock(wed.add(const Duration(days: 14)));
      expect(_session(s), _nextUpper(second));
    });

    test('跨過週一 04:00：週日晚上一場、週一 03:59 一場，同一週，只算一次', () {
      _pinClock(DateTime(2026, 10, 25, 23, 0));
      final s = AppState(demo: false);
      final first = _session(s);
      _pinClock(DateTime(2026, 10, 26, 3, 59));
      expect(_session(s), first);
      _pinClock(DateTime(2026, 10, 26, 4, 1));
      expect(_session(s), _nextUpper(first));
    });

    test('六維各自計算：腿升過不影響胸', () {
      _pinClock(wed);
      final s = AppState(demo: false);
      _session(s);
      final chest = kPlatformExercises.firstWhere((e) => e.name == '板凳臥推 · 槓鈴');
      s.beginWorkout(
        WorkoutPlan(
          id: 'c',
          name: 'c',
          source: PlanSource.privateCustom,
          exercises: [
            PlanExercise(exercise: chest, planned: const [PlannedSet(500, 10)]),
          ],
        ),
      );
      s.editCurrentSet(weight: 500, reps: 10);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(
        s.points[Dim.chest],
        greaterThan(kInitialPoints),
        reason: '胸是自己的第一次',
      );
    });

    test('存檔再讀回來：本週基準還在，同一週重開 App 也不能重新起算', () {
      _pinClock(wed);
      final s = AppState(demo: false);
      final first = _session(s);
      final snap = s.toSnapshot();

      final s2 = AppState(demo: false);
      expect(s2.applySnapshot(snap), isTrue);
      expect(s2.weekGain[Dim.legs]?.base, s.weekGain[Dim.legs]!.base);
      expect(_session(s2), first, reason: '讀回後同一週仍不能再升');
    });

    test('舊存檔沒有 weekGain：讀得進來，不當掉', () {
      final snap = AppState(demo: false).toSnapshot()..remove('weekGain');
      final s = AppState(demo: false);
      expect(s.applySnapshot(snap), isTrue);
      expect(s.weekGain, isEmpty);
    });
  });
}
