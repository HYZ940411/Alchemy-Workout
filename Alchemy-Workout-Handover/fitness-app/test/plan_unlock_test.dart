import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rank.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan _advanced(AppState s) =>
    s.platformPlans.firstWhere((p) => p.unlockCoins != null);

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('進階訓練計畫的三種解鎖方式為 OR 關係', () {
    test('初階計畫（所需階級為空）恆為已解鎖', () {
      final s = AppState();
      final basic = s.platformPlans.firstWhere((p) => p.requiredRank == null);
      expect(s.planUnlocked(basic), isTrue);
    });

    test('方式 1 階級達標', () {
      final s = AppState();
      final p = _advanced(s);
      expect(s.planUnlocked(p), isFalse);
      s.totalExp = expThresholdForRank(p.requiredRank!);
      expect(s.planUnlocked(p), isTrue);
    });

    test('方式 2 金幣購買', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      expect(s.planUnlocked(p), isFalse);
      expect(s.purchasePlan(p), isNull);
      expect(s.planUnlocked(p), isTrue);
      expect(s.purchasedPlanIds, contains(p.id));
    });

    test('方式 3 會員身分，且權益失效即回退', () {
      final s = AppState();
      final p = _advanced(s);
      s.subscribe(yearly: false);
      expect(s.planUnlocked(p), isTrue);
      s.membership = MembershipState.none;
      expect(s.planUnlocked(p), isFalse, reason: '僅靠會員解鎖者，權益失效即鎖回');
    });

    test('金幣購買者不因會員權益失效而回退', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.subscribe(yearly: false);
      s.purchasePlan(p);
      s.membership = MembershipState.none;
      expect(s.planUnlocked(p), isTrue, reason: '方式 2 為永久取得');
    });
  });

  group('不得重複購買', () {
    test('階級已達標者不得購買', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.totalExp = expThresholdForRank(p.requiredRank!);
      expect(s.planPurchaseBlockedReason(p), isNotNull);
      expect(s.purchasePlan(p), FailReason.other);
      expect(s.coins, 10000, reason: '被擋下就不該扣款');
    });

    test('已購買者不得再買', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.purchasePlan(p);
      final after = s.coins;
      expect(s.planPurchaseBlockedReason(p), isNotNull);
      expect(s.purchasePlan(p), FailReason.other);
      expect(s.coins, after);
    });

    test('僅以會員身分解鎖者仍可購買，用途為轉為永久取得', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.subscribe(yearly: false);
      expect(s.planMemberOnly(p), isTrue);
      expect(s.planPurchaseBlockedReason(p), isNull);
      expect(s.purchasePlan(p), isNull);
      expect(s.planMemberOnly(p), isFalse, reason: '買完就不只是會員解鎖了');
    });

    test('解鎖價格為空值者不可購買', () {
      final s = AppState();
      final p = s.platformPlans.firstWhere(
          (p) => p.requiredRank != null && p.unlockCoins == null);
      expect(s.planPurchaseBlockedReason(p), isNotNull);
    });
  });

  group('支付與發放', () {
    test('金幣足夠：全額以金幣支付，無補差額', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.purchasePlan(p);
      final o = s.orders.first;
      expect(o.coinPaid, p.unlockCoins);
      expect(o.cashPaid, 0);
      expect(s.coins, 10000 - p.unlockCoins!);
    });

    test('金幣不足：扣光金幣，其餘以現金補差額', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 100;
      s.purchasePlan(p);
      final o = s.orders.first;
      expect(o.coinPaid, 100);
      expect(o.cashPaid, cashForShortfall(p.unlockCoins! - 100));
      expect(s.coins, 0, reason: '金幣餘額扣除後不得為負值');
    });

    test('權限解鎖類不適用庫存，交易成立即發放', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.purchasePlan(p);
      final o = s.orders.first;
      expect(o.state, OrderState.delivered);
    });
  });

  group('統一定價 600 金幣，為平台級可調參數', () {
    test('預設值為 600（＝120 元）', () {
      expect(kPlanUnlockCoins, 600);
      expect(kPlanUnlockCoins / kCoinsPerNtd, 120);
    });

    test('進階計畫的解鎖價格不逐計畫自訂，取統一定價', () {
      final s = AppState();
      for (final p in s.platformPlans.where((p) => p.unlockCoins != null)) {
        expect(p.unlockCoins, kPlanUnlockCoins);
      }
    });

    test('不變條件擋下非正數的價格', () {
      final g = platformConfig.group('commerce');
      expect(g.invariant!({...g.values, 'planUnlockCoins': 0}), isNotNull);
      expect(g.invariant!(g.values), isNull);
    });
  });

  group('重新整理後仍成立（存檔來回一趟）', () {
    AppState reload(AppState s) {
      final back = AppState();
      expect(back.applySnapshot(s.toSnapshot()), isTrue);
      return back;
    }

    test('金幣購買：重新整理後仍解鎖，金幣只扣一次', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 1000;
      s.purchasePlan(p);
      final coinsAfter = s.coins;
      expect(coinsAfter, 1000 - p.unlockCoins!);

      final back = reload(s);
      expect(back.planUnlocked(_advanced(back)), isTrue);
      expect(back.coins, coinsAfter, reason: '重新整理不能多扣也不能退回');
      expect(back.purchasedPlanIds, contains(p.id));
    });

    test('會員：重新整理後仍有效；到期後鎖回', () {
      final s = AppState();
      final p = _advanced(s);
      s.subscribe(yearly: false);
      expect(s.planUnlocked(p), isTrue);

      final back = reload(s);
      expect(back.isMember, isTrue);
      expect(back.planUnlocked(_advanced(back)), isTrue);

      addTearDown(resetAppClock);
      back.advanceDemoClock(const Duration(days: 32));
      expect(back.isMember, isFalse);
      expect(back.planUnlocked(_advanced(back)), isFalse,
          reason: '僅靠會員解鎖者到期鎖回');

      final again = reload(back);
      expect(again.planUnlocked(_advanced(again)), isFalse,
          reason: '鎖回的狀態重新整理後不能又被打開');
    });

    test('自己買過的：會員到期、重新整理之後都不被鎖', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.subscribe(yearly: false);
      s.purchasePlan(p);

      final back = reload(s);
      addTearDown(resetAppClock);
      back.advanceDemoClock(const Duration(days: 32));
      expect(back.isMember, isFalse);
      expect(back.planUnlocked(_advanced(back)), isTrue);

      final again = reload(back);
      expect(again.planUnlocked(_advanced(again)), isTrue);
    });
  });

  group('後台改課表的階級與價格（setPlanConfig）', () {
    test('前台跟著變：所需階級與解鎖價格都用新的', () {
      final s = AppState();
      s.adminMode = true;
      final p = _advanced(s);
      expect(s.setPlanConfig(p, requiredRank: 70, unlockCoins: 250), isNull);
      final q = s.platformPlans.firstWhere((x) => x.id == p.id);
      expect(q.requiredRank, 70);
      expect(q.unlockCoins, 250);

      s.coins = 1000;
      expect(s.purchasePlan(q), isNull);
      expect(s.coins, 1000 - 250, reason: '用新價格扣');
    });

    test('改階級或價格不能洗掉這份課表的其他欄位', () {
      final s = AppState();
      s.adminMode = true;
      final p = _advanced(s);
      expect(p.suitableExperience, isNotEmpty, reason: '前提：這份課表有填適合的經驗');
      s.setPlanConfig(p, requiredRank: 70, unlockCoins: 250);
      final q = s.platformPlans.firstWhere((x) => x.id == p.id);
      expect(q.suitableExperience, p.suitableExperience);
      expect(q.suitableGoals, p.suitableGoals);
      expect(q.equipmentTier, p.equipmentTier);
      expect(q.memberUnlockable, p.memberUnlockable);
    });

    test('規格也同步改，下次載入雲端資料不會被洗掉', () {
      final s = AppState();
      s.adminMode = true;
      final p = _advanced(s);
      s.setPlanConfig(p, requiredRank: 70, unlockCoins: 250);
      expect(s.planSpecById[p.id]!.requiredRank, 70);
      expect(s.planSpecById[p.id]!.unlockCoins, 250);
    });
  });
}
