import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/platform_config.dart';

/// 〈基準值與映射係數的實際數值〉的六錨點驗算表。
///
/// 模型自己列了這張表並逐格標了「✅ 落在正確區間」，等於一份標準答案 ——
/// 兩個參數若被改動而未一起重新校準，這裡會直接指出是哪一階跑掉了。
///
/// 基準人：**80kg 男性、槓鈴臥推（相對強度係數 1.0）**。
const _anchors = <({String grade, double mult, double kg, int lower, int upper})>[
  (grade: 'E', mult: 0.500, kg: 40, lower: 0, upper: 99),
  (grade: 'D', mult: 0.600, kg: 48, lower: 100, upper: 249),
  (grade: 'C', mult: 0.750, kg: 60, lower: 250, upper: 449),
  (grade: 'B', mult: 0.875, kg: 70, lower: 450, upper: 649),
  (grade: 'A', mult: 1.000, kg: 80, lower: 650, upper: 849),
  (grade: 'S', mult: 1.250, kg: 100, lower: 850, upper: 999),
];

/// 錨點給的是 **1RM 本身**，不是某一組的成績。
///
/// 故次數代 0：Epley 為 `重量 × (1 + 次數/30)`，次數 0 時即回傳重量本身。
/// 代 1 會多算 3.3%（80kg 變成 82.7kg），錨點的驗算就不是在驗那張表了。
int _pointsFor(double oneRm) => measuredScore(
      weightKg: oneRm,
      reps: 0,
      relativeIntensity: 1.0,
      bodyweightKg: 80,
      isMale: true,
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('基準值與映射係數', () {
    test('取模型 2026-08-19 定案的實際數值', () {
      expect(kBaseline, 27.6);
      expect(kMappingFactor, 23.6);
    });

    test('80kg 男性的 DOTS 係數為 0.6895', () {
      expect(dotsCoefficient(bodyweightKg: 80, isMale: true),
          closeTo(0.6895, 0.0001));
    });

    test('基準值由 E 底反解：40 × 0.6895 ＝ 27.6', () {
      final k = dotsCoefficient(bodyweightKg: 80, isMale: true);
      expect(40 * k, closeTo(kBaseline, 0.05));
    });

    test('映射係數由 A 底反解：650 ÷ (55.16 − 27.58) ＝ 23.6', () {
      final k = dotsCoefficient(bodyweightKg: 80, isMale: true);
      expect(650 / (80 * k - 40 * k), closeTo(kMappingFactor, 0.05));
    });
  });

  group('六個錨點全部落在正確的等級區間', () {
    for (final a in _anchors) {
      test('${a.grade} 級：${a.mult}× 體重（${a.kg.round()}kg）'
          '→ ${a.lower}–${a.upper}', () {
        final pts = _pointsFor(a.kg);
        expect(pts, greaterThanOrEqualTo(a.lower));
        expect(pts, lessThanOrEqualTo(a.upper));
        expect(majorGradeOf(pts), a.grade);
      });
    }

    test('等級隨重量單調遞增，六階不會擠在一起', () {
      final pts = [for (final a in _anchors) _pointsFor(a.kg)];
      for (var i = 1; i < pts.length; i++) {
        expect(pts[i], greaterThan(pts[i - 1]));
      }
      // E 底到 S 底要撐得開整條刻度 —— 這正是加入基準值的理由。
      expect(pts.last - pts.first, greaterThan(900));
    });

    test('完全未訓練者落在 E 級，不是一進來就中等', () {
      expect(majorGradeOf(_pointsFor(40)), 'E');
    });
  });

  group('校準時兩個參數須一起動', () {
    test('只改基準值，A 底就跑掉', () {
      platformConfig.group('ability').param('baseline').value = 15.0;
      expect(majorGradeOf(_pointsFor(80)), isNot('A'));
    });

    test('只改映射係數，S 底就跑掉', () {
      platformConfig.group('ability').param('mapping').value = 11.0;
      expect(majorGradeOf(_pointsFor(100)), isNot('S'));
    });
  });

  group('已知缺口：999 於 1.27× 體重即觸頂', () {
    // 模型自己標了這個缺口。忠實實作就會帶進來 ——
    // 自行調參數繞過去會讓程式與模型再度分家，缺口該留在模型裡解決。
    test('80kg 男性臥推約 101.5kg 即達上限', () {
      expect(_pointsFor(101.5), kMaxPoints);
      expect(_pointsFor(100), lessThan(kMaxPoints));
    });

    test('S 級內部的三個小節點確實被壓縮', () {
      // S 底 850 到硬上限 999，只有 149 點的空間可切三個小節點。
      final sFloor = _pointsFor(100);
      expect(kMaxPoints - sFloor, lessThan(200));
    });
  });
}
