import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rank.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/mock/mock_data.dart';

/// n 個動作的最小課表，供不關心內容的測試使用。
List<PlanExercise> plannedOf(int n) => [
      for (var i = 0; i < n; i++)
        PlanExercise(
          exercise: kExercises[i % kExercises.length],
          planned: const [PlannedSet(20, 10)],
        ),
    ];

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('分組鎖定：週期中新加入者於首次計分時鎖定', () {
    test('剛註冊者尚未鎖定組別', () {
      final s = AppState();
      s.signUpDraft
        ..nickname = '阿昶'
        ..heightCm = 170
        ..weightKg = 65
        ..gender = '男'
        ..birthday = DateTime(2000, 1, 1)
        ..commonGoal = '增肌'
        ..experience = '新手（未滿 6 個月）'
        ..daysPerWeek = 3
        ..duration = '30–60 分鐘'
        ..equipment.add('徒手');
      s.completeSignUp();
      expect(s.lockedRankGroup, isNull);
      expect(s.lockedMonthlyGroup, isNull);
    });

    test('尚未鎖定時，呈現用的組別退回當前階級', () {
      final s = AppState();
      s.lockedRankGroup = null;
      expect(s.rankGroupNow(weekly: true), rankGroupOf(s.rank));
    });

    test('首次計分時鎖定當下階級', () {
      final s = AppState();
      s.lockedRankGroup = null;
      s.lockedMonthlyGroup = null;
      final atScoring = rankGroupOf(s.rank);
      s.checkIn(); // 推進每日任務 → 個人排行榜分數已增加
      expect(s.lockedRankGroup, atScoring);
      expect(s.lockedMonthlyGroup, atScoring);
    });

    test('週期內升階不改變本週期所屬組別', () {
      final s = AppState();
      s.lockedRankGroup = null;
      s.checkIn();
      final locked = s.lockedRankGroup;
      s.totalExp = expThresholdForRank(90); // 期中大幅升階
      expect(s.rank, greaterThanOrEqualTo(90));
      expect(s.lockedRankGroup, locked, reason: '本週期組別不因升階而變');
    });

    test('新組別自下一週期起生效', () {
      final s = AppState();
      s.checkIn();
      s.totalExp = expThresholdForRank(90);
      final old = s.lockedRankGroup;
      s.advanceDemoClock(const Duration(days: 8)); // 跨過週一
      expect(s.lockedRankGroup, isNot(old));
      expect(s.lockedRankGroup, rankGroupOf(s.rank));
    });
  });

  group('商品下架連帶取消待付款訂單', () {
    test('使用者端的待付款訂單一起取消並釋放庫存', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.kind == ProductKind.physical);
      final spec = p.specs.firstWhere((x) => x.inStock);
      final stock = spec.stock;
      s.coins = 99999;
      expect(s.confirmPurchase(p, spec, 1, shipping: s.lastShipping), isNull);
      final order = s.orders.first;
      expect(order.state, OrderState.pendingPayment);
      expect(spec.stock, stock - 1, reason: '確認購買時預扣庫存');

      final admin = s.adminProducts.firstWhere((a) => a.name == p.name);
      s.adminMode = true;
      s.delistProduct(admin);

      expect(order.state, OrderState.cancelled,
          reason: '後台已取消，使用者那一側不該還停在待付款');
      expect(order.cancelledBySystem, isTrue, reason: 'Actor 為系統，非使用者');
      expect(spec.stock, stock, reason: '預扣的庫存回補');
    });

    test('已付款而未出貨者照常履行，不被下架取消', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.kind == ProductKind.physical);
      final spec = p.specs.firstWhere((x) => x.inStock);
      s.coins = 99999;
      s.confirmPurchase(p, spec, 1, shipping: s.lastShipping);
      final order = s.orders.first;
      s.payOrder(order);
      expect(order.state, OrderState.paid);

      s.adminMode = true;
      s.delistProduct(s.adminProducts.firstWhere((a) => a.name == p.name));
      expect(order.state, OrderState.paid, reason: '下架僅停止新訂單成立');
    });
  });

  group('超出名額的自訂訓練：鎖定但不刪除', () {
    /// 造一個「曾是會員、多開了幾份課表，之後權益失效」的情境。
    AppState overQuota() {
      final s = AppState()..subscribe(yearly: false);
      expect(s.customPlanQuota, AppState.kUnlimitedPlans);
      for (var i = 0; i < 3; i++) {
        s.addPlan('會員期間的第 $i 份', plannedOf(3));
      }
      s.advanceDemoClock(const Duration(days: 31)); // 權益到期
      expect(s.isMember, isFalse);
      return s;
    }

    test('權益失效後超出的部分被鎖定', () {
      final s = overQuota();
      expect(s.myPlanCount, greaterThan(s.customPlanQuota));
      expect(s.quotaLockedPlanIds.length,
          s.myPlanCount - s.customPlanQuota);
    });

    test('鎖定的是最新的幾份，舊的先保住', () {
      final s = overQuota();
      final mine = s.myPlans;
      final kept = mine.take(s.customPlanQuota).map((p) => p.id).toSet();
      expect(s.quotaLockedPlanIds.intersection(kept), isEmpty);
      expect(s.planQuotaLocked(mine.last), isTrue);
    });

    test('不刪除任何資料', () {
      final s = AppState()..subscribe(yearly: false);
      for (var i = 0; i < 3; i++) {
        s.addPlan('第 $i 份', plannedOf(3));
      }
      final before = s.customPlans.length;
      s.advanceDemoClock(const Duration(days: 31));
      expect(s.customPlans.length, before, reason: '鎖定但不刪除');
    });

    test('鎖定者不可啟用', () {
      final s = overQuota();
      final locked =
          s.myPlans.firstWhere((p) => s.planQuotaLocked(p));
      final was = locked.state;
      s.publishPlan(locked);
      expect(locked.state, was, reason: '鎖定的定義就是不可選用於訓練');
    });

    test('重新訂閱即回復可用', () {
      final s = overQuota();
      expect(s.quotaLockedPlanIds, isNotEmpty);
      s.subscribe(yearly: false);
      expect(s.quotaLockedPlanIds, isEmpty, reason: '會員不受名額限制');
    });

    test('升階讓名額變多時也自動解鎖', () {
      final s = overQuota();
      final lockedBefore = s.quotaLockedPlanIds.length;
      s.totalExp = expThresholdForRank(70); // 名額 4 → 5
      expect(s.quotaLockedPlanIds.length, lessThan(lockedBefore));
    });

    test('名額沒超出時沒有任何鎖定', () {
      final s = AppState();
      expect(s.myPlanCount, lessThanOrEqualTo(s.customPlanQuota));
      expect(s.quotaLockedPlanIds, isEmpty);
    });
  });
}
