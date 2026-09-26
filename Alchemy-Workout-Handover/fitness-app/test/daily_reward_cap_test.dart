import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

SettlementRewards _r(
  EndKind kind, {
  PlanSource source = PlanSource.official,
  int coinsGrantedToday = 0,
  int scoreGrantedToday = 0,
  int streakDays = 0,
}) =>
    computeSettlement(
      kind: kind,
      source: source,
      doneSets: kind == EndKind.completed ? 10 : 5,
      plannedSets: 10,
      streakDays: streakDays,
      expAlreadyGrantedToday: false,
      coinsGrantedToday: coinsGrantedToday,
      scoreGrantedToday: scoreGrantedToday,
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('訓練獎勵金幣每日最多發放一次', () {
    test('當日第一場全額發放', () {
      final r = _r(EndKind.completed);
      expect(r.coins, 30);
      expect(r.coinsEntitled, 30);
      expect(r.coinsCapped, isFalse);
    });

    test('同日第二場完成度相同：一毛都不發', () {
      final r = _r(EndKind.completed, coinsGrantedToday: 30);
      expect(r.coins, 0);
      expect(r.coinsEntitled, 30, reason: '應得仍要算出來，畫面得說明為什麼是 0');
      expect(r.coinsCapped, isTrue);
    });

    test('同日第二場完成度更低：仍然不發，不會倒扣', () {
      final r = _r(EndKind.endedEarly, coinsGrantedToday: 30);
      expect(r.coins, 0);
      expect(r.coinsEntitled, 21);
    });

    test('同日第二場完成度更高：補發差額，補至上限即止', () {
      // 先提前結束（70%）拿 21，再完成一場（100%）應得 30 → 只補 9。
      final first = _r(EndKind.endedEarly);
      expect(first.coins, 21);
      final second = _r(EndKind.completed, coinsGrantedToday: first.coins);
      expect(second.coins, 30 - 21);
      expect(second.coinsCapped, isTrue, reason: '拿到的少於本場應得');
    });

    test('補到上限後第三場再無金幣', () {
      final third = _r(EndKind.completed, coinsGrantedToday: 30);
      expect(third.coins, 0);
    });

    test('連續加成後的上限也是同一條：39 補滿就停', () {
      final a = _r(EndKind.endedEarly, streakDays: 50);
      expect(a.coins, (30 * 0.7 * 1.3).round());
      final b = _r(EndKind.completed, streakDays: 50, coinsGrantedToday: a.coins);
      expect(a.coins + b.coins, 39);
    });
  });

  group('個人排行榜分數每日最多計分一次，取當日最高並補發差額', () {
    test('同日第二場完成度更高只補差額', () {
      final a = _r(EndKind.endedEarly);
      expect(a.leaderboardScore, 70);
      final b = _r(EndKind.completed, scoreGrantedToday: a.leaderboardScore!);
      expect(b.leaderboardScore, 30);
      expect(b.leaderboardScoreEntitled, 100);
      expect(b.scoreCapped, isTrue);
    });

    test('同日第二場完成度不變則不計分', () {
      final b = _r(EndKind.completed, scoreGrantedToday: 100);
      expect(b.leaderboardScore, 0);
    });

    test('空白課表兩個欄位都是 null，不受上限邏輯影響', () {
      final b = _r(EndKind.completed,
          source: PlanSource.blank, scoreGrantedToday: 100);
      expect(b.leaderboardScore, isNull);
      expect(b.leaderboardScoreEntitled, isNull);
      expect(b.scoreCapped, isFalse);
    });
  });

  group('上限不約束其他指標', () {
    test('同日第二場：金幣 0 分數 0，但能力值、累積次數、連續天數照舊', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 10));
      final first = s.finishWorkout(EndKind.completed);
      final workouts = s.totalWorkouts;
      final days = s.totalWorkoutDays;
      final streak = s.trainingStreakDays;
      final coins = s.coins;
      final weekly = s.weeklyScore;

      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 10));
      final second = s.finishWorkout(EndKind.completed);

      expect(second.rewards.coins, 0);
      expect(s.coins, coins, reason: '金幣沒有再入帳');
      expect(second.rewards.leaderboardScore, 0);
      expect(s.weeklyScore, weekly);
      // 而這些不受上限約束：
      expect(s.trainingStreakDays, streak, reason: '同一天訓練多次仍計 1 天');
      // 次數每場都加、天數一日只加一次 —— 兩者並存不合併。
      expect(s.totalWorkouts, workouts + 1, reason: '累積訓練次數計場次');
      expect(s.totalWorkoutDays, days, reason: '累積訓練天數一日只計 1');
      expect(second.pointsAfter, isNotEmpty);
      expect(first.rewards.coins, greaterThan(0));
    });

    test('AppState 的當日計數在換日後歸零', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 10));
      s.finishWorkout(EndKind.completed);
      expect(s.maxCompletionToday, 1.0);

      s.advanceDemoClock(const Duration(days: 1));
      expect(s.maxCompletionToday, 0, reason: '換日即歸零');

      final coins = s.coins;
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 10));
      final r = s.finishWorkout(EndKind.completed);
      expect(r.rewards.coins, greaterThan(0));
      expect(s.coins, greaterThan(coins));
    });
  });
}
