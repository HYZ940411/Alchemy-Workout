import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/platform_config.dart';

/// 六個錨點的驗算表 —— **2026-10-19 使用者裁決重新校準後的版本**。
///
/// 原本的表（規格〈基準值與映射係數的實際數值〉，2026-08-19 定案，基準值 27.6、映射係數 23.6）：
/// E 0.5×、D 0.6×、C 0.75×、B 0.875×、A 1.0×、S 1.25× 體重。
/// 使用者認為刻度太陡：體重 70 kg 男性槓鈴臥推 70 kg × 8 下就是 920 分（S 級），
/// 應該是 A 級。於是兩個參數一起重新校準為 **19.54／14.33**：
/// **新手標準不變**（70 kg 男性槓鈴臥推 40 kg × 10 下 ＝ 294），**S 級下緣約 1.5 倍體重**，
/// A 級下緣約 1.2 倍體重。動到規格的 A 底 1.0× 體重；既有點數不重算。
///
/// 這張表是新的標準答案 —— 兩個參數若被改動而未一起重新校準，這裡會直接指出是哪一階跑掉了。
///
/// 基準人：**80kg 男性、槓鈴臥推（相對強度係數 1.0）**。
const _anchors = <({String grade, double mult, double kg, int lower, int upper})>[
  (grade: 'E', mult: 0.40, kg: 32, lower: 0, upper: 99),
  (grade: 'D', mult: 0.50, kg: 40, lower: 100, upper: 249),
  (grade: 'C', mult: 0.70, kg: 56, lower: 250, upper: 449),
  (grade: 'B', mult: 0.95, kg: 76, lower: 450, upper: 649),
  (grade: 'A', mult: 1.25, kg: 100, lower: 650, upper: 849),
  (grade: 'S', mult: 1.50, kg: 120, lower: 850, upper: 999),
];

/// 錨點給的是 **1RM 本身**，不是某一組的成績。
///
/// 故次數代 0：Epley 為 `重量 × (1 + 次數/30)`，次數 0 時即回傳重量本身。
/// 代 1 會多算 3.3%（80kg 變成 82.7kg），錨點的驗算就不是在驗那張表了。
int _pointsFor(double oneRm, {double bodyweight = 80}) => measuredScore(
      weightKg: oneRm,
      reps: 0,
      relativeIntensity: 1.0,
      bodyweightKg: bodyweight,
      isMale: true,
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('基準值與映射係數', () {
    test('取 2026-10-19 重新校準後的數值（原 27.6／23.6）', () {
      expect(kBaseline, 19.54);
      expect(kMappingFactor, 14.33);
    });

    test('80kg 男性的 DOTS 係數為 0.6895', () {
      expect(dotsCoefficient(bodyweightKg: 80, isMale: true),
          closeTo(0.6895, 0.0001));
    });

    test('新手標準不變：70kg 男性槓鈴臥推 40kg × 10 下 ＝ 294', () {
      expect(
          measuredScore(
              weightKg: 40,
              reps: 10,
              relativeIntensity: 1.0,
              bodyweightKg: 70,
              isMale: true),
          closeTo(294, 1));
    });

    test('S 級下緣（850）落在 70kg 男性最大臥推約 1.5 倍體重（105kg）', () {
      expect(_pointsFor(70 * 1.5, bodyweight: 70), closeTo(850, 3));
    });

    test('使用者的對照：70kg 男性槓鈴臥推 70kg × 8 下是 A 級，不是 S', () {
      final pts = measuredScore(
          weightKg: 70,
          reps: 8,
          relativeIntensity: 1.0,
          bodyweightKg: 70,
          isMale: true);
      expect(majorGradeOf(pts), 'A');
      expect(pts, closeTo(674, 2));
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
      // E 到 S 要撐得開整條刻度 —— 這正是加入基準值的理由。
      expect(pts.last - pts.first, greaterThan(800));
    });

    test('完全未訓練者落在 E 級，不是一進來就中等', () {
      // 新刻度下 E 級到 0.5 倍體重以內（原 0.5 倍）；0.4 倍體重仍是 E。
      expect(majorGradeOf(_pointsFor(32)), 'E');
    });
  });

  group('校準時兩個參數須一起動', () {
    test('只改基準值，A 底就跑掉', () {
      platformConfig.group('ability').param('baseline').value = 5.0;
      expect(majorGradeOf(_pointsFor(100)), isNot('A'));
    });

    test('只改映射係數，S 底就跑掉', () {
      platformConfig.group('ability').param('mapping').value = 11.0;
      expect(majorGradeOf(_pointsFor(120)), isNot('S'));
    });
  });

  group('已知缺口：999 於約 1.62× 體重即觸頂', () {
    // 模型自己標了這個缺口（原本 1.27× 體重）。忠實實作就會帶進來 ——
    // 自行調參數繞過去會讓程式與模型再度分家，缺口該留在模型裡解決。
    test('80kg 男性臥推約 129.5kg 即達上限', () {
      expect(_pointsFor(129.5), kMaxPoints);
      expect(_pointsFor(128), lessThan(kMaxPoints));
    });

    test('S 級內部的三個小節點確實被壓縮', () {
      // S 底 850 到硬上限 999，只有 149 點的空間可切三個小節點。
      final sFloor = _pointsFor(114.5);
      expect(sFloor, inInclusiveRange(845, 855));
      expect(kMaxPoints - sFloor, lessThan(200));
    });
  });
}
