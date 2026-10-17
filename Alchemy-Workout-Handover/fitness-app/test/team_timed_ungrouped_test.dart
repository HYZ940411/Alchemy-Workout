// 團隊限時榜不依人數分組（`[QA-05]`，使用者 2026-10-17 裁決 A）。
//
// 規格有兩處互相矛盾：〈排行榜週期結算流程〉寫兩個團隊榜都在 3/4/5 人組內比較，
// 但 02_Aggregate〈團隊限時排行獎勵已發放〉寫「不採人數分級距分組」，理由是限時分數
// 已用「固定 10 分／人＋全員完成加碼 50」收斂人數差距。使用者選後者：
// 日常榜分組、限時榜不分組。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/screens/social/team_leaderboard_screen.dart';
import 'package:fitness_app/state/app_state.dart';

PublicTeam _t(String name, int size, int daily, int timed, {int? peak}) =>
    PublicTeam(name, size, 5,
        id: 'x-$name', dailyScore: daily, timedScore: timed, peakSize: peak);

/// 我的隊（[size] 人）。成員名單不重要，分組看的是 [Team.lockedGroupSize]。
AppState _state({
  required int size,
  required int daily,
  required int timed,
  required List<PublicTeam> others,
}) {
  final s = AppState()
    ..displayName = '阿昶'
    ..myUid = 'u1';
  s.publicTeams = [...others];
  s.myTeam = Team(
    id: 't1',
    name: '健金術',
    isPublic: true,
    members: [
      TeamMember('阿昶', 20, TeamRole.leader, uid: 'u1'),
      for (var i = 1; i < size; i++)
        TeamMember('隊友$i', 15, TeamRole.member, uid: 'm$i'),
    ],
    contributions: {'u1': daily},
    timedScore: timed,
    lockedGroupSize: size,
  );
  return s;
}

void main() {
  final all = [
    _t('三A', 3, 10, 30),
    _t('三B', 3, 20, 10),
    _t('四A', 4, 30, 50),
    _t('五A', 5, 40, 20),
    _t('未成局', 2, 99, 99, peak: 2),
  ];

  group('teamRanking', () {
    test('限時榜：3、4、5 人的隊排在同一張榜，傳什麼組別都一樣', () {
      final r3 = teamRanking(all, TeamBoard.timed, 3);
      final r5 = teamRanking(all, TeamBoard.timed, 5);
      expect([for (final t in r3) t.name], ['四A', '三A', '五A', '三B']);
      expect([for (final t in r5) t.name], [for (final t in r3) t.name]);
    });

    test('日常榜仍然分組：3 人組只有 3 人的隊', () {
      final r = teamRanking(all, TeamBoard.daily, 3);
      expect([for (final t in r) t.name], ['三B', '三A']);
    });

    test('限時榜一樣排除未成局的隊（資格判定跟分組無關）', () {
      final r = teamRanking(all, TeamBoard.timed, 3);
      expect(r.any((t) => t.name == '未成局'), isFalse);
    });
  });

  group('我的名次與結算', () {
    test('我的限時名次跨組比：4 人隊分數 20，前面有 50、30 兩隊 → 第 3 名', () {
      final s = _state(size: 4, daily: 0, timed: 20, others: all);
      // 排：四A 50、三A 30、我 20 與 五A 20 並列、三B 10。
      expect(s.myTeamPlace(TeamBoard.timed), 3);
    });

    test('我的日常名次仍然只跟同組比', () {
      final s = _state(size: 4, daily: 5, timed: 0, others: all);
      // 4 人組只有「四A」(30) 與我 (5) → 第 2 名。
      expect(s.myTeamPlace(TeamBoard.daily), 2);
    });

    test('結算限時榜：組別標示「全部隊伍」，百分比級距用全部隊數算', () {
      // 我 4 人、限時 1000，全場第 1：一共 5 隊（4 隊別人＋我，未成局不算），前 5% 進位為 1 隊 → 最高檔。
      final s = _state(size: 4, daily: 0, timed: 1000, others: all);
      final row = s.settleBoard(Board.teamTimed)!;
      expect(row.group, '全部隊伍');
      expect(row.place, 1);
      expect(row.prize.coins, 100);
    });

    test('結算日常榜：組別仍標「N 人組」', () {
      final s = _state(size: 4, daily: 1000, timed: 0, others: all);
      final row = s.settleBoard(Board.teamDaily)!;
      expect(row.group, '4 人組');
    });

    test('同樣的分數，分不分組名次不同 —— 限時榜看全體', () {
      // 若限時榜分組，我是 4 人組的第 2 名（只有四A 在前）；不分組是第 3 名。
      final s = _state(size: 4, daily: 0, timed: 20, others: all);
      final row = s.settleBoard(Board.teamTimed)!;
      expect(row.place, 3);
    });
  });

  group('畫面', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: TeamLeaderboardScreen()),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('日常榜有「N 人組」的選項', (t) async {
      final s = _state(size: 4, daily: 5, timed: 20, others: all);
      await open(t, s);
      expect(find.text('3 人組'), findsOneWidget);
      expect(find.text('5 人組'), findsOneWidget);
    });

    testWidgets('切到限時榜：組別選項不見，三組的隊都列出來', (t) async {
      final s = _state(size: 4, daily: 5, timed: 20, others: all);
      await open(t, s);
      await t.tap(find.text(teamBoardNames[TeamBoard.timed]!));
      await t.pumpAndSettle();
      expect(find.text('3 人組'), findsNothing);
      expect(find.text('5 人組'), findsNothing);
      expect(find.text('三A'), findsOneWidget);
      expect(find.text('五A'), findsOneWidget);
      expect(find.text('四A'), findsOneWidget);
    });

    testWidgets('先在日常榜看了別的組，再切到限時榜：自己的隊仍固定在最上面', (t) async {
      final s = _state(size: 4, daily: 5, timed: 60, others: all);
      await open(t, s);
      await t.tap(find.text('5 人組'));
      await t.pumpAndSettle();
      await t.tap(find.text(teamBoardNames[TeamBoard.timed]!));
      await t.pumpAndSettle();
      // 我的限時 60 分是全場第 1 → 「已在前三名」那行只有置頂的那一列才有。
      expect(find.text('已在前三名'), findsOneWidget);
      expect(find.textContaining('你的隊在'), findsNothing,
          reason: '限時榜不分組，不該再說「你的隊在 4 人組」');
    });

    testWidgets('我的隊還沒成局（不上榜）：限時榜也不說「你的隊在 N 人組」', (t) async {
      final s = _state(size: 2, daily: 5, timed: 20, others: all);
      await open(t, s);
      await t.tap(find.text('5 人組'));
      await t.pumpAndSettle();
      expect(find.textContaining('你的隊在'), findsOneWidget, reason: '前提：日常榜確實會講');
      await t.tap(find.text(teamBoardNames[TeamBoard.timed]!));
      await t.pumpAndSettle();
      expect(find.textContaining('你的隊在'), findsNothing);
    });
  });
}
