// 新帳號不該帶著退步的假資料（2026-09-24）。
//
// 使用者回報「能力值退步狀態的資料，能力值已退步是不是有假資料」。是。
//
// `decayTimers` 與 `registeredOn` **沒有 `demo` 開關** —— 旁邊的
// `posts`／`socialUsers`／`instructors`／`mentorTasks` 全都是
// `demo ? buildX() : []`，只有這兩個漏掉。於是 `AppState(demo: false)`
// 一建出來就帶著：
//
//   registeredOn = 180 天前（寫死）
//   肩累積退步 14、手 31、核心 37，decayLog 7 筆
//
// 2026-09-16 那次假資料清查（`[QA-02a]`–`[QA-02e]`）清的是**集合類**，
// 這兩個是純量與計時器，所以被漏掉。
//
// `resetToNewAccount()` 會修正它們，但那只在完成註冊流程時跑；
// 存檔缺 `decayTimers` 這個鍵時（舊存檔）那份假資料就會留著。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('非示範帳號', () {
    test('註冊日是今天，不是寫死的 180 天前', () {
      final s = AppState(demo: false);
      expect(s.registeredOn, businessDate(DateTime.now()));
    });

    test('六個退步計時器都自註冊日起算', () {
      final s = AppState(demo: false);
      for (final d in Dim.values) {
        expect(s.decayTimers[d]!.lastTrainedDate, s.registeredOn,
            reason: '${d.name} 的最後訓練日應為註冊日');
      }
    });

    test('沒有任何累積退步量', () {
      final s = AppState(demo: false);
      for (final d in Dim.values) {
        expect(s.decayTimers[d]!.cumulative, 0, reason: d.name);
      }
    });

    test('退步流水是空的 —— 這是使用者實際看到的那一頁', () {
      final s = AppState(demo: false);
      // 改之前這裡是 7 筆：肩 14、手 31、核心 37 的退步紀錄。
      expect(s.decayLog, isEmpty);
    });

    test('跑一次退步判定也不會退 —— 才剛註冊', () {
      final s = AppState(demo: false);
      expect(s.runDecayCheck(), isEmpty);
      expect(s.decayLog, isEmpty);
    });
  });

  group('示範身分維持原樣', () {
    test('六個計時器刻意錯開，才演得出各自的門檻', () {
      final s = AppState();
      final days = {
        for (final d in Dim.values)
          d: businessDate(DateTime.now())
              .difference(s.decayTimers[d]!.lastTrainedDate)
              .inDays,
      };
      // 胸今天、背 2 天、腿 5 天、肩 12 天、手 26 天、核心 46 天
      expect(days[Dim.chest], 0);
      expect(days[Dim.core], 46);
      expect(days.values.toSet(), hasLength(6), reason: '六個都不一樣才錯得開');
    });

    test('示範身分才有退步流水', () {
      expect(AppState().decayLog, isNotEmpty);
    });
  });

  _dailyTaskCoins();
}

/// 每日任務的加碼金幣（2026-09-24）
///
/// 使用者回報「完成每日任務沒有得到經驗值跟金幣」。查證後：
///
///   · **經驗值本來就不給** —— `platform_config` 的獎勵參數裡，簽到、訓練、
///     新手任務、回歸任務、排行榜都有各自的 Exp，唯獨每日任務只有金幣。
///     〈每日任務流程〉也只提排行榜分數。使用者裁決維持不給。
///   · **金幣有給，但少了加碼那 4 枚** —— 它只掛在「領取全部」那顆按鈕上，
///     一項一項點的人一天只拿到 6 金幣，而規格是 10
///     （〈02_Aggregate定義〉每日任務 300／月）。
void _dailyTaskCoins() {
  group('每日任務的加碼金幣', () {
    /// 把三項都做到完成。
    void finishAll(AppState s) {
      for (final t in s.dailyTasks) {
        t.progress = t.target;
      }
    }

    test('一項一項領，也拿得到全部完成的加碼', () {
      final s = AppState(demo: false);
      finishAll(s);
      final before = s.coins;

      for (final t in s.dailyTasks.toList()) {
        s.claimTask(t);
      }

      // 2×3 ＋ 4 ＝ 10／日，與規格相符。
      expect(s.coins - before, kDailyTaskCoin * s.dailyTasks.length + kDailyTaskAllDoneCoin);
    });

    test('「領取全部」拿到的一樣多', () {
      final s = AppState(demo: false);
      finishAll(s);
      final before = s.coins;

      s.claimAllTasks();

      expect(s.coins - before, kDailyTaskCoin * s.dailyTasks.length + kDailyTaskAllDoneCoin);
    });

    test('加碼只發一次', () {
      final s = AppState(demo: false);
      finishAll(s);
      s.claimAllTasks();
      final after = s.coins;

      s.claimAllTasks();
      for (final t in s.dailyTasks.toList()) {
        s.claimTask(t);
      }

      expect(s.coins, after);
    });

    test('沒有全部完成就沒有加碼', () {
      final s = AppState(demo: false);
      final t = s.dailyTasks.first;
      t.progress = t.target;
      final before = s.coins;

      s.claimTask(t);

      expect(s.coins - before, kDailyTaskCoin, reason: '只有那一項的金幣');
    });

    test('每日任務不給經驗值（使用者裁決 2026-09-24）', () {
      final s = AppState(demo: false);
      finishAll(s);
      final before = s.totalExp;
      s.claimAllTasks();
      expect(s.totalExp, before);
    });
  });
}
