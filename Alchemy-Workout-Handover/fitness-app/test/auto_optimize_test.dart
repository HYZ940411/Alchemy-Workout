import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

/// 假資料一開始就有一份掛著建議的課表；先把它處理掉，
/// 才驗得到「新的建議是被觸發產生的」。
Future<AppState> _clean() async {
  final s = AppState();
  final p = s.aiOptimizePlan;
  if (p != null) {
    s.aiRequest(AiSource.autoOptimize, '調一下');
    await s.aiConfirmDemand(AiSource.autoOptimize, '整體降強度');
    s.aiProduceSuggestion(AiSource.autoOptimize);
    s.aiReject(AiSource.autoOptimize);
  }
  s.autoOptimizeCount = 0;
  return s;
}

void _train(AppState s, {bool anySet = true}) {
  s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
  if (anySet) s.completeCurrentSet();
  s.finishWorkout(anySet ? EndKind.completed : EndKind.endedEarly);
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('每 3 次合格訓練觸發一次', () {
    test('不到 3 次不觸發', () async {
      final s = await _clean()..subscribe(yearly: false);
      _train(s);
      _train(s);
      expect(s.aiOptimizePlan, isNull);
      expect(s.autoOptimizeCount, 2);
    });

    test('滿 3 次產生一份建議，計數歸零', () async {
      final s = await _clean()..subscribe(yearly: false);
      for (var i = 0; i < 3; i++) {
        _train(s);
      }
      expect(s.aiOptimizePlan, isNotNull);
      expect(s.autoOptimizeCount, 0);
    });

    test('三種終止方式皆計入', () async {
      final s = await _clean()..subscribe(yearly: false);
      for (final k in EndKind.values) {
        s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
        s.completeCurrentSet();
        s.finishWorkout(k);
      }
      expect(s.aiOptimizePlan, isNotNull);
    });

    test('一組都沒完成的訓練不計入 —— 不構成歷史訓練資料', () async {
      final s = await _clean()..subscribe(yearly: false);
      for (var i = 0; i < 5; i++) {
        _train(s, anySet: false);
      }
      expect(s.autoOptimizeCount, 0);
      expect(s.aiOptimizePlan, isNull);
    });
  });

  group('會員與開關', () {
    test('非會員練再多次也收不到建議，但計數照常累計', () async {
      final s = await _clean();
      expect(s.isMember, isFalse);
      for (var i = 0; i < 5; i++) {
        _train(s);
      }
      expect(s.aiOptimizePlan, isNull, reason: '僅會員收得到');
      expect(s.autoOptimizeCount, 5, reason: '非會員期間照常累計');
    });

    test('訂閱當下已達 3 次即立即觸發一次，且不補跑', () async {
      final s = await _clean();
      for (var i = 0; i < 9; i++) {
        _train(s);
      }
      expect(s.autoOptimizeCount, 9);
      s.subscribe(yearly: false);
      expect(s.aiOptimizePlan, isNotNull);
      expect(s.autoOptimizeCount, 0, reason: '只觸發一次，不補跑三份');
    });

    test('關閉開關期間照常累計，重新啟用不補跑', () async {
      final s = await _clean()..subscribe(yearly: false);
      s.setFlag(autoOptimize: false);
      for (var i = 0; i < 9; i++) {
        _train(s);
      }
      expect(s.aiOptimizePlan, isNull);
      expect(s.autoOptimizeCount, 9);

      s.setFlag(autoOptimize: true);
      expect(s.aiOptimizePlan, isNotNull);
      expect(s.autoOptimizeCount, 0);
    });
  });

  group('建議的呈現與覆蓋', () {
    test('同一課表同時只保留一份 —— 後者覆蓋前者', () async {
      final s = await _clean()..subscribe(yearly: false);
      for (var i = 0; i < 6; i++) {
        _train(s);
      }
      final marked =
          s.platformPlans.where((p) => p.hasOptimizationSuggestion).length;
      expect(marked, 1, reason: '不會同時掛著兩份建議');
    });

    test('接受後標記清除，範本真的改了', () async {
      final s = await _clean()..subscribe(yearly: false);
      for (var i = 0; i < 3; i++) {
        _train(s);
      }
      final plan = s.aiOptimizePlan!;
      final before = [
        for (final e in plan.exercises)
          [for (final x in e.planned) (x.targetWeight, x.targetReps)]
      ];
      s.aiRequest(AiSource.autoOptimize, '調一下');
      await s.aiConfirmDemand(AiSource.autoOptimize, '整體降強度');
      s.aiProduceSuggestion(AiSource.autoOptimize);
      s.aiAccept(AiSource.autoOptimize);

      final now = s.platformPlans.firstWhere((p) => p.id == plan.id);
      expect(now.hasOptimizationSuggestion, isFalse);
      expect([
        for (final e in now.exercises)
          [for (final x in e.planned) (x.targetWeight, x.targetReps)]
      ], isNot(before));
    });

    test('自動優化不扣 AI 點數', () async {
      final s = await _clean()..subscribe(yearly: false);
      for (var i = 0; i < 3; i++) {
        _train(s);
      }
      final credits = s.aiTotal;
      s.aiRequest(AiSource.autoOptimize, '調一下');
      await s.aiConfirmDemand(AiSource.autoOptimize, '整體降強度');
      s.aiProduceSuggestion(AiSource.autoOptimize);
      expect(s.aiTotal, credits);
    });
  });
}
