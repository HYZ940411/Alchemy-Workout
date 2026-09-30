import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/platform_config.dart';

/// 使用者回報「雖然階級次數有達標，但是無法申請」。
///
/// 申請鍵讀的是 `InstructorGate.passed`，而它包含 `qualityOk` 與 `vetoed`
/// —— 品質評分。還沒申請的人 `quality` 是空值 → 分數當 0 →
/// `qualityOk` 為假、一票否決成立 → **門檻達標也永遠按不下申請鍵**。
///
/// 規格的順序是「使用者已申請教官權限」→ 系統初審 → 系統「分析歷史訓練
/// 品質」（〈教官申請流程〉）—— 評分發生在申請**之後**，
/// 而且屬於那一筆申請（請求識別碼 ＝ 使用者 ID ＋ 教官申請 ID）。
void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  InstructorGate gate({
    int rank = 20,
    int workouts = 50,
    int quality = 0,
    int sanity = 0,
  }) =>
      evaluateInstructorGate(
          rank: rank, workouts: workouts, quality: quality, sanity: sanity);

  group('按得下申請鍵的條件只有階級與次數', () {
    test('還沒評分（分數 0、一票否決成立）也按得下', () {
      final g = gate();
      expect(g.canApply, isTrue, reason: '評分發生在申請之後');
      expect(g.passed, isFalse, reason: '完整初審當然還沒過');
    });

    test('階級不足就按不下', () {
      expect(gate(rank: 19).canApply, isFalse);
    });

    test('次數不足就按不下', () {
      expect(gate(workouts: 49).canApply, isFalse);
    });

    test('剛好達標就按得下', () {
      final g = gate();
      expect(g.rankOk, isTrue);
      expect(g.workoutsOk, isTrue);
      expect(g.canApply, isTrue);
    });
  });

  group('完整初審仍然要看品質', () {
    test('品質不過就不算通過', () {
      final g = gate(quality: 0, sanity: 100);
      expect(g.canApply, isTrue);
      expect(g.passed, isFalse);
    });

    test('一票否決擋得住', () {
      final g = gate(quality: 100, sanity: 0);
      expect(g.canApply, isTrue);
      expect(g.vetoed, isTrue);
      expect(g.passed, isFalse, reason: '加權平均再高也擋不住一票否決');
    });

    test('兩者都過才算通過', () {
      final g = gate(quality: 100, sanity: 100);
      expect(g.passed, isTrue);
    });
  });

  test('passed 一定蘊含 canApply —— 不可能沒達門檻卻通過初審', () {
    for (final r in [10, 20, 30]) {
      for (final w in [10, 50, 80]) {
        final g = gate(rank: r, workouts: w, quality: 100, sanity: 100);
        if (g.passed) expect(g.canApply, isTrue);
      }
    }
  });
}
