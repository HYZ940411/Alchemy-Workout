// 能力值每週升格上限（使用者 2026-10-20 逐題裁決）。
//
// 起因：「每場最多前進一個小節點」只限制每一場，不限制一天幾場。
// 實測同一天連開 10 場、每場只勾一組 500 公斤深蹲，深蹲 449 → … → 999（S 頂）。
//
// 規則：每個維度、每個日曆週（週一 04:00 換週），
// 點數最多升到「本週開始時的點數 ＋ 30% × （999 － 本週開始時的點數）」，至少補 10 分。
// 曲線形：分數越高、每週能補的越少，沒有等級邊界的斷層。
// 每場上限同時拿掉（改由每週上限單獨承擔）。首次訓練（封頂 450）不受此限。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';
import 'package:fitness_app/screens/settlement_screen.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan _plan(String name, double kg) => WorkoutPlan(
      id: 'cap',
      name: '上限測試',
      source: PlanSource.privateCustom,
      exercises: [
        PlanExercise(
            exercise: kPlatformExercises.firstWhere((e) => e.name == name),
            planned: [PlannedSet(kg, 10)]),
      ],
    );

/// 開一場、勾一組、結算，回傳結算結果。
SettlementResult _session(AppState s, {String ex = '深蹲 · 槓鈴', double kg = 500}) {
  s.beginWorkout(_plan(ex, kg));
  s.editCurrentSet(weight: kg, reps: 10);
  s.completeCurrentSet();
  return s.finishWorkout(EndKind.completed);
}

int _legs(AppState s) => s.points[Dim.legs]!;

/// 全新帳號：六維 10 分、沒練過。`AppState(demo: false)` 的點數仍是假資料（腿 318），
/// 不能當「首次訓練」用 —— 要走 [AppState.resetToNewAccount]。
AppState _fresh() => AppState(demo: false)..resetToNewAccount();

/// 把示範時鐘釘在指定時刻，免得測試剛好跨過週一 04:00 而偶發失敗。
void _pinClock(DateTime at) => appClockOffset = at.difference(DateTime.now());

AbilityGain _gain(int current, int measured,
        {int pending = 0, int? weekBase, bool first = false}) =>
    applySessionGain(
        current: current,
        measured: measured,
        pending: pending,
        isFirstSessionForDim: first,
        weekBase: weekBase);

