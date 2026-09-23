import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/decay.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

/// 距今 [daysAgo] 個**營業日**的一天。
///
/// **不可以寫成 `s.now.subtract(...)`。** 換日時點是當地 04:00，所以
/// 00:00–03:59 這四個小時裡 `businessDate(now)` 還停在前一天，而
/// `now.subtract()` 算的是日曆日 —— 兩者差一天，`daysAgo` 就少一。
/// 那會讓這個檔案的測試**只在凌晨紅**，白天怎麼跑都是綠的。
///
/// `app_state.dart` 的 `daysAgo` 註解講的正是這一類漏洞（它說那是
/// 最後一處，其實漏了測試自己）；2026-09-24 00:18 的一次執行照出來。
MakeupDay _missed(AppState s, int daysAgo) => MakeupDay(
      businessDate(s.now).subtract(Duration(days: daysAgo)),
      MakeupDayState.missed,
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('補簽券持有上限 5 張，無有效期限', () {
    test('預設上限為 5', () {
      expect(AppState().makeupTicketCap, 5);
    });

    test('入手到上限就停', () {
      final s = AppState();
      s.makeupTickets = 0;
      expect(s.grantMakeupTickets(3), 3);
      expect(s.grantMakeupTickets(5), 2, reason: '只補到上限');
      expect(s.makeupTickets, 5);
      expect(s.grantMakeupTickets(1), 0);
    });

    test('達上限者不得再購買', () {
      final s = AppState();
      s.makeupTickets = s.makeupTicketCap;
      s.coins = 99999;
      final coins = s.coins;
      expect(s.buyMakeupTicket(), isNotNull);
      expect(s.coins, coins, reason: '被擋下就不該扣款');
    });

    test('未達上限且金幣足夠即可購買', () {
      final s = AppState();
      s.makeupTickets = 1;
      s.coins = 1000;
      expect(s.buyMakeupTicket(), isNull);
      expect(s.makeupTickets, 2);
      expect(s.coins, 1000 - s.makeupTicketPrice);
    });

    test('金幣不足時不扣券也不扣款', () {
      final s = AppState();
      s.makeupTickets = 1;
      s.coins = 0;
      expect(s.buyMakeupTicket(), isNotNull);
      expect(s.makeupTickets, 1);
    });

    test('上限只擋新入手，不沒收已持有的', () {
      final s = AppState();
      s.makeupTickets = 5;
      platformConfig.group('makeup').param('ticketCap').value = 2;
      expect(s.makeupTickets, 5, reason: '手上的券不因上限調低而消失');
      expect(s.grantMakeupTickets(1), 0);
    });
  });

  group('補簽券售價', () {
    test('預設 150 金幣 ＝ 四天份簽到金幣 ＋ 四天份訓練金幣', () {
      final s = AppState();
      expect(s.makeupTicketPrice, 150);
      final checkIn = platformConfig.i('reward', 'checkInCoin');
      final train = platformConfig.i('reward', 'trainCoin');
      expect(4 * checkIn + 4 * train, 160);
      expect(s.makeupTicketPrice, closeTo(160, 15));
    });

    test('不變條件擋下低於單日簽到獎勵的售價', () {
      final g = platformConfig.group('makeup');
      final checkIn = platformConfig.i('reward', 'checkInCoin');
      expect(g.invariant!({...g.values, 'ticketPrice': checkIn}), isNotNull,
          reason: '會形成「買券 → 補簽 → 拿回更多金幣」的套利迴圈');
      expect(g.invariant!({...g.values, 'ticketPrice': checkIn + 1}), isNull);
      expect(g.invariant!(g.values), isNull);
    });

    test('不變條件擋下非正數的持有上限', () {
      final g = platformConfig.group('makeup');
      expect(g.invariant!({...g.values, 'ticketCap': 0}), isNotNull);
    });
  });

  group('補簽日期 ≥ 註冊日', () {
    test('註冊日之前的日期不可補 —— 補不回還不存在的那些天', () {
      final s = AppState();
      s.makeupTickets = 3;
      // 三天前才註冊：五天前雖在回補範圍內，卻早於註冊日。
      s.registeredOn = businessDate(s.now.subtract(const Duration(days: 3)));
      final before = _missed(s, 5);
      expect(s.daysAgo(before.date) <= s.makeupRangeDays, isTrue,
          reason: '這一天本身在回補範圍內，擋下它的必須是註冊日這條');
      expect(s.canMakeUp(before), isFalse);
      expect(s.makeupBlockedReason(before), contains('註冊'));
    });

    test('註冊日當日可補', () {
      final s = AppState();
      s.makeupTickets = 3;
      s.registeredOn = businessDate(s.now.subtract(const Duration(days: 3)));
      final onRegistrationDay = MakeupDay(s.registeredOn, MakeupDayState.missed);
      expect(s.canMakeUp(onRegistrationDay), isTrue);
    });
  });

  group('其餘 Precondition 各自檢核', () {
    test('已簽到的日期不可補', () {
      final s = AppState();
      s.makeupTickets = 3;
      final d = MakeupDay(
        s.now.subtract(const Duration(days: 2)),
        MakeupDayState.signed,
      );
      expect(s.canMakeUp(d), isFalse);
    });

    test('超出回補範圍不可補，端點含在內', () {
      final s = AppState();
      s.makeupTickets = 3;
      final range = s.makeupRangeDays;
      expect(s.canMakeUp(_missed(s, range)), isTrue, reason: '距今第 N 天仍可補');
      expect(s.canMakeUp(_missed(s, range + 1)), isFalse);
    });

    test('沒有補簽券就不可補', () {
      final s = AppState();
      s.makeupTickets = 0;
      expect(s.canMakeUp(_missed(s, 2)), isFalse);
      expect(s.makeupBlockedReason(_missed(s, 2)), contains('補簽券'));
    });
  });

  _lastTrained();
}

/// 上次訓練日期不允許空值

/// 上次訓練日期不允許空值，初始值為註冊日 —— 四道門檻自註冊日的日界起算。
void _lastTrained() {
  group('上次訓練日期不允許空值', () {
    test('初始值為註冊日', () {
      final s = AppState();
      expect(s.initialLastTrainedDate, s.registeredOn);
    });

    test('從未訓練者的四道門檻自註冊日的日界起算', () {
      final s = AppState();
      s.lastTrainedDate = s.initialLastTrainedDate;
      // 註冊日在 180 天前，遠超 240 小時。
      expect(hoursSinceBoundary(s.lastTrainedDate, s.now),
          greaterThan(kDecayIntervalHours));
    });

    test('與已訓練者共用同一套規則，不必為「還沒練過」另寫分支', () {
      final s = AppState();
      s.lastTrainedDate = businessDate(s.now.subtract(const Duration(days: 1)));
      final trained = hoursSinceBoundary(s.lastTrainedDate, s.now);
      s.lastTrainedDate = s.initialLastTrainedDate;
      final never = hoursSinceBoundary(s.lastTrainedDate, s.now);
      expect(never, greaterThan(trained));
    });

    test('連續天數：上次訓練非昨日者自 1 起算', () {
      final s = AppState();
      s.trainingStreakDays = 12;
      s.lastTrainedDate = businessDate(s.now.subtract(const Duration(days: 5)));
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.trainingStreakDays, 1);
    });

    test('連續天數：上次訓練為昨日者續計', () {
      final s = AppState();
      s.trainingStreakDays = 12;
      s.lastTrainedDate = businessDate(s.now.subtract(const Duration(days: 1)));
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.trainingStreakDays, 13);
    });
  });
}
