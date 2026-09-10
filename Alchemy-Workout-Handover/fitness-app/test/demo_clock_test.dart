import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/decay.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('展示時鐘貫穿全域', () {
    test('推進時鐘後，簽到會換日', () {
      final s = AppState();
      s.checkIn();
      expect(s.checkedInToday, isTrue);
      final streak = s.checkInStreak;
      final total = s.checkInTotal;

      s.advanceDemoClock(const Duration(days: 1));
      expect(s.checkedInToday, isFalse, reason: '換日了就該能再簽');
      s.checkIn();
      expect(s.checkInStreak, streak + 1, reason: '連續簽到要接得上');
      expect(s.checkInTotal, total + 1);
    });

    test('同一天內推進幾小時不換日', () {
      final s = AppState();
      s.checkIn();
      s.advanceDemoClock(const Duration(hours: 2));
      expect(s.checkedInToday, isTrue);
    });

    test('中斷一天以上，連續簽到自 1 重新起算', () {
      final s = AppState();
      s.checkIn();
      s.advanceDemoClock(const Duration(days: 3));
      s.checkIn();
      expect(s.checkInStreak, 1);
    });

    test('限時任務每日換一組，前一日的不可補做', () {
      final s = AppState();
      s.completeTimedTask();
      expect(s.timedTask.doneBy(s.displayName), isTrue);
      s.advanceDemoClock(const Duration(days: 1));
      // 排程每日指派新的一組，故不會停在「已失效」；
      // 「隔日不可補做」表現為前一日的完成紀錄不帶過來。
      expect(s.timedTaskExpired, isFalse);
      expect(s.timedTask.doneBy(s.displayName), isFalse,
          reason: '當日有效，隔日不可補做');
    });

    test('排程還沒跑到時，過期的那一組不給完成', () {
      final s = AppState();
      // 只推時鐘、不跑排程 —— 手上這一組已經是昨天的了。
      s.demoClockOffset += const Duration(days: 1);
      expect(s.timedTaskExpired, isTrue);
      s.completeTimedTask();
      expect(s.timedTask.doneBy(s.displayName), isFalse);
    });

    test('訂單的 15 分鐘預扣，推進時鐘後會釋放並回補庫存', () {
      final s = AppState();
      final p = s.products.firstWhere((p) => p.kind == ProductKind.physical);
      final spec = p.specs.first;
      final stock = spec.stock;
      s.coins += 100000;
      s.confirmPurchase(p, spec, 1, shipping: s.lastShipping);
      expect(spec.stock, stock - 1, reason: '確認購買當下即預扣');
      final o = s.orders.first;
      expect(o.state, OrderState.pendingPayment);

      s.advanceDemoClock(const Duration(minutes: 20));
      expect(s.releaseExpiredHolds(), isNotEmpty);
      expect(o.state, OrderState.cancelled);
      expect(spec.stock, stock, reason: '預扣的庫存回補至該規格');
    });

    test('補簽的可選範圍跟著時鐘走', () {
      final s = AppState();
      final d = s.now.subtract(const Duration(days: 2));
      expect(s.daysAgo(d), 2);
      s.advanceDemoClock(const Duration(days: 5));
      expect(s.daysAgo(d), 7);
    });

    test('推進時鐘後產生的時戳，落在推進後而非現在', () {
      final s = AppState();
      s.advanceDemoClock(const Duration(days: 30));
      s.publishPost('推進之後發的文', PostVisibility.public);
      final p = s.posts.first;
      expect(p.at.isAfter(DateTime.now()), isTrue,
          reason: '否則新貼文會顯示成「30 天前」，比舊文還舊');
      expect(s.now.difference(p.at).inMinutes, lessThan(1));
    });

    test('時鐘是全域的：構不到 AppState 的純函式讀到同一個時間', () {
      final s = AppState();
      final before = appNow();
      s.advanceDemoClock(const Duration(days: 10));
      expect(appNow().difference(before).inDays, greaterThanOrEqualTo(9));
      expect(appNow().difference(s.now).inSeconds.abs(), lessThan(2));
    });
  });

  group('回歸任務獎勵', () {
    /// 推到能力值退步，讓回歸任務被指派。
    AppState assigned() {
      final s = AppState();
      s.advanceDemoClock(Duration(hours: kDecayIntervalHours + 24));
      expect(s.returnTaskAssigned, isTrue);
      return s;
    }

    test('獎勵不於完成時自動發放，須主動領取', () {
      final s = assigned();
      final exp = s.totalExp;
      final coins = s.coins;
      s.completeReturnTask();
      expect(s.totalExp, exp, reason: '完成本身不發獎');
      expect(s.coins, coins);
      expect(s.returnRewardClaimable, isTrue);
    });

    test('領取後發放經驗值 50 ＋ 金幣 50 ＋ AI 點數 1', () {
      final s = assigned();
      final exp = s.totalExp;
      final coins = s.coins;
      final credit = s.aiTotal;
      s.completeReturnTask();
      final r = s.claimReturnReward()!;
      expect(r.exp, 50);
      expect(r.coins, 50);
      expect(r.credit, 1);
      expect(s.totalExp, exp + 50);
      expect(s.coins, coins + 50);
      expect(s.aiTotal, credit + 1);
    });

    test('同一筆獎勵不得重複領取', () {
      final s = assigned();
      s.completeReturnTask();
      s.claimReturnReward();
      final coins = s.coins;
      expect(s.claimReturnReward(), isNull);
      expect(s.coins, coins);
    });

    test('未完成者不得領取', () {
      final s = assigned();
      expect(s.returnRewardClaimable, isFalse);
      expect(s.claimReturnReward(), isNull);
    });

    test('逾期者不發放獎勵', () {
      final s = assigned();
      s.viewReturnTask();
      final assignedAt = s.returnTaskAssignedAt;
      s.advanceDemoClock(const Duration(days: 8));
      expect(s.returnTaskLog.last.overdue, isTrue, reason: '該筆記為已逾期');
      expect(s.returnTaskDone, isFalse);
      expect(s.claimReturnReward(), isNull, reason: '逾期不發放獎勵');
      // 逾期後可再次指派（距前一次指派已滿 7 天），那是新的一筆。
      expect(s.returnTaskAssignedAt, isNot(assignedAt));
    });

    test('數額為平台級可調參數', () {
      final s = assigned();
      s.adminMode = true;
      expect(s.applySettings('reward', {'returnCoin': 99}), isNull);
      s.completeReturnTask();
      expect(s.claimReturnReward()!.coins, 99);
    });
  });

  group('連續逾期次數為衍生值', () {
    test('倒序掃描到第一筆已完成即停止計數', () {
      final s = AppState();
      s.returnTaskLog
        ..add((assignedAt: s.now, overdue: true))
        ..add((assignedAt: s.now, overdue: false))
        ..add((assignedAt: s.now, overdue: true))
        ..add((assignedAt: s.now, overdue: true));
      expect(s.returnTaskOverdueStreak, 2, reason: '遇已完成即停，不累計更早的');
    });

    test('再次訓練切斷連續，指派機制重新啟動', () {
      final s = AppState();
      for (var i = 0; i < 3; i++) {
        s.returnTaskLog.add((assignedAt: s.now, overdue: true));
      }
      expect(s.returnTaskOverdueStreak, 3);
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.completed);
      expect(s.returnTaskOverdueStreak, 0);
    });
  });
}