void main() {
  // 2026-10-21 是週三。
  final wed = DateTime(2026, 10, 21, 12);

  tearDown(resetAppClock);

  group('週界', () {
    test('週一 04:00 換週，週日深夜與週一凌晨仍屬上一週', () {
      final monday = DateTime(2026, 10, 19);
      expect(businessWeekStart(DateTime(2026, 10, 19, 4, 0)), monday);
      expect(businessWeekStart(DateTime(2026, 10, 19, 3, 59)), DateTime(2026, 10, 12));
      expect(businessWeekStart(DateTime(2026, 10, 25, 23, 59)), monday);
      expect(businessWeekStart(DateTime(2026, 10, 26, 3, 59)), monday);
      expect(businessWeekStart(DateTime(2026, 10, 26, 4, 0)), DateTime(2026, 10, 26));
    });
  });

  group('曲線：本週最多能升到哪裡', () {
    test('對照表（30%）：分數越高，每週能補的越少', () {
      // 與給使用者看的表一致。
      expect(weeklyCeilingOf(50), 335);
      expect(weeklyCeilingOf(130), 391);
      expect(weeklyCeilingOf(199), 439);
      expect(weeklyCeilingOf(300), 510);
      expect(weeklyCeilingOf(449), 614);
      expect(weeklyCeilingOf(650), 755);
      expect(weeklyCeilingOf(850), 895);
      expect(weeklyCeilingOf(950), 965);
    });

    test('越高越慢：每週能補的分數隨基準單調遞減', () {
      var prev = 1 << 30;
      for (var p = 10; p <= 990; p += 20) {
        final room = weeklyCeilingOf(p) - p;
        expect(room, lessThanOrEqualTo(prev), reason: '基準 $p');
        prev = room;
      }
    });

    test('沒有等級邊界的斷層：449 與 450 的上限只差一點點', () {
      expect((weeklyCeilingOf(450) - weeklyCeilingOf(449)).abs(), lessThanOrEqualTo(2));
    });

    test('至少補 10 分，所以 999 是到得了的；上限不超過 999', () {
      expect(weeklyCeilingOf(990), 999);
      expect(weeklyCeilingOf(985), 995);
      expect(weeklyCeilingOf(999), 999);
    });
  });

  group('單看公式', () {
    test('你的例子：腿 130、實測 379 → 一場直接升到 379（舊的每場一小段只到 199）', () {
      final g = _gain(130, 379, weekBase: 130);
      expect(g.newPoints, 379);
      expect(g.cappedByWeek, isFalse);
    });

    test('實測超過本週上限：停在 391，超出的記進待兌現', () {
      final g = _gain(130, 999, pending: 0, weekBase: 130);
      expect(g.newPoints, 391);
      expect(g.cappedByWeek, isTrue);
      expect(g.newPending, 999);
    });

    test('同一週分兩場補：第一場升到 170，第二場補到上限 391，不是鎖死', () {
      final g = _gain(170, 999, pending: 999, weekBase: 130);
      expect(g.newPoints, 391);
    });

    test('本週已到上限：再練不動', () {
      final g = _gain(391, 999, pending: 999, weekBase: 130);
      expect(g.newPoints, 391);
      expect(g.delta, 0);
      expect(g.cappedByWeek, isTrue);
    });

    test('沒有本週基準（舊存檔）：以當前點數為基準', () {
      final g = _gain(130, 999);
      expect(g.newPoints, 391);
    });

    test('首次訓練不受每週上限約束，也不標「被每週上限擋住」', () {
      final g = _gain(10, 999, first: true, weekBase: 10);
      expect(g.newPoints, kFirstTimeCap);
      expect(g.cappedByWeek, isFalse);
    });

    test('每場上限已拿掉：一場能一次升過好幾個小節點（基準 449 → 實測 600 直接到 600）', () {
      final g = _gain(449, 600, weekBase: 449);
      expect(g.newPoints, 600);
    });

    test('實測沒超過目前點數：不是被每週上限擋，不標記', () {
      final g = _gain(391, 300, weekBase: 130);
      expect(g.newPoints, 391);
      expect(g.cappedByWeek, isFalse);
    });

    test('回歸任務把點數推過本週上限：不往下拉，也不再升', () {
      final g = _gain(500, 999, pending: 999, weekBase: 130);
      expect(g.newPoints, 500);
    });
  });

  group('整場結算', () {
    test('同一天連開 12 場、每場都填 500 公斤：只有第一場有效，其後原地不動', () {
      _pinClock(wed);
      final s = _fresh();
      final seq = [for (var i = 0; i < 12; i++) _session(s).pointsAfter[Dim.legs]!];
      expect(seq.first, inInclusiveRange(440, 450), reason: '首次訓練仍是封頂 450 附近');
      expect(seq.toSet().length, 1, reason: '同一週內第二場起不再升格：$seq');
      expect(s.pending[Dim.legs], greaterThan(seq.first), reason: '沒升上去的實力記在待兌現');
    });

    test('下一個日曆週再練：升到曲線給的上限，同一週再練不再升', () {
      _pinClock(wed);
      final s = _fresh();
      _session(s);
      final first = _legs(s);
      _pinClock(wed.add(const Duration(days: 7)));
      _session(s);
      expect(_legs(s), weeklyCeilingOf(first));
      final second = _legs(s);
      _session(s);
      expect(_legs(s), second, reason: '同一週再練一場不再升');
      _pinClock(wed.add(const Duration(days: 14)));
      _session(s);
      expect(_legs(s), weeklyCeilingOf(second));
    });

    test('跨過週一 04:00：週日晚上一場、週一 03:59 一場，同一週，只算一次', () {
      _pinClock(DateTime(2026, 10, 25, 23, 0));
      final s = _fresh();
      _session(s);
      final first = _legs(s);
      _pinClock(DateTime(2026, 10, 26, 3, 59));
      _session(s);
      expect(_legs(s), first);
      _pinClock(DateTime(2026, 10, 26, 4, 1));
      _session(s);
      expect(_legs(s), weeklyCeilingOf(first));
    });

    test('六維各自計算：腿升過不影響胸的第一次', () {
      _pinClock(wed);
      final s = _fresh();
      _session(s);
      _session(s, ex: '板凳臥推 · 槓鈴', kg: 500);
      expect(s.points[Dim.chest], greaterThan(kInitialPoints), reason: '胸是自己的第一次');
    });

    test('結算結果標出被每週上限擋住的維度；第一次與沒超過紀錄的不標', () {
      _pinClock(wed);
      final s = _fresh();
      final r1 = _session(s);
      expect(r1.weekCapped, isEmpty, reason: '第一次是首次封頂，不是每週上限');
      final r2 = _session(s);
      expect(r2.weekCapped, {Dim.legs});
      // 很輕的一場：實測比目前點數低，不是被擋。
      final r3 = _session(s, kg: 20);
      expect(r3.weekCapped, isEmpty);
    });

    test('存檔再讀回來：本週基準還在，同一週重開 App 也不能重新起算', () {
      _pinClock(wed);
      final s = _fresh();
      _session(s);
      final first = _legs(s);
      final snap = s.toSnapshot();

      final s2 = _fresh();
      expect(s2.applySnapshot(snap), isTrue);
      expect(s2.weekGain[Dim.legs]?.base, s.weekGain[Dim.legs]!.base);
      _session(s2);
      expect(_legs(s2), first, reason: '讀回後同一週仍不能再升');
    });

    test('舊存檔沒有 weekGain：讀得進來，不當掉', () {
      final snap = _fresh().toSnapshot()..remove('weekGain');
      final s = _fresh();
      expect(s.applySnapshot(snap), isTrue);
      expect(s.weekGain, isEmpty);
    });
  });

  group('結算畫面的說明', () {
    Future<void> show(WidgetTester t, AppState s) async {
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

    const generic = '本次訓練未推進任何維度 —— 點數只在超越自身紀錄時上升。';

    testWidgets('被每週上限擋住：講「本週已升到上限」，不再說「只在超越紀錄時上升」', (t) async {
      _pinClock(wed);
      final s = _fresh();
      _session(s);
      _session(s);
      await show(t, s);
      expect(find.text('腿本週已升到上限，這次的表現已記下。下週再練腿，就能繼續往上。'),
          findsOneWidget);
      expect(find.text(generic), findsNothing);
    });

    testWidgets('真的沒超過自己的紀錄：維持原句，不出現「本週已升到上限」', (t) async {
      _pinClock(wed);
      final s = _fresh();
      _session(s);
      _session(s, kg: 20);
      await show(t, s);
      expect(find.text(generic), findsOneWidget);
      expect(find.textContaining('本週已升到上限'), findsNothing);
    });
  });
}
