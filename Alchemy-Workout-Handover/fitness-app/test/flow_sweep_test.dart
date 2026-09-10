// 逐份流程文件稽核所找出的六個缺口，各自釘住。
//
// 這一輪的教訓是：編號的五份文件掃完，不等於 31 份流程文件掃完。
// 下面每一組都對應一份流程文件裡一條白紙黑字的規則。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/decay.dart';
import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('〈排行榜週期結算流程〉週期起訖沿用 04:00 換日', () {
    bool contains(Board b, DateTime now) {
      final (from, to) = periodOf(b, now);
      return !now.isBefore(from) && now.isBefore(to);
    }

    test('週一凌晨 0–4 點屬於前一週', () {
      final earlyMonday = DateTime(2026, 9, 7, 2);
      expect(contains(Board.personalWeekly, earlyMonday), isTrue,
          reason: '算出來的週期必須包含當下，否則結算會提早 4 小時觸發');
      final (from, to) = periodOf(Board.personalWeekly, earlyMonday);
      expect(from, DateTime(2026, 8, 31, 4));
      expect(to, DateTime(2026, 9, 7, 4));
    });

    test('每月 1 日凌晨 0–4 點屬於前一月', () {
      final earlyFirst = DateTime(2026, 9, 1, 2);
      expect(contains(Board.personalMonthly, earlyFirst), isTrue);
      final (from, to) = periodOf(Board.personalMonthly, earlyFirst);
      expect(from, DateTime(2026, 8, 1, 4));
      expect(to, DateTime(2026, 9, 1, 4));
    });

    test('04:00 之後即進入新週期', () {
      final (from, _) = periodOf(Board.personalWeekly, DateTime(2026, 9, 7, 5));
      expect(from, DateTime(2026, 9, 7, 4));
      for (final b in Board.values) {
        for (final h in [0, 3, 4, 5, 12, 23]) {
          expect(contains(b, DateTime(2026, 9, 7, h)), isTrue,
              reason: '$b 於 $h 點算出的週期不含當下');
          expect(contains(b, DateTime(2026, 9, 1, h)), isTrue,
              reason: '$b 於 1 日 $h 點算出的週期不含當下');
        }
      }
    });

    test('結算不會在 04:00 之前提早觸發', () {
      final s = AppState();
      // **相對於當下**推算，不寫死日期 —— 寫死的話換一天跑就變成往回快轉，
      // 測試會在某個日子突然開始失敗，而程式一行都沒改。
      void jumpTo(DateTime t) {
        final d = t.difference(s.now);
        expect(d.isNegative, isFalse, reason: '示範時鐘只能往前');
        s.advanceDemoClock(d);
      }

      // 本週期的結束時點就是下一個週一 04:00。
      final (_, boundary) = periodOf(Board.personalWeekly, s.now);
      jumpTo(boundary.subtract(const Duration(hours: 6))); // 週日 22:00
      s.settleDueBoards();
      final before = s.leaderboardHistory.length;

      jumpTo(boundary.subtract(const Duration(hours: 2))); // 週一 02:00
      expect(s.settleDueBoards(), isEmpty,
          reason: '週一 02:00 還在上一週期內，不該結算');
      expect(s.leaderboardHistory.length, before);

      jumpTo(boundary.add(const Duration(hours: 1))); // 週一 05:00
      expect(s.leaderboardHistory.length, greaterThan(before),
          reason: '過了 04:00 才結算');
    });
  });

  group('〈發文與互動流程〉按讚獎勵的請求識別碼', () {
    Post seed(AppState s, String id) {
      final p = Post(
        id: id,
        author: '路人 $id',
        authorRank: 20,
        text: '$id 的貼文',
        at: s.now,
      );
      s.posts.insert(0, p);
      return p;
    }

    test('同一篇按讚 → 取消 → 再按，只發一次獎勵', () {
      final s = AppState();
      final p = seed(s, 'a');
      final exp0 = s.totalExp;
      s.toggleLike(p);
      final once = s.totalExp - exp0;
      expect(once, greaterThan(0));
      for (var i = 0; i < 5; i++) {
        s.toggleLike(p); // 取消
        s.toggleLike(p); // 再按
      }
      expect(s.totalExp, exp0 + once,
          reason: '防刷由「同一貼文只發一次」承擔，不是由每日上限承擔');
    });

    test('沒發獎勵就不吃掉每日額度', () {
      final s = AppState();
      final p = seed(s, 'b');
      s.toggleLike(p);
      final used = s.interactionsToday('Like');
      s.toggleLike(p);
      s.toggleLike(p);
      expect(s.interactionsToday('Like'), used);
    });

    test('不同貼文各自發一次', () {
      final s = AppState();
      final exp0 = s.totalExp;
      s.toggleLike(seed(s, 'c1'));
      final once = s.totalExp - exp0;
      s.toggleLike(seed(s, 'c2'));
      expect(s.totalExp, exp0 + once * 2);
    });

    test('成就計數照常累加 —— 計的是行為次數', () {
      final s = AppState();
      final p = seed(s, 'd');
      final before = s.interactionTotals['按讚']!;
      s.toggleLike(p);
      s.toggleLike(p);
      s.toggleLike(p);
      expect(s.interactionTotals['按讚'], before + 2, reason: '取消不計數，兩次「按」計兩次');
    });
  });

  group('〈虛擬商品購買流程〉商品發放已失敗', () {
    Order pendingVirtual(AppState s) {
      final o = Order(
        id: 'V-1',
        productName: '進階計畫',
        spec: '永久解鎖',
        qty: 1,
        kind: ProductKind.virtual,
        placedAt: s.now,
        coinPaid: 600,
        cashPaid: 0,
        state: OrderState.pendingPayment,
      );
      s.orders.insert(0, o);
      return o;
    }

    test('發放失敗不改變訂單狀態，維持已付款', () {
      final s = AppState();
      final o = pendingVirtual(s);
      s.payOrder(o);
      expect(o.state, OrderState.delivered, reason: '正常路徑一次就發成功');

      final o2 = pendingVirtual(s);
      o2.state = OrderState.paid;
      s.failDelivery(o2, '道具入庫逾時');
      expect(o2.state, OrderState.paid, reason: '不自動退款，訂單維持已付款');
      expect(o2.deliveryRetries, 1);
      expect(o2.deliveryFailReason, '道具入庫逾時');
    });

    test('自動重試上限 3 次，達上限轉人工處理', () {
      final s = AppState();
      final o = pendingVirtual(s);
      o.state = OrderState.paid;
      for (var i = 0; i < kDeliveryMaxRetries; i++) {
        s.failDelivery(o, '服務錯誤');
        expect(o.deliveryManual, isFalse, reason: '第 ${i + 1} 次還在自動重試範圍內');
      }
      expect(o.deliveryRetries, kDeliveryMaxRetries);
      s.failDelivery(o, '服務錯誤');
      expect(o.deliveryManual, isTrue, reason: '達上限仍失敗者轉人工處理');
      expect(o.deliveryRetries, kDeliveryMaxRetries, reason: '不再往上加');
      expect(s.manualDeliveryOrders, contains(o));
      expect(o.state, OrderState.paid);
    });

    test('重試成功後轉入已發放，人工旗標一併清掉', () {
      final s = AppState();
      final o = pendingVirtual(s);
      o.state = OrderState.paid;
      s.failDelivery(o, '逾時');
      expect(s.undeliveredOrders, contains(o));
      s.deliverOrder(o);
      expect(o.state, OrderState.delivered);
      expect(o.deliveryManual, isFalse);
      expect(o.deliveryFailReason, isNull);
      expect(s.undeliveredOrders, isNot(contains(o)));
    });
  });

  group('〈實體商品購買流程〉電子郵件通知', () {
    test('未填電子郵件者不寄，也不因此少收到 App 內通知', () {
      final s = AppState();
      s.email = null;
      s.requestDeletion();
      expect(s.emailOutbox, isEmpty);
      expect(s.pendingDeletion, isTrue, reason: '沒信箱不影響排程本身');
    });

    test('已填者：帳號刪除排程寄一封', () {
      final s = AppState();
      s.setEmail('a@b.co');
      s.requestDeletion();
      expect(s.emailOutbox, hasLength(1));
      expect(s.emailOutbox.first.to, 'a@b.co');
      expect(s.emailOutbox.first.subject, contains('帳號刪除'));
    });

    test('出貨寄一封，且帶物流單號', () {
      final s = AppState();
      s.setEmail('a@b.co');
      final o = s.adminOrders.firstWhere((o) => o.state == '已付款');
      s.shipOrder(o, trackingNo: 'TW999');
      final mail = s.emailOutbox.first;
      expect(mail.subject, contains('出貨'));
      expect(mail.body, contains('TW999'));
    });
  });

  group('〈訓練紀錄流程〉使用者已取消該組', () {
    AppState started() {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      return s;
    }

    test('已完成的組取消得掉，進度條跟著回退', () {
      final s = started();
      expect(s.completeCurrentSet(), isTrue);
      final done = s.session!.records[0][0];
      expect(done.state, SetState.done);

      expect(s.uncheckSet(0, 0), isTrue);
      expect(s.session!.records[0][0].state, isNot(SetState.done),
          reason: '該組回到未完成');
    });

    test('原筆不實體刪除，標記已取消後留著', () {
      final s = started();
      s.completeCurrentSet();
      final original = s.session!.records[0][0];
      s.uncheckSet(0, 0);
      expect(original.state, SetState.cancelled);
      expect(s.session!.cancelled, hasLength(1));
      expect(s.session!.cancelled.first.record, same(original),
          reason: '「使用者已取消該組」已經發生，資料要看得出曾經取消過');
    });

    test('再次勾選是新建一筆，不是把原筆改回來', () {
      final s = started();
      s.completeCurrentSet();
      final original = s.session!.records[0][0];
      s.uncheckSet(0, 0);
      final fresh = s.session!.records[0][0];
      expect(fresh, isNot(same(original)), reason: '同一組可以有多筆組紀錄');
      expect(s.session!.cancelled.first.record, same(original),
          reason: '原筆維持已取消，不被覆寫');
    });

    test('未完成的組不適用 —— Precondition 是該組已完成', () {
      final s = started();
      expect(s.uncheckSet(0, 0), isFalse);
      expect(s.session!.cancelled, isEmpty);
    });

    test('索引超出範圍不當機', () {
      final s = started();
      expect(s.uncheckSet(99, 0), isFalse);
      expect(s.uncheckSet(0, 99), isFalse);
      expect(s.uncheckSet(-1, -1), isFalse);
    });
  });

  group('〈管理員管理社群流程〉永久停權期間暫停計時', () {
    AppState permanentlyBanned() {
      final s = AppState();
      s.punishment = Punishment(
        kind: PunishmentKind.permanent,
        reason: '嚴重違規',
        evidence: '—',
        issuedAt: s.now,
        violationCount: 7,
        nextConsequence: '永久停權',
      );
      return s;
    }

    test('永久停權期間連續訓練天數不歸零', () {
      final s = permanentlyBanned();
      s.trainingStreakDays = 12;
      s.advanceDemoClock(const Duration(days: 20));
      expect(s.trainingStreakDays, 12,
          reason: '訓練被整個關掉，卻因為沒訓練而歸零，等於同一件事罰兩次');
    });

    test('永久停權期間能力值不退步', () {
      final s = permanentlyBanned();
      final before = {for (final d in Dim.values) d: s.points[d]!};
      s.advanceDemoClock(const Duration(days: 30));
      for (final d in Dim.values) {
        expect(s.points[d], before[d], reason: '$d 在停權期間退步了');
      }
    });

    test('社群功能停權不凍結 —— 它不影響訓練與所有累積', () {
      final s = AppState();
      s.punishment = Punishment(
        kind: PunishmentKind.communitySuspended,
        reason: '不當言論',
        evidence: '—',
        issuedAt: s.now,
        violationCount: 3,
        nextConsequence: '社群功能停權 30 天',
        expiresAt: s.now.add(const Duration(days: 7)),
      );
      s.trainingStreakDays = 12;
      s.advanceDemoClock(const Duration(days: 20));
      expect(s.clocksFrozen, isFalse);
      expect(s.trainingStreakDays, 0, reason: '被禁的是社群互動，不是訓練');
    });

    test('申訴撤銷時以撤銷時點重設計時基準', () {
      final s = permanentlyBanned();
      s.trainingStreakDays = 12;
      s.advanceDemoClock(const Duration(days: 40));
      s.rebaseClocks();
      s.punishment = null;
      // 重設後不該在解除的瞬間一次結清那 40 天。
      s.runStreakCheck();
      s.runDecayCheck();
      expect(s.trainingStreakDays, 12);
      expect(hoursSinceBoundary(s.lastTrainedDate, s.now),
          lessThan(kInterruptWarnHours),
          reason: '計時基準要落在撤銷時點，不是停權前那一天');
    });
  });
}
