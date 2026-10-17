// 團隊日常分數：每日任務一項一項完成，每項都要各加 10 分（使用者 2026-10-17 回報）。
//
// 回報：成員完成一個任務後團隊日常分數會加，第二個任務完成卻不再加分。
//
// 原因：任務池（含雲端那份）的判定來源 Event 用的是模型裡的名字
// （「訓練已結算」「互動者已按讚貼文」「互動者已留言」），
// 但 `_bumpTasks` 被呼叫時餵的是另外一組名字（「使用者已完成訓練」「使用者已按讚」），
// 留言則完全沒有呼叫。名字對不上的任務永遠不會被推進，也就永遠不發 +10。
// 只有名字剛好一致的（「使用者已簽到」「使用者已完成該組」）才會加分。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 我有一支隊，日常分數 0；今天的每日任務指定成 [events]。
AppState _state(List<(String, int)> events) {
  final s = AppState()
    ..displayName = '阿昶'
    ..myUid = 'u1';
  s.myTeam = Team(
    id: 't1',
    name: '健金術',
    isPublic: true,
    members: [
      TeamMember('阿昶', 20, TeamRole.leader, uid: 'u1'),
      const TeamMember('甲', 15, TeamRole.member, uid: 'u2'),
      const TeamMember('乙', 15, TeamRole.member, uid: 'u3'),
    ],
    contributions: {},
    lockedGroupSize: 3,
  );
  // 多放一項永遠完成不了的墊底任務：全部完成會加碼 20 分，會把要量的 +10 混在一起。
  // 每月前兩天是重新分隊期，團隊分數不累加；那不是這份測試要量的東西。
  var guard = 0;
  while (inRegroupWindow(s.now) && guard++ < 40) {
    s.advanceDemoClock(const Duration(days: 1));
  }
  s.dailyTasks = [
    for (final (e, n) in events) DailyTask(name: e, sourceEvent: e, target: n),
    DailyTask(name: '墊底', sourceEvent: '永遠不會發生', target: 99),
  ];
  return s;
}

int _daily(AppState s) => s.myTeam!.dailyScore;

