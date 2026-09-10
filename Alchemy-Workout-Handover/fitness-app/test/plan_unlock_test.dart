import 'package:flutter_test/flutter_test.dart';

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

    test('權限解鎖類不適用庫存，交易成立即發放，無預扣到期時點', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.purchasePlan(p);
      final o = s.orders.first;
      expect(o.kind, ProductKind.virtual);
      expect(o.state, OrderState.delivered);
      expect(o.holdUntil, isNull);
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
}
