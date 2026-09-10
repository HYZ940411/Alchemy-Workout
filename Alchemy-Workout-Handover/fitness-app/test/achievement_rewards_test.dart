import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

List<Achievement> _of(String cat) =>
    buildAchievements().where((a) => a.category == cat).toList();

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('階級成就 5 枚，門檻 10 / 25 / 45 / 70 / 99', () {
    final rank = _of('階級');

    test('枚數與門檻', () {
      expect(rank.length, 5);
      expect(rank.map((a) => a.threshold), [10, 25, 45, 70, 99]);
    });

    test('金幣 100 → 500 遞增', () {
      expect(rank.map((a) => a.rewardCoins), [100, 200, 300, 400, 500]);
    });

    test('不給經驗值 —— 否則形成升階得經驗值再升階的循環', () {
      expect(rank.every((a) => a.rewardExp == 0), isTrue);
    });

    test('領取時真的不加經驗值', () {
      final s = AppState();
      final a = s.achievements
          .firstWhere((a) => a.category == '階級' && a.unlocked && !a.claimed);
      final exp = s.totalExp;
      final coins = s.coins;
      s.claimAchievement(a);
      expect(s.totalExp, exp);
      expect(s.coins, coins + a.rewardCoins);
    });
  });

  group('可刷的兩類一律 5 金幣、不遞增', () {
    test('互動四種各 9 枚，合計 36 枚', () {
      expect(kInteractionKinds.length, 4);
      for (final k in kInteractionKinds) {
        expect(_of(k).length, 9, reason: '$k 應為 9 枚');
        expect(_of(k).every((a) => a.rewardCoins == 5), isTrue);
      }
      final total = kInteractionKinds.fold(0, (n, k) => n + _of(k).length);
      expect(total, 36);
    });

    test('粉絲成就 9 枚，一律 5 金幣', () {
      expect(_of('粉絲').length, 9);
      expect(_of('粉絲').every((a) => a.rewardCoins == 5), isTrue);
    });

    test('經驗值照給且可遞增 —— 經驗值不影響金幣經濟', () {
      final e = _of('按讚').map((a) => a.rewardExp).toList();
      expect(e.first, lessThan(e.last));
    });
  });

  group('刷不動的五類 20 → 60 遞增', () {
    for (final cat in ['連簽', '累簽', '連續訓練', '累積訓練']) {
      test('$cat 為 20 → 60', () {
        final c = _of(cat).map((a) => a.rewardCoins).toList();
        expect(c.length, 9);
        expect(c.first, 20);
        expect(c.last, 60);
        for (var i = 1; i < c.length; i++) {
          expect(c[i], greaterThan(c[i - 1]));
        }
      });
    }

    test('新手成就只有 1 枚，取該類上緣 60', () {
      // 新手任務三選一、做一次就結束，一個布林事實撐不起 9 個遞增門檻。
      final n = _of('新手任務');
      expect(n.length, 1);
      expect(n.single.rewardCoins, 60);
      expect(n.single.threshold, 1);
    });

    test('能力值 12 枚，100 → 300 遞增（最難刷，給雙倍）', () {
      final c = _of('能力值').map((a) => a.rewardCoins).toList();
      expect(c.length, 12);
      expect(c.first, 100);
      expect(c.last, 300);
    });
  });

  group('互動成就的計數', () {
    test('每日上限只擋獎勵發放，不擋成就計數', () {
      final s = AppState();
      final cap = platformConfig.i('reward', 'capLike');
      final before = s.interactionTotals['按讚']!;
      // **逐篇不同的貼文**：按讚獎勵的請求識別碼為 貼文 ID ＋ 互動者 ID，
      // 同一篇反覆按只發一次，拿它來測每日上限測不出東西。
      final posts = _seedOthersPosts(s, cap + 3);
      for (final p in posts) {
        s.toggleLike(p);
      }
      expect(posts.length, greaterThan(cap), reason: '測試本身要按超過上限才有意義');
      expect(s.interactionTotals['按讚'], before + posts.length,
          reason: '成就計數不受每日上限影響');
      expect(s.interactionsToday('Like'), cap, reason: '獎勵發放仍停在上限');
    });

    test('同一篇按讚 → 取消 → 再按，獎勵只發一次', () {
      final s = AppState();
      final p = _seedOthersPosts(s, 1).single;
      final exp0 = s.totalExp;
      s.toggleLike(p);
      final gained = s.totalExp - exp0;
      expect(gained, greaterThan(0), reason: '第一次按讚要真的發得出經驗值');

      final used = s.interactionsToday('Like');
      final totalBefore = s.interactionTotals['按讚']!;
      s.toggleLike(p); // 取消
      s.toggleLike(p); // 再按
      expect(s.totalExp, exp0 + gained,
          reason: '請求識別碼為 貼文 ID ＋ 互動者 ID —— 同一篇只發一次');
      expect(s.interactionsToday('Like'), used,
          reason: '沒發獎勵就不該吃掉每日上限的額度');
      expect(s.interactionTotals['按讚'], totalBefore + 1,
          reason: '成就計的是行為次數，與獎勵發放與否無關');
    });

    test('粉絲成就讀的是粉絲數本身', () {
      final s = AppState();
      expect(s.currentProgressFor('粉絲'), s.followerCount);
    });
  });

  group('全部拿完的金幣總額', () {
    // 模型〈全部拿完的金幣總額〉2026-09-04 重算為 5,625。
    // 各類的規則是明確的，總額是推導值 —— 此處驗規則，並把實算值釘住，
    // 任何一類的數額被改動時這裡會炸。
    test('各類加總為 5,625，與模型列出的各類規則一致', () {
      final all = buildAchievements();
      int sumOf(Iterable<String> cats) => all
          .where((a) => cats.contains(a.category))
          .fold(0, (n, a) => n + a.rewardCoins);

      expect(sumOf(['連簽', '累簽', '連續訓練', '累積訓練']), 1440);
      expect(sumOf(['新手任務']), 60);
      expect(sumOf(kInteractionKinds), 180);
      expect(sumOf(['粉絲']), 45);
      expect(sumOf(['能力值']), 2400);
      expect(sumOf(['階級']), 1500);
      expect(all.fold(0, (n, a) => n + a.rewardCoins), 5625);
    });

    test('成就共 99 枚', () {
      expect(buildAchievements().length, 99);
    });
  });

  _workoutCounters();
}

