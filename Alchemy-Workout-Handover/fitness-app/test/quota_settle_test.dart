import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rank.dart';
import 'package:fitness_app/state/app_state.dart';

int _quota(int rank) =>
    customPlanQuotaForRank(rank, base: 2, max: 5);

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('自訂訓練名額隨階級自 2 成長至 5', () {
    test('里程碑 25 / 45 / 70，沿用進階計畫的同一組數字', () {
      expect(kCustomPlanMilestones, [25, 45, 70]);
      expect(_quota(1), 2);
      expect(_quota(24), 2);
      expect(_quota(25), 3);
      expect(_quota(44), 3);
      expect(_quota(45), 4);
      expect(_quota(69), 4);
      expect(_quota(70), 5);
      expect(_quota(99), 5);
    });

    test('初始為 2 而非 1', () {
      expect(_quota(1), 2,
          reason: 'AI 調整落地的自訂訓練共用同一名額，只有 1 個會立刻被佔滿');
    });

    test('不超過上限', () {
      expect(customPlanQuotaForRank(99, base: 4, max: 5), 5);
    });

    test('會員不受名額限制', () {
      final s = AppState();
      final free = s.customPlanQuota;
      s.subscribe(yearly: false);
      expect(s.customPlanQuota, AppState.kUnlimitedPlans);
      expect(free, lessThan(AppState.kUnlimitedPlans));
    });

    test('AppState 的名額跟著階級走，不是寫死的 5', () {
      final s = AppState();
      expect(s.customPlanQuota, _quota(s.rank));
      s.totalExp = expThresholdForRank(70);
      expect(s.rank, greaterThanOrEqualTo(70));
      expect(s.customPlanQuota, 5);
      s.totalExp = 0;
      expect(s.customPlanQuota, 2);
    });

    test('名額為平台級可調參數', () {
      platformConfig.group('commerce').param('customPlanBase').value = 1;
      expect(AppState().customPlanQuota, _quota(45) - 1);
    });

    test('不變條件擋下上限低於初始值', () {
      final g = platformConfig.group('commerce');
      expect(g.invariant!({...g.values, 'customPlanMax': 1}), isNotNull);
      expect(g.invariant!({...g.values, 'customPlanBase': 0}), isNotNull);
      expect(g.invariant!(g.values), isNull);
    });
  });

  group('排行榜週期結算由排程觸發，不是一顆手動按鈕', () {
    test('同一週期內不重複結算', () {
      final s = AppState();
      expect(s.settleDueBoards(), isEmpty, reason: '第一次只記基準週期');
      s.advanceDemoClock(const Duration(hours: 1));
      expect(s.settleDueBoards(), isEmpty);
    });

    test('跨過週一 04:00：週榜結算並歸零', () {
      final s = AppState();
      s.weeklyScore = 500;
      final before = s.leaderboardHistory.length;
      s.advanceDemoClock(const Duration(days: 8));
      expect(s.leaderboardHistory.length, greaterThan(before));
      expect(
          s.leaderboardHistory.any((h) => h.board == Board.personalWeekly),
          isTrue);
      expect(s.weeklyScore, 0);
    });

    test('跨過月初：月榜與兩個團隊榜一起結算', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 40));
      final boards =
          s.leaderboardHistory.map((h) => h.board).toSet();
      expect(boards, containsAll([
        Board.personalMonthly,
        Board.teamDaily,
        Board.teamTimed,
      ]));
      expect(s.monthlyScore, 0);
    });

    test('團隊榜結算後分數歸零 —— 兩個團隊榜同樣是結算並重置', () {
      final s = AppState();
      expect(s.myTeam!.dailyScore, greaterThan(0));
      s.advanceDemoClock(const Duration(days: 40));
      expect(s.myTeam!.dailyScore, 0);
      expect(s.myTeam!.timedCredited, isEmpty);
    });

    test('歸零前先把最終名次與分數寫入歷史紀錄', () {
      final s = AppState();
      final score = s.weeklyScore;
      expect(score, greaterThan(0));
      s.advanceDemoClock(const Duration(days: 8));
      final row = s.leaderboardHistory
          .firstWhere((h) => h.board == Board.personalWeekly);
      expect(row.score, score, reason: '寫進歷史的是歸零前的分數');
      expect(row.place, greaterThan(0));
    });

    test('經驗值不受排行榜重置影響 —— 兩者是不同數值', () {
      final s = AppState();
      final exp = s.totalExp;
      s.advanceDemoClock(const Duration(days: 40));
      expect(s.totalExp, exp);
    });
  });
}
