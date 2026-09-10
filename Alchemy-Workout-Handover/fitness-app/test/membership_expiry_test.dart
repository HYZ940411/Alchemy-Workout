import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

WorkoutPlan _advanced(AppState s) =>
    s.platformPlans.firstWhere((p) => p.memberUnlockable);

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('取消不等於失效', () {
    test('取消後轉為已取消待到期，權益維持至當期到期日', () {
      final s = AppState();
      s.subscribe(yearly: false);
      s.cancelSubscription();
      expect(s.membership, MembershipState.cancelledPending);
      expect(s.isMember, isTrue, reason: '已支付整個當期，立即收回等同沒收');
      expect(s.planUnlocked(_advanced(s)), isTrue);
    });

    test('取消當下不觸發鎖定', () {
      final s = AppState();
      s.subscribe(yearly: false);
      s.cancelSubscription();
      expect(s.expireMembershipIfDue(), isEmpty);
      expect(s.membershipLockedPlanIds, isEmpty);
    });

    test('到期日一到，已取消待到期者才失效', () {
      final s = AppState();
      s.subscribe(yearly: false);
      s.cancelSubscription();
      s.advanceDemoClock(const Duration(days: 29));
      expect(s.isMember, isTrue);
      s.advanceDemoClock(const Duration(days: 2));
      expect(s.membership, MembershipState.expired);
      expect(s.isMember, isFalse);
    });
  });

  group('會員權益已失效 → 進階訓練計畫已鎖定', () {
    test('僅以會員身分解鎖者回鎖', () {
      final s = AppState();
      final p = _advanced(s);
      s.subscribe(yearly: false);
      expect(s.planUnlocked(p), isTrue);
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.planUnlocked(p), isFalse);
      expect(s.membershipLockedPlanIds, contains(p.id));
    });

    test('以金幣購買取得者不回鎖', () {
      final s = AppState();
      final p = _advanced(s);
      s.coins = 10000;
      s.subscribe(yearly: false);
      s.purchasePlan(p);
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.membership, MembershipState.expired);
      expect(s.planUnlocked(p), isTrue, reason: '方式 2 為永久取得');
      expect(s.membershipLockedPlanIds, isNot(contains(p.id)));
    });

    test('以階級達標取得者不回鎖', () {
      final s = AppState();
      final p = _advanced(s);
      s.subscribe(yearly: false);
      s.totalExp = 99999;
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.planUnlocked(p), isTrue);
      expect(s.membershipLockedPlanIds, isNot(contains(p.id)));
    });

    test('僅改變可選用性，不刪除任何資料', () {
      final s = AppState();
      final p = _advanced(s);
      s.subscribe(yearly: false);
      final historyBefore = s.history.length;
      final plansBefore = s.platformPlans.length;
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.history.length, historyBefore);
      expect(s.platformPlans.length, plansBefore);
      expect(s.platformPlans, contains(p));
    });

    test('續訂即回復原狀，不是從零開始', () {
      final s = AppState();
      final p = _advanced(s);
      s.subscribe(yearly: false);
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.planUnlocked(p), isFalse);
      s.subscribe(yearly: false);
      expect(s.membership, MembershipState.active,
          reason: '已失效非終止狀態，沿用同一筆會員權益');
      expect(s.planUnlocked(p), isTrue);
    });

    test('當前計畫正好被鎖掉時換成解得開的一份', () {
      final s = AppState();
      final p = _advanced(s);
      s.subscribe(yearly: false);
      s.currentPlan = p;
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.currentPlan, isNot(p));
      expect(s.planUnlocked(s.currentPlan!), isTrue);
    });
  });

  group('權益與已取得的資源要分開', () {
    test('補簽券不作廢，失效後仍可使用', () {
      final s = AppState();
      s.subscribe(yearly: false);
      final tickets = s.makeupTickets;
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.makeupTickets, tickets,
          reason: '補簽券是已發放給使用者的物品，收回等同溯及既往');
    });

    test('AI 月度額度歸零，但永久點數不動', () {
      final s = AppState();
      s.subscribe(yearly: false);
      final permanent = s.aiPermanent;
      expect(s.aiMonthly, greaterThan(0));
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.aiMonthly, 0);
      expect(s.aiPermanent, permanent, reason: '永久點數不重置不過期');
    });
  });

  group('結算是冪等的', () {
    test('重複呼叫不重複鎖定，也不改變狀態', () {
      final s = AppState();
      s.subscribe(yearly: false);
      s.advanceDemoClock(const Duration(days: 31));
      final locked = [...s.membershipLockedPlanIds];
      expect(s.expireMembershipIfDue(), isEmpty);
      expect(s.membershipLockedPlanIds, locked);
    });

    test('結算還沒跑到，權益也已經是失效的', () {
      final s = AppState();
      s.subscribe(yearly: false);
      // 只推時鐘，不跑結算 —— 權益的有無看的是時間，不是排程跑了沒。
      s.demoClockOffset = const Duration(days: 31);
      expect(s.membership, MembershipState.active, reason: '狀態尚未結算');
      expect(s.isMember, isFalse);
      expect(s.planUnlocked(_advanced(s)), isFalse);
    });

    test('從未訂閱者不受影響', () {
      final s = AppState();
      expect(s.membership, MembershipState.none);
      s.advanceDemoClock(const Duration(days: 400));
      expect(s.membership, MembershipState.none);
      expect(s.expireMembershipIfDue(), isEmpty);
    });
  });
}
