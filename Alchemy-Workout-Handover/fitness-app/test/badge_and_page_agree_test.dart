// 紅點數的每一則，通知頁上都要找得到。
//
// 紅點數的是 `notifications` 裡全部的未讀；通知頁列的卻只有
// 「今日推播」＋「今日未送出」＋「App 內通知」。昨天那則未讀的推播
// 從畫面上消失了，紅點還在數它 —— 使用者看到紅點寫著 1，
// 點進去一則未讀都沒有，而且怎麼點都消不掉。
//
// 這是今天第十個「功能做好了，而它做的事到不了任何人面前」的形狀，
// 差別是這次反過來：**數字到得了，東西到不了。**

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/social.dart';
import 'package:fitness_app/screens/social/notifications_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 昨天送出、還沒讀的一則推播。
AppNotification _yesterday(AppState s) => AppNotification(
      id: 'n-yesterday',
      sourceEvent: '測試',
      title: '昨天那則還沒讀的推播',
      body: '它昨天送出，今天仍未讀',
      at: s.now.subtract(const Duration(days: 1)),
      kind: NotifyKind.push,
      priority: NotifyPriority.expiring,
    );

void main() {
  group('紅點與通知頁要對得起來', () {
    test('前提：昨天的推播確實會被紅點數到', () {
      final s = AppState();
      final before = s.unreadNotifications;
      s.notifications.insert(0, _yesterday(s));
      expect(s.unreadNotifications, before + 1);
    });

    test('昨天的推播不在「今日推播」也不在「今日未送出」裡', () {
      final s = AppState();
      final n = _yesterday(s);
      s.notifications.insert(0, n);
      expect(s.todaysPushes.map((x) => x.id), isNot(contains(n.id)),
          reason: '它不是今天的');
      expect(s.suppressedPushes.map((x) => x.id), isNot(contains(n.id)),
          reason: '它不是被上限擋掉的');
    });

    test('它落在「先前的推播」這一格', () {
      final s = AppState();
      final n = _yesterday(s);
      s.notifications.insert(0, n);
      expect(s.earlierPushes.map((x) => x.id), contains(n.id));
    });

    test('「先前的推播」不含今天的 —— 同一則不會列兩次', () {
      final s = AppState();
      final todayIds = {
        ...s.todaysPushes.map((x) => x.id),
        ...s.suppressedPushes.map((x) => x.id),
      };
      expect(todayIds, isNotEmpty, reason: '前提：假資料裡有今天的推播');
      for (final n in s.earlierPushes) {
        expect(todayIds.contains(n.id), isFalse, reason: '${n.title} 被列了兩次');
      }
    });

    test('新的排前面 —— 先前的推播由近至遠', () {
      final s = AppState();
      for (var d = 1; d <= 3; d++) {
        s.notifications.add(AppNotification(
          id: 'n-d$d',
          sourceEvent: '測試',
          title: '$d 天前',
          body: '',
          at: s.now.subtract(Duration(days: d)),
          kind: NotifyKind.push,
          priority: NotifyPriority.routine,
        ));
      }
      final mine = s.earlierPushes.where((n) => n.id.startsWith('n-d')).toList();
      expect(mine.map((n) => n.id), ['n-d1', 'n-d2', 'n-d3']);
    });

    test('每一則通知都落在某一格裡 —— 沒有任何一則無處可去', () {
      final s = AppState();
      s.notifications.insert(0, _yesterday(s));
      final listed = {
        ...s.todaysPushes.map((n) => n.id),
        ...s.suppressedPushes.map((n) => n.id),
        ...s.earlierPushes.map((n) => n.id),
        ...s.notifications
            .where((n) => n.kind == NotifyKind.inApp)
            .map((n) => n.id),
      };
      for (final n in s.notifications) {
        expect(listed.contains(n.id), isTrue,
            reason: '「${n.title}」列不出來，但紅點會數它');
      }
    });
  });

  group('畫面上真的看得到', () {
    testWidgets('昨天那則未讀的推播出現在通知頁上', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      final s = AppState();
      final n = _yesterday(s);
      s.notifications.insert(0, n);

      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: NotificationsScreen()),
      ));
      await t.pumpAndSettle();

      await t.scrollUntilVisible(find.text(n.title), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(n.title), findsOneWidget,
          reason: '紅點數得到它，頁面就要列得出它');
    });

    testWidgets('紅點歸零之後，頁面上一個未讀點都不剩', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      final s = AppState();
      s.notifications.insert(0, _yesterday(s));
      s.markAllNotificationsRead();

      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: NotificationsScreen()),
      ));
      await t.pumpAndSettle();

      expect(s.unreadNotifications, 0);
    });
  });
}
