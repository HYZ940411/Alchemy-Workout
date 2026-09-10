import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/train/plan_detail_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Future<void> boot(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('互動獎勵', () {
    test('只發經驗值，不發金幣', () {
      final s = AppState();
      final coins = s.coins;
      final exp = s.totalExp;
      final other = s.posts.firstWhere((p) => p.author != s.displayName);
      s.toggleLike(other);
      expect(s.coins, coins);
      expect(s.totalExp, greaterThan(exp));
    });

    test('自己的貼文不計 —— 對自身貼文的互動不發獎勵', () {
      final s = AppState();
      final mine = Post(
          id: 'm', author: s.displayName, authorRank: 1, text: 'hi',
          at: DateTime.now());
      s.posts.add(mine);
      final exp = s.totalExp;
      s.toggleLike(mine);
      s.addComment(mine, '自己回自己');
      expect(s.totalExp, exp);
    });

    test('超過每日上限仍可操作，只是不再發放', () {
      final s = AppState();
      final cap = platformConfig.i('reward', 'capLike');
      var granted = 0;
      // **逐篇不同的貼文**：同一篇反覆按只發一次獎勵（請求識別碼為
      // 貼文 ID ＋ 互動者 ID），拿同一批循環按測不出每日上限。
      for (var i = 0; i < cap + 5; i++) {
        final p = Post(
          id: 'cap-$i',
          author: '路人$i',
          authorRank: 20,
          text: '第 $i 篇',
          at: s.now,
        );
        s.posts.insert(0, p);
        final before = s.totalExp;
        s.toggleLike(p);
        if (s.totalExp > before) granted++;
      }
      expect(granted, cap);
      expect(s.posts.any((p) => p.likedByMe), isTrue, reason: '行為本身不被擋');
    });

    test('取消按讚不退回已發的經驗值', () {
      final s = AppState();
      final p = s.posts.firstWhere(
          (x) => x.author != s.displayName && !x.likedByMe);
      s.toggleLike(p);
      final exp = s.totalExp;
      s.toggleLike(p);
      expect(s.totalExp, exp);
    });
  });

  group('分享訓練成果', () {
    test('產生一則帶訓練成果的貼文，不是一個 toast', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      final r = s.finishWorkout(EndKind.completed);
      final n = s.visiblePosts.length;

      final out = s.shareWorkout(r, '今天練完了')!;
      expect(s.visiblePosts.length, n + 1);
      expect(out.post.attachedWorkout, isNotNull);
      expect(out.post.attachedWorkout, contains(r.plan.name));
      expect(out.exp, greaterThan(0));
    });

    test('分享出去的貼文一樣先過內容過濾', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      final r = s.finishWorkout(EndKind.completed);
      final n = s.posts.length;
      expect(s.shareWorkout(r, '加賴 詐騙'), isNull);
      expect(s.posts.length, n);
    });

    test('分享獎勵每日上限 3 次，超過仍分享得出去', () {
      final s = AppState();
      s.startWorkout(s.platformPlans.first);
      s.completeCurrentSet();
      final r = s.finishWorkout(EndKind.completed);
      final cap = platformConfig.i('reward', 'capShare');
      var granted = 0;
      for (var i = 0; i < cap + 2; i++) {
        final out = s.shareWorkout(r, '第 $i 次')!;
        if (out.exp > 0) granted++;
      }
      expect(granted, cap);
      expect(s.visiblePosts.where((p) => p.attachedWorkout != null).length,
          greaterThanOrEqualTo(cap + 2));
    });
  });

  group('教官專長', () {
    test('值域不含六大肌群，也不含需要執照的項目', () {
      for (final banned in ['胸', '背', '腿', '飲食營養', '傷後復健', '產後恢復']) {
        expect(kInstructorSpecialties, isNot(contains(banned)));
      }
      expect(kInstructorSpecialties.length, 11);
    });

    test('申請時至少 1 項至多 3 項', () {
      final s = AppState();
      expect(s.specialtyBlockedReason, isNotNull);
      s.toggleSpecialty('增肌');
      expect(s.specialtyBlockedReason, isNull);
      s..toggleSpecialty('減脂')..toggleSpecialty('新手引導')..toggleSpecialty('課表規劃');
      expect(s.instructorSpecialties.length, kSpecialtyMax);
    });

    test('再點一次可取消，不會卡在上限', () {
      final s = AppState()
        ..toggleSpecialty('增肌')
        ..toggleSpecialty('減脂')
        ..toggleSpecialty('新手引導');
      s.toggleSpecialty('減脂');
      expect(s.instructorSpecialties, isNot(contains('減脂')));
      s.toggleSpecialty('動作教學');
      expect(s.instructorSpecialties, contains('動作教學'));
    });
  });

  group('個人排行榜的自己那一列', () {
    test('距目標名次的差距，已在名次內者不給數字', () {
      expect(gapToPlace([100, 90, 80, 55], 3, 3), 25);
      expect(gapToPlace([100, 90, 80, 55], 1, 3), isNull);
    });

    test('本期還剩多久結算', () {
      final now = DateTime(2026, 9, 3, 10);
      expect(timeToSettlement(Board.personalWeekly, now),
          lessThanOrEqualTo(const Duration(days: 7)));
      expect(timeToSettlement(Board.personalMonthly, now).inDays,
          greaterThan(20));
    });
  });

  group('走一遍新加的入口', () {
    testWidgets('首頁有今天的訓練與開始訓練', (t) async {
      await boot(t);
      expect(find.text('今天的訓練'), findsOneWidget);
      await t.tap(find.text('開始訓練'));
      await t.pumpAndSettle();
      expect(find.byType(PlanDetailScreen), findsOneWidget);
    });

    testWidgets('全域通知鈴鐺帶未讀數，點得進通知中心', (t) async {
      await boot(t);
      final s = AppScope.of(t.element(find.byType(Scaffold).first));
      expect(s.unreadNotifications, greaterThan(0));
      expect(find.byType(CountBadge), findsWidgets);
      await t.tap(find.byIcon(Icons.notifications_none_rounded));
      await t.pumpAndSettle();
      expect(find.text('今日推播'), findsOneWidget);
    });

    testWidgets('個人排行榜把自己固定在最上面', (t) async {
      await boot(t);
      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      final list = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('個人排行榜'), 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(find.text('個人排行榜'));
      await t.pumpAndSettle();
      expect(find.textContaining('還剩'), findsWidgets);
      expect(find.textContaining('距離前'), findsWidgets);
    });
  });
}
