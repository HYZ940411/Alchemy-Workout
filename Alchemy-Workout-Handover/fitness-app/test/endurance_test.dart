// 耐力值（`[QA-02e]`）。
//
// 規格：`03_能力值.md`〈耐力的判定基準有公開錨點〉。
// 上一版是 radar_screen 自己編的 —— 六維點數乘上一個 0.72～0.94 的抖動
// 係數。那不只是假資料，它連語意都相反：耐力值高的人是「相對重的重量
// 做很多下」，跟點數高低沒有那種比例關係。
//
// 這份測試的核心是規格自己給的那個例子（見〈%1RM 的分母〉那一節）。
// 那個例子之所以被寫進規格，正是因為結論反直覺：用很輕的重量做很多下，
// 耐力值**反而低**。實作要是把分母搞錯，測出來會是一個漂亮的高分。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/endurance.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/mock/mock_extra.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('對照表', () {
    test('公開段落原樣取用', () {
      expect(standardRepsAt(100), 1);
      expect(standardRepsAt(75), 10);
      expect(standardRepsAt(65), 15);
    });

    test('外推段落照定案的數字', () {
      expect(standardRepsAt(45), 30);
      expect(standardRepsAt(40), 35);
    });

    test('格與格之間線性內插', () {
      // 47.5% 落在 45（30 下）與 50（26 下）正中間。
      expect(standardRepsAt(47.5), closeTo(28, 0.001));
    });

    test('低於 40% 不算 —— 已非肌力訓練區間', () {
      expect(standardRepsAt(39).isNaN, isTrue);
    });
  });

  group('逐組耐力值', () {
    test('規格的例子：75% 做 15 下是 1.5，做 8 下是 0.8', () {
      expect(
        enduranceOfSet(weightKg: 75, reps: 15, best1RM: 100),
        closeTo(1.5, 0.001),
      );
      expect(
        enduranceOfSet(weightKg: 75, reps: 8, best1RM: 100),
        closeTo(0.8, 0.001),
      );
    });

    test('強度太低的組不計入，回傳空值', () {
      expect(enduranceOfSet(weightKg: 30, reps: 40, best1RM: 100), isNull);
    });

    test('徒手（0 kg）算不出 %1RM', () {
      expect(enduranceOfSet(weightKg: 0, reps: 30, best1RM: 100), isNull);
    });
  });

  group('六維彙總', () {
    List<EnduranceRow> rows(List<(double, int)> sets) => [
          for (final s in sets)
            (dim: Dim.chest, exerciseId: 'bench', weightKg: s.$1, reps: s.$2),
        ];

    test('規格的完整例子：最重推過 60×3，今日 30×20 → 0.67', () {
      // 這是規格自己給的例子，**逐組**的值。
      // 1RM ≈ 60 × (1 + 3/30) = 66；30/66 = 45.5%，標準約 30 下；
      // 20 / 29.6 ≈ 0.67 —— **低於平均**。
      final best = epley1RM(60, 3);
      expect(best, closeTo(66, 0.001));
      expect(
        enduranceOfSet(weightKg: 30, reps: 20, best1RM: best),
        closeTo(0.67, 0.02),
      );
    });

    test('只做過高反覆者沒有可靠的 1RM —— 空值，不推測', () {
      // 這條是整份裡最要緊的。Epley 在 10 下截斷，所以 30kg × 20 下
      // 算出來的「1RM」其實是 40kg（＝ 該組重量的 4/3 倍），
      // 拿它當分母，%1RM 恆為 75%、標準次數恆為 10，
      // 耐力值直接變成 20/10 ＝ 2.0 —— 一個做輕重量高反覆的人
      // 會拿到全 App 最高的耐力值。規格花了一整節否決這件事。
      expect(enduranceOfRows(rows([(30, 20)])), isEmpty);
    });

    test('推過一次大重量之後，同樣那一組就算得出來了，而且是低分', () {
      // 差別只在分母。同樣的 30kg × 20 下：
      // 沒有可靠 1RM 時不給值；有了 66kg 這個分母，它是 0.67。
      final e = enduranceOfRows(rows([(60, 3), (30, 20)]));
      expect(e[Dim.chest], isNotNull);
      expect(e[Dim.chest]!, lessThan(1.0), reason: '輕重量高反覆是低耐力');
    });

    test('40% 以下的組不計入', () {
      // 100×1 給出可靠的 1RM（約 103），20kg 只有 19%，不合格。
      final e = enduranceOfRows(rows([(100, 1), (20, 50)]));
      expect(e[Dim.chest], closeTo(
          enduranceOfRows(rows([(100, 1)]))[Dim.chest]!, 0.001),
          reason: '那一組沒有被算進平均');
    });

    test('沒有任何紀錄就是空的', () {
      expect(enduranceOfRows(const []), isEmpty);
    });

    test('各維度各自獨立，不互相汙染', () {
      final e = enduranceOfRows([
        (dim: Dim.chest, exerciseId: 'bench', weightKg: 100, reps: 1),
        (dim: Dim.chest, exerciseId: 'bench', weightKg: 75, reps: 15),
        (dim: Dim.legs, exerciseId: 'squat', weightKg: 100, reps: 1),
        (dim: Dim.legs, exerciseId: 'squat', weightKg: 75, reps: 5),
      ]);
      expect(e[Dim.chest]!, greaterThan(e[Dim.legs]!));
    });

    test('多組取平均，不取最佳', () {
      // 耐力是穩定特徵，不該被單一組的超水準發揮拉高（2026-09-16 裁決）。
      // 斷言寫成「多加一組表現差的，數字要往下走」而不是一個算好的數字：
      // 後者會跟著 Epley 截斷點這個平台參數一起漂，改個設定就紅一片，
      // 而那跟「取平均還是取最佳」根本沒關係。
      final before = enduranceOfRows(rows([(100, 1), (75, 15)]))[Dim.chest]!;
      final after =
          enduranceOfRows(rows([(100, 1), (75, 15), (75, 5)]))[Dim.chest]!;
      expect(after, lessThan(before), reason: '取最佳的話它不會動');
    });
  });

  group('接到訓練紀錄上', () {
    test('練過大重量之後六維耐力值算得出來', () {
      final s = AppState(demo: false);
      s.history.add(
        HistoryEntry(DateTime(2026, 9, 1), '推日', 0, 40, 0, [
          const HistoryExercise('板凳臥推 · 槓鈴', [(100, 1), (75, 10)],
              id: 'bench'),
        ]),
      );
      expect(s.enduranceByDim[Dim.chest], isNotNull);
      expect(s.enduranceByDim[Dim.chest]!, greaterThan(0));
    });

    test('沒有訓練紀錄就是空的 —— 新帳號不呈現這一區', () {
      expect(AppState(demo: false).enduranceByDim, isEmpty);
    });

    test('計時動作不計入 —— 沒有重量與次數，算不出 %1RM', () {
      final s = AppState(demo: false);
      s.history.add(
        HistoryEntry(DateTime(2026, 9, 1), '核心', 0, 20, 0, [
          const HistoryExercise('棒式', [(0, 60)], isTimed: true, id: 'plank'),
        ]),
      );
      expect(s.enduranceByDim, isEmpty);
    });
  });
}
