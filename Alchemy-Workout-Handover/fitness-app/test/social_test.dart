import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/social.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/social/blocked_list_screen.dart';
import 'package:fitness_app/screens/social/follow_list_screen.dart';
import 'package:fitness_app/screens/social/notifications_screen.dart';
import 'package:fitness_app/screens/social/post_detail_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

/// 社群：關注、封鎖、通知、貼文詳情
void main() {
  group('關注（單向關係）', () {
    test('關注別人只改對方的粉絲數，不改自己的', () {
      final s = AppState();
      final mine = s.followerCount;
      final target = s.socialUsers.firstWhere((u) => !s.following.contains(u.name));
      final theirs = s.otherFollowerCounts[target.name]!;

      s.toggleFollow(target.name);

      expect(s.following.contains(target.name), isTrue);
      expect(s.otherFollowerCounts[target.name], theirs + 1);
      expect(s.followerCount, mine, reason: '關注是我對他，不是他對我');
    });

    test('重複關注不產生第二筆 —— 唯一鍵為關注者＋被關注者', () {
      final s = AppState();
      final name = s.socialUsers.first.name;
      if (!s.following.contains(name)) s.toggleFollow(name);
      final n = s.following.length;
      s.following.add(name); // 直接再塞一次
      expect(s.following.length, n);
    });

    test('取消關注把對方的粉絲數減回去', () {
      final s = AppState();
      const name = '深蹲王'; // 一開始就在關注中
      expect(s.following.contains(name), isTrue);
      final theirs = s.otherFollowerCounts[name]!;
      s.toggleFollow(name);
      expect(s.following.contains(name), isFalse);
      expect(s.otherFollowerCounts[name], theirs - 1);
    });

    test('粉絲數下降不撤銷已解鎖的粉絲成就', () {
      final s = AppState();
      // 先把粉絲數推過 10 的門檻
      for (var i = 0; i < 8; i++) {
        s.gainFollower('粉絲$i');
      }
      expect(s.followerCount, greaterThanOrEqualTo(10));
      final unlocked = s.followerMilestones;
      expect(unlocked, greaterThanOrEqualTo(1));

      // 掉回門檻以下
      for (var i = 0; i < 8; i++) {
        s.loseFollower('粉絲$i');
      }
      expect(s.followerCount, lessThan(10));
      expect(s.followerMilestones, unlocked,
          reason: '粉絲取消關注是他人的行為，成就不該被拿走');
    });

    test('粉絲成就的門檻換算', () {
      expect(followerMilestonesReached(9), 0);
      expect(followerMilestonesReached(10), 1);
      expect(followerMilestonesReached(99), 2);
      expect(followerMilestonesReached(10000), kFollowerMilestones.length);
    });
  });

  group('封鎖（獨立 Aggregate）', () {
    test('可封鎖從未對話過的對象', () {
      final s = AppState();
      const stranger = '從沒講過話的人';
      expect(s.conversations.any((c) => c.peer == stranger), isFalse);
      s.blockUser(stranger);
      expect(s.isBlocked(stranger), isTrue);
    });

    test('重複封鎖同一人不產生第二筆', () {
      final s = AppState();
      s.blockUser('某人');
      final n = s.blockedUsers.length;
      s.blockUser('某人');
      expect(s.blockedUsers.length, n);
    });

    test('封鎖為單向：封鎖某人不代表被他封鎖', () {
      final s = AppState();
      s.blockUser('某人');
      // 模型裡封鎖的唯一鍵是「封鎖者＋被封鎖者」，本清單只存我封鎖的人。
      expect(s.blockedUsers.every((b) => b.name != '我'), isTrue);
    });

    test('解除封鎖後就查不到了', () {
      final s = AppState();
      final name = s.blockedUsers.first.name;
      s.unblockUser(name);
      expect(s.isBlocked(name), isFalse);
    });
  });

  group('通知的兩類與同日上限', () {
    test('只有推播類受上限約束，App 內通知不受限', () {
      final s = AppState();
      final inApp =
          s.notifications.where((n) => n.kind == NotifyKind.inApp).toList();
      // 其中要有一則是「今天」的，否則這條測試驗不到上限有沒有把它算進去。
      final now = DateTime.now();
      expect(
        inApp.any((n) =>
            n.at.year == now.year &&
            n.at.month == now.month &&
            n.at.day == now.day),
        isTrue,
      );
      // 今日推播裡不得出現 App 內通知，且名額沒被它吃掉
      final pushes = s.todaysPushes;
      expect(pushes.every((n) => n.kind == NotifyKind.push), isTrue);
      expect(pushes.length, kDailyPushLimit);
      final pushIds = pushes.map((n) => n.id).toSet();
      for (final n in inApp) {
        expect(pushIds.contains(n.id), isFalse);
      }
    });

    test('超出上限者依優先序由低至高捨棄', () {
      final s = AppState();
      expect(s.todaysPushes.length, kDailyPushLimit);
      // 假資料三則期限即將失效 ＋ 一則例行提醒，開機時的退步又帶進一則行動引導。
      expect(s.suppressedPushes, isNotEmpty);
      final worstSent = s.todaysPushes
          .map((n) => n.priority!.index)
          .reduce((a, b) => a > b ? a : b);
      for (final n in s.suppressedPushes) {
        expect(n.priority!.index, greaterThanOrEqualTo(worstSent),
            reason: '被丟掉的不該比送出去的還急');
      }
      expect(
        s.suppressedPushes.map((n) => n.priority),
        contains(NotifyPriority.routine),
        reason: '該丟的是例行提醒，不是期限即將失效的那些',
      );
      for (final n in s.todaysPushes) {
        expect(n.priority, NotifyPriority.expiring);
      }
    });

    test('同優先序內取較早的 —— 後來的不擠掉稍早同級的', () {
      final now = DateTime.now();
      AppNotification n(String id, int hour, NotifyPriority p) =>
          AppNotification(
            id: id,
            sourceEvent: 'x',
            title: id,
            body: '',
            at: DateTime(now.year, now.month, now.day, hour),
            kind: NotifyKind.push,
            priority: p,
          );
      final all = [
        n('晚的', 20, NotifyPriority.guidance),
        n('早的', 8, NotifyPriority.guidance),
      ];
      final got = pushesWithinLimit(all, now, limit: 1);
      expect(got.single.id, '早的');
    });

    test('不是今天的推播不算進今日上限', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final all = [
        AppNotification(
          id: '昨天的',
          sourceEvent: 'x',
          title: 'x',
          body: '',
          at: yesterday,
          kind: NotifyKind.push,
          priority: NotifyPriority.expiring,
        ),
      ];
      expect(pushesWithinLimit(all, now), isEmpty);
    });

    test('全部已讀後未讀數歸零', () {
      final s = AppState();
      expect(s.unreadNotifications, greaterThan(0));
      s.markAllNotificationsRead();
      expect(s.unreadNotifications, 0);
    });
  });

  group('貼文詳情', () {
    test('留言先過自動過濾：明顯違規不寫入', () {
      final s = AppState();
      final p = s.posts.first;
      final n = p.comments.length;
      expect(s.screenContent('加賴 詐騙'), FilterVerdict.blocked);
      // 畫面攔在呼叫 addComment 之前，這裡驗的是判定本身
      expect(p.comments.length, n);
    });

    test('留言寫得進去', () {
      final s = AppState();
      final p = s.posts.first;
      final n = p.comments.length;
      s.addComment(p, '寫得不錯');
      expect(p.comments.length, n + 1);
      expect(p.comments.last.author, s.displayName);
    });
  });

  group('走一遍社群五張', () {
    Future<void> boot(WidgetTester t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();
    }

    Future<void> openMore(WidgetTester t, String label) async {
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text(label));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();
    }

    testWidgets('動態牆點貼文進詳情，可留言', (t) async {
      await boot(t);
      await t.tap(find.text('社群').last);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('腿日結束'));
      await t.pumpAndSettle();

      expect(find.byType(PostDetailScreen), findsOneWidget);
      expect(find.text('留言'), findsOneWidget);

      await t.enterText(find.byType(TextField).last, '恭喜！');
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.arrow_forward_rounded));
      await t.pumpAndSettle();
      expect(find.textContaining('恭喜！'), findsOneWidget);
    });

    testWidgets('關注與粉絲：兩個分頁，按鈕可切換關注狀態', (t) async {
      await boot(t);
      await openMore(t, '關注與粉絲');
      expect(find.byType(FollowListScreen), findsOneWidget);

      // 關注分頁：清單裡的每一位都是追蹤中
      expect(find.text('關注 3'), findsOneWidget);
      expect(find.text('深蹲王'), findsOneWidget);
      await t.tap(find.widgetWithText(AppButton, '追蹤中').first);
      await t.pumpAndSettle();
      // 取消關注後，這一頁列的就是關注關係本身，該筆直接消失
      expect(find.text('關注 2'), findsOneWidget);
      expect(find.text('深蹲王'), findsNothing);

      // 切到粉絲分頁
      await t.tap(find.textContaining('粉絲 '));
      await t.pumpAndSettle();
      // 那行補充說明 2026-09-24 依使用者裁示移除（在按鈕底下反而讓人猶豫）。
      expect(find.textContaining('粉絲成就'), findsNothing);
    });

    testWidgets('封鎖名單：解除要先確認', (t) async {
      await boot(t);
      await openMore(t, '封鎖名單');
      expect(find.byType(BlockedListScreen), findsOneWidget);
      expect(find.text('匿名使用者 A'), findsOneWidget);

      await t.tap(find.text('解除').first);
      await t.pumpAndSettle();
      expect(find.textContaining('解除封鎖 匿名使用者 A'), findsOneWidget);
      await t.tap(find.widgetWithText(AppButton, '解除封鎖'));
      await t.pumpAndSettle();
      expect(find.text('匿名使用者 A'), findsNothing);
    });

    testWidgets('通知中心：未送出的那則列得出來', (t) async {
      await boot(t);
      await openMore(t, '通知');
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('今日未送出'), findsOneWidget);
      expect(find.text('每日登入提醒'), findsWidgets);

      await t.tap(find.text('全部已讀'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '全部已讀')).onPressed,
        isNull,
        reason: '沒有未讀就不該再讓人按',
      );
    });
  });
}
