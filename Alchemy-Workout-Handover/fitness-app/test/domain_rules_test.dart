import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/rank.dart';
import 'package:fitness_app/domain/rewards.dart';

void main() {
  group('能力值等級：六階 ＋ 18 節點', () {
    test('主階門檻與〈能力值等級〉的門檻表一致', () {
      expect(majorGradeOf(0), 'E');
      expect(majorGradeOf(99), 'E');
      expect(majorGradeOf(100), 'D');
      expect(majorGradeOf(249), 'D');
      expect(majorGradeOf(250), 'C');
      expect(majorGradeOf(449), 'C');
      expect(majorGradeOf(450), 'B');
      expect(majorGradeOf(649), 'B');
      expect(majorGradeOf(650), 'A');
      expect(majorGradeOf(849), 'A');
      expect(majorGradeOf(850), 'S');
      expect(majorGradeOf(999), 'S');
    });

    test('小節點分段與分段表一致', () {
      expect(nodeOf(29).label, 'E');
      expect(nodeOf(30).label, 'E+');
      expect(nodeOf(70).label, 'E++');
      expect(nodeOf(314).label, 'C');
      expect(nodeOf(315).label, 'C+');
      expect(nodeOf(585).label, 'B++');
      expect(nodeOf(950).label, 'S++');
    });

    test('呈現格式為「主階 ＋ 本節點累積 ＋ 距下一節點」', () {
      // 例：B　+12　距 30 升 B+
      final p = nodeProgressOf(462);
      expect(p.currentLabel, 'B');
      expect(p.intoNode, 12);
      expect(p.nextLabel, 'B+');
      expect(p.toNext, 515 - 462);
      expect(p.display, 'B　+12　距 53 升 B+');
    });

    test('綜合點數為六維算術平均，非取最高', () {
      final onlyChest = {
        Dim.chest: 900, Dim.back: 10, Dim.legs: 10,
        Dim.shoulders: 10, Dim.arms: 10, Dim.core: 10,
      };
      // 只練胸者不應被判為整體 S 級
      expect(overallGrade(onlyChest), isNot('S'));
      expect(overallPoints(onlyChest), ((900 + 50) / 6).round());
    });
  });

  group('能力值提升公式', () {
    test('Epley：次數超過 10 下以 10 下計', () {
      expect(epley1RM(100, 10), closeTo(epley1RM(100, 15), 0.0001));
      expect(epley1RM(100, 10), closeTo(100 * (1 + 10 / 30), 0.0001));
    });

    test('未訓練者落在 E 級、頂尖者落在 S 級（基準值撐開倍數關係）', () {
      int score(double w, int reps) => measuredScore(
            weightKg: w,
            reps: reps,
            relativeIntensity: 1.0,
            bodyweightKg: 70,
            isMale: true,
          );
      expect(majorGradeOf(score(20, 8)), 'E');
      expect(majorGradeOf(score(140, 1)), 'S');
    });

    test('點數下限為初始值 10、上限硬截斷 999', () {
      final low = measuredScore(
          weightKg: 1, reps: 1, relativeIntensity: 1.0,
          bodyweightKg: 70, isMale: true);
      expect(low, kInitialPoints);
      final high = measuredScore(
          weightKg: 500, reps: 10, relativeIntensity: 3.0,
          bodyweightKg: 70, isMale: true);
      expect(high, kMaxPoints);
    });
  });

  group('單次訓練的提升上限', () {
    test('一、首次封頂於 450 點，超額記入待兌現', () {
      final g = applySessionGain(
          current: 10, measured: 750, pending: 0, isFirstSessionForDim: true);
      expect(g.newPoints, 450);
      // 待兌現為絕對分數（模型：「直到追平待兌現實測值為止」）
      expect(g.newPending, 750);
      expect(g.cappedByFirstTime, isTrue);
    });

    test('二、其後每場最多前進一個節點，落點取下一節點上緣與實測值之較小者', () {
      // 450 (B) 的下一節點為 B+，上緣 584；實測 750 → 取 584
      final g = applySessionGain(
          current: 450, measured: 750, pending: 750, isFirstSessionForDim: false);
      expect(g.newPoints, 584);

      // 實測值低於上緣時取實測值
      final g2 = applySessionGain(
          current: 450, measured: 500, pending: 0, isFirstSessionForDim: false);
      expect(g2.newPoints, 500);
    });

    test('模型舉例：實測 A+ 750 者自 450 起 5 次歸位', () {
      var cur = 10, pending = 0;
      final path = <int>[];
      for (var i = 0; i < 5; i++) {
        final g = applySessionGain(
          current: cur,
          measured: 750,
          pending: pending,
          isFirstSessionForDim: i == 0,
        );
        cur = g.newPoints;
        pending = g.newPending;
        path.add(cur);
      }
      expect(path, [450, 584, 649, 714, 750]);
    });

    test('三、實測值未達當前點數 80% 者本場不補格', () {
      // 當前 584，待兌現 750，本場實測僅 400（< 584 × 0.8 = 467.2）
      final g = applySessionGain(
          current: 584, measured: 400, pending: 750, isFirstSessionForDim: false);
      expect(g.newPoints, 584); // 不前進
      expect(g.newPending, 750); // 待兌現保留
    });

    test('三、實測值達 80% 以上者自動補一格', () {
      final g = applySessionGain(
          current: 584, measured: 500, pending: 750, isFirstSessionForDim: false);
      expect(g.newPoints, 649); // 前進一個節點 B++
    });
  });

  group('階級', () {
    test('累計經驗值門檻公式 C(n) ＝ 8,340 × ((n − 1) / 98)²', () {
      expect(expThresholdForRank(1), 0);
      expect(expThresholdForRank(99), 8340);
      expect(expThresholdForRank(50), (8340 * (49 / 98) * (49 / 98)).round());
    });

    test('階級單調遞增，最高 99', () {
      expect(rankForExp(0), 1);
      expect(rankForExp(8340), 99);
      expect(rankForExp(999999), 99);
    });

    test('排行榜分組：每 10 階一組，共 10 組', () {
      expect(rankGroupOf(1), 0);
      expect(rankGroupOf(10), 0);
      expect(rankGroupOf(11), 1);
      expect(rankGroupOf(99), 9);
      expect(rankGroupLabel(0), '1–10 階');
      expect(rankGroupLabel(9), '91–99 階');
    });
  });

  group('訓練結算的獎勵', () {
    test('完成度係數：完成 100% / 提前結束 70% / 逾時中斷 50%', () {
      expect(completionFactor(EndKind.completed, doneSets: 5, plannedSets: 10), 1.0);
      expect(completionFactor(EndKind.endedEarly, doneSets: 5, plannedSets: 10), 0.7);
      expect(completionFactor(EndKind.timedOut, doneSets: 5, plannedSets: 10), 0.5);
    });

    test('逾時中斷但已完成組數等於總計畫組數者給 100%', () {
      expect(completionFactor(EndKind.timedOut, doneSets: 10, plannedSets: 10), 1.0);
    });

    test('經驗值固定 30，不受終止方式影響；當日僅發一次', () {
      for (final k in EndKind.values) {
        final r = computeSettlement(
          kind: k, source: PlanSource.official, doneSets: 5, plannedSets: 10,
          streakDays: 0, expAlreadyGrantedToday: false,
        );
        expect(r.exp, kTrainingExp);
      }
      final again = computeSettlement(
        kind: EndKind.completed, source: PlanSource.official,
        doneSets: 10, plannedSets: 10, streakDays: 0,
        expAlreadyGrantedToday: true,
      );
      expect(again.exp, 0);
    });

    test('連續訓練加成每天 +1%、上限 30%，金幣實得 30–39', () {
      expect(streakBonus(0), 0);
      expect(streakBonus(12), closeTo(0.12, 1e-9));
      expect(streakBonus(50), 0.30);

      final full = computeSettlement(
        kind: EndKind.completed, source: PlanSource.official,
        doneSets: 10, plannedSets: 10, streakDays: 50,
        expAlreadyGrantedToday: false,
      );
      expect(full.coins, 39);

      final none = computeSettlement(
        kind: EndKind.completed, source: PlanSource.official,
        doneSets: 10, plannedSets: 10, streakDays: 0,
        expAlreadyGrantedToday: false,
      );
      expect(none.coins, 30);
    });

    test('個人排行榜分數 ＝ 基準分 100 × 完成度 × 課表來源係數', () {
      final r = computeSettlement(
        kind: EndKind.endedEarly, source: PlanSource.publishedCustom,
        doneSets: 5, plannedSets: 10, streakDays: 10,
        expAlreadyGrantedToday: false,
      );
      expect(r.leaderboardScore, (100 * 0.7 * 0.75).round());
    });

    test('課表來源係數：官方 100% / 已公開 75% / 未公開 50% / 空白不計分', () {
      expect(planSourceFactor(PlanSource.official), 1.0);
      expect(planSourceFactor(PlanSource.publishedCustom), 0.75);
      expect(planSourceFactor(PlanSource.privateCustom), 0.5);
      expect(planSourceFactor(PlanSource.blank), isNull);

      final blank = computeSettlement(
        kind: EndKind.completed, source: PlanSource.blank,
        doneSets: 3, plannedSets: 3, streakDays: 5,
        expAlreadyGrantedToday: false,
      );
      expect(blank.leaderboardScore, isNull);
    });

    test('連續訓練加成不套用於排行榜分數', () {
      final a = computeSettlement(
        kind: EndKind.completed, source: PlanSource.official,
        doneSets: 10, plannedSets: 10, streakDays: 0,
        expAlreadyGrantedToday: false,
      );
      final b = computeSettlement(
        kind: EndKind.completed, source: PlanSource.official,
        doneSets: 10, plannedSets: 10, streakDays: 30,
        expAlreadyGrantedToday: false,
      );
      expect(a.leaderboardScore, b.leaderboardScore);
      expect(a.coins, lessThan(b.coins));
    });
  });
}