/// 別人的貼文（按讚、留言才有互動獎勵，自己的不算）。
List<Post> _othersPosts(AppState s) =>
    s.posts.where((p) => !s.isMyPost(p)).toList();

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('簽到任務完成：團隊日常 +10（名字本來就對得上）', () {
    final s = _state([('使用者已簽到', 1)]);
    s.checkIn();
    expect(_daily(s), 10);
  });

  test('按讚任務（任務池的名字「互動者已按讚貼文」）：按滿 3 則要 +10', () {
    final s = _state([('互動者已按讚貼文', 3)]);
    final posts = _othersPosts(s);
    expect(posts.length, greaterThanOrEqualTo(3));
    for (final p in posts.take(3)) {
      s.toggleLike(p);
    }
    expect(s.dailyTasks.first.done, isTrue, reason: '進度要被推進到完成');
    expect(_daily(s), 10, reason: '完成的那一刻要發任務分數');
  });

  test('留言任務（任務池的名字「互動者已留言」）：留言 1 則要 +10', () {
    final s = _state([('互動者已留言', 1)]);
    s.addComment(_othersPosts(s).first, '加油');
    expect(s.dailyTasks.first.done, isTrue);
    expect(_daily(s), 10);
  });

  test('兩個任務依序完成：第二個也要再加 10（使用者回報的情境）', () {
    final s = _state([('使用者已簽到', 1), ('互動者已留言', 1)]);
    s.checkIn();
    expect(_daily(s), 10);
    s.addComment(_othersPosts(s).first, '加油');
    expect(_daily(s), 20, reason: '第二個任務完成不能沒有分數');
  });

  test('訓練任務（任務池的名字「訓練已結算」）：練完一場要 +10', () {
    final s = _state([('訓練已結算', 1)]);
    s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
    s.completeCurrentSet();
    s.backdateSession(const Duration(minutes: 10));
    s.finishWorkout(EndKind.completed);
    expect(s.dailyTasks.first.done, isTrue);
    // 訓練結算本身也會加個人分數，所以只驗「任務那 10 分有進來」：
    // 沒有修的話，這裡只有訓練結算的分數。
    final withTask = _daily(s);
    final base = _state([('永遠不會發生', 1)]);
    base.startWorkout(base.platformPlans.firstWhere((p) => p.id == 'p_push'));
    base.completeCurrentSet();
    base.backdateSession(const Duration(minutes: 10));
    base.finishWorkout(EndKind.completed);
    expect(withTask - _daily(base), 10, reason: '同一場訓練，有訓練任務的多 10 分');
  });

  test('分享任務（「發文者已分享訓練成果」）：分享一次完成', () {
    final s = _state([('發文者已分享訓練成果', 1)]);
    s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
    s.completeCurrentSet();
    s.backdateSession(const Duration(minutes: 10));
    final r = s.finishWorkout(EndKind.completed);
    s.shareWorkout(r, '今天練完了');
    expect(s.dailyTasks.first.done, isTrue);
  });

  test('按讚→取消→再按同一則：只算一次，不能灌水任務進度', () {
    final s = _state([('互動者已按讚貼文', 3)]);
    final p = _othersPosts(s).first;
    s.toggleLike(p);
    s.toggleLike(p);
    s.toggleLike(p);
    expect(s.dailyTasks.first.progress, 1);
  });

  test('按讚自己的貼文不算任務進度', () {
    final s = _state([('互動者已按讚貼文', 1)]);
    s.publishPost('今天練完了', PostVisibility.public);
    final mine = s.posts.firstWhere(s.isMyPost);
    s.toggleLike(mine);
    expect(s.dailyTasks.first.progress, 0);
  });

  group('開發者模式：重置我的每日任務（團隊成員都做完之後要能再測）', () {
    test('做完再重置：進度與已領歸零，再完成一次團隊日常分數繼續往上加', () {
      final s = _state([('互動者已留言', 1)]);
      final p = _othersPosts(s).first;
      s.addComment(p, '加油');
      s.claimTask(s.dailyTasks.first);
      expect(_daily(s), 10);
      // 再留言一次：任務已完成，不會再加。這就是回報時「測不了」的狀態。
      s.addComment(p, '再來');
      expect(_daily(s), 10);

      s.resetMyDailyTasksForTest();
      expect(s.dailyTasks.first.progress, 0);
      expect(s.dailyTasks.first.claimed, isFalse);
      expect(_daily(s), 10, reason: '已經拿到的分數不扣');

      s.addComment(p, '重來');
      expect(_daily(s), 20, reason: '重置後再完成一次要再加 10');
    });

    test('重置後同一則貼文再按讚，仍然計進度（按讚去重名單也清掉）', () {
      final s = _state([('互動者已按讚貼文', 1)]);
      final p = _othersPosts(s).first;
      s.toggleLike(p);
      expect(_daily(s), 10);
      s.toggleLike(p); // 取消
      s.resetMyDailyTasksForTest();
      s.toggleLike(p);
      expect(_daily(s), 20);
    });

    test('全部完成的加碼 20 分重置後可以再拿一次', () {
      final s = _state([('互動者已留言', 1)]);
      s.dailyTasks.removeLast(); // 去掉墊底，只剩一項：完成即全部完成
      final p = _othersPosts(s).first;
      s.addComment(p, '加油');
      expect(_daily(s), 30, reason: '任務 10 ＋ 全部完成加碼 20');
      s.resetMyDailyTasksForTest();
      s.addComment(p, '重來');
      expect(_daily(s), 60);
    });

    test('今天的互動計數歸零：留言額度用完之後重置，又能計進任務', () {
      final s = _state([('互動者已留言', 1)]);
      final p = _othersPosts(s).first;
      final cap = platformConfig.i('reward', 'capComment');
      for (var i = 0; i < cap + 2; i++) {
        s.addComment(p, '留言 $i');
      }
      expect(s.interactionsToday('Comment'), cap, reason: '前提：額度已用完');
      s.resetMyDailyTasksForTest();
      expect(s.interactionsToday('Comment'), 0);
      s.addComment(p, '重來');
      expect(s.dailyTasks.first.done, isTrue, reason: '額度回來了，這一則要計進任務');
    });

    group('畫面', () {
      Future<void> open(WidgetTester t, AppState s) async {
        await t.pumpWidget(AppScope(
          state: s,
          child: const MaterialApp(home: SettingsScreen()),
        ));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.widgetWithText(AppButton, '重置我的每日任務'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
      }

      testWidgets('開發者模式才有這顆鍵，按下去任務歸零', (t) async {
        final s = _state([('互動者已留言', 1)])..toggleDeveloperMode();
        s.addComment(_othersPosts(s).first, '加油');
        expect(s.dailyTasks.first.done, isTrue);
        await open(t, s);
        await t.tap(find.widgetWithText(AppButton, '重置我的每日任務'));
        await t.pump();
        expect(s.dailyTasks.first.progress, 0);
      });

      testWidgets('沒開開發者模式就看不到', (t) async {
        final s = _state([('互動者已留言', 1)]);
        await t.pumpWidget(AppScope(
          state: s,
          child: const MaterialApp(home: SettingsScreen()),
        ));
        await t.pumpAndSettle();
        expect(find.widgetWithText(AppButton, '重置我的每日任務'), findsNothing);
      });
    });
  });
}