/// 累積訓練次數與天數並存不合併

/// 累積訓練次數與天數並存不合併（〈訓練類成就的門檻計數單位〉）。
void _workoutCounters() {
  group('累積訓練次數與天數是兩個欄位', () {
    /// 假使用者今天已經練過（[lastTrainedDate] 就是今天），
    /// 先把它挪到昨天，本日的第一場才算得出「天數 +1」。
    AppState fresh() =>
        AppState()..lastTrainedDate = businessDate(DateTime.now())
            .subtract(const Duration(days: 1));

    AppState practiced(AppState s) {
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      return s;
    }

    test('一日兩場：次數 +2、天數 +1', () {
      final s = fresh();
      final n = s.totalWorkouts;
      final d = s.totalWorkoutDays;
      practiced(s);
      practiced(s);
      expect(s.totalWorkouts, n + 2, reason: '次數計場次');
      expect(s.totalWorkoutDays, d + 1, reason: '天數一日只計 1');
    });

    test('跨日兩場：兩者都 +2', () {
      final s = fresh();
      final n = s.totalWorkouts;
      final d = s.totalWorkoutDays;
      practiced(s);
      s.advanceDemoClock(const Duration(days: 1));
      practiced(s);
      expect(s.totalWorkouts, n + 2);
      expect(s.totalWorkoutDays, d + 2);
    });

    test('累積訓練成就讀天數，不讀次數', () {
      final s = AppState();
      s.totalWorkouts = 999;
      s.totalWorkoutDays = 7;
      expect(s.currentProgressFor('累積訓練'), 7);
    });

    test('成就門檻不能靠一日連開多場刷完', () {
      final s = fresh();
      s.totalWorkoutDays = 0;
      final before = s.currentProgressFor('累積訓練');
      for (var i = 0; i < 5; i++) {
        practiced(s);
      }
      expect(s.totalWorkouts, greaterThanOrEqualTo(5));
      expect(s.currentProgressFor('累積訓練'), before + 1,
          reason: '同一天練五場，成就只前進 1');
    });

    test('教官初審門檻用的是次數，不是天數', () {
      final s = AppState();
      s.totalWorkouts = 0;
      s.totalWorkoutDays = 999;
      final low = s.instructorGate.workoutsOk;
      s.totalWorkouts = 999;
      s.totalWorkoutDays = 0;
      expect(s.instructorGate.workoutsOk, isTrue);
      expect(low, isFalse, reason: '天數再多也不該讓教官門檻過關');
    });

    test('成就名稱寫的是「天」不是「次」', () {
      final names = buildAchievements()
          .where((a) => a.category == '累積訓練')
          .map((a) => a.name);
      expect(names.every((n) => n.endsWith('天')), isTrue);
    });
  });
}


/// 造 [n] 篇他人的貼文。按讚獎勵逐篇去重，測上限就得有夠多篇。
List<Post> _seedOthersPosts(AppState s, int n) {
  final made = <Post>[];
  for (var i = 0; i < n; i++) {
    final p = Post(
      id: 'seed-$i',
      author: '路人$i',
      authorRank: 20,
      text: '第 $i 篇',
      at: s.now,
    );
    s.posts.insert(0, p);
    made.add(p);
  }
  return made;
}
