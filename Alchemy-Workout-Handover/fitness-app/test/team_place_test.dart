// 團隊頁的名次：不能是「第 0 名」（使用者 2026-10-17 回報）。
//
// 團隊頁原本讀 `Team.dailyRankPos`／`timedRankPos`，兩個欄位從來沒有人算過，
// 真帳號永遠是 0。名次改由排行榜同一份資料現算（`AppState.myTeamPlace`）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/team_screen.dart';
import 'package:fitness_app/state/app_state.dart';

PublicTeam _other(String name, int daily, int timed, {int size = 3}) =>
    PublicTeam(name, size, 5, id: 'x-$name', dailyScore: daily, timedScore: timed);

/// 我的隊：3 人、日常 [daily] 分、限時 [timed] 分。其他隊另放。
AppState _state({
  int daily = 10,
  int timed = 20,
  int peak = 3,
  List<PublicTeam> others = const [],
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
      const TeamMember('甲', 15, TeamRole.member, uid: 'u2'),
      const TeamMember('乙', 15, TeamRole.member, uid: 'u3'),
    ],
    contributions: {'u1': daily},
    timedScore: timed,
    lockedGroupSize: peak,
  );
  return s;
}

void main() {
  group('myTeamPlace', () {
    test('榜上只有我的隊：第 1 名，不是 0', () {
      final s = _state();
      expect(s.myTeamPlace(TeamBoard.daily), 1);
      expect(s.myTeamPlace(TeamBoard.timed), 1);
    });

    test('別隊分數比我高就排在我前面', () {
      final s = _state(others: [
        _other('強隊', 50, 5),
        _other('弱隊', 1, 99),
      ]);
      expect(s.myTeamPlace(TeamBoard.daily), 2, reason: '日常：強隊 50 > 我 10 > 弱隊 1');
      expect(s.myTeamPlace(TeamBoard.timed), 2, reason: '限時：弱隊 99 > 我 20 > 強隊 5');
    });

    test('同分並列同一名次', () {
      // 同分時排序取隊名：「A 同分隊」排在我前面，但名次仍是並列第 1，不是第 2。
      final s = _state(others: [_other('A 同分隊', 10, 20)]);
      expect(s.myTeamPlace(TeamBoard.daily), 1);
      expect(s.myTeamPlace(TeamBoard.timed), 1);
    });

    test('只跟同人數組別的隊比', () {
      final s = _state(others: [_other('四人組', 999, 999, size: 4)]);
      expect(s.myTeamPlace(TeamBoard.daily), 1);
    });

    test('我是四人組：只跟四人組比，三人組再高也不算', () {
      final s = _state(peak: 4, others: [
        _other('三人強隊', 999, 999),
        _other('四人隊', 50, 50, size: 4),
      ]);
      expect(s.myTeamPlace(TeamBoard.daily), 2, reason: '四人組裡只有「四人隊」50 > 我 10');
    });

    test('本月從未成局的隊不入榜：沒有名次', () {
      final s = _state(peak: 2);
      expect(s.myTeamPlace(TeamBoard.daily), isNull);
    });

    test('沒有隊伍：沒有名次', () {
      final s = AppState();
      s.myTeam = null;
      expect(s.myTeamPlace(TeamBoard.daily), isNull);
    });
  });

  group('團隊頁文字', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: TeamScreen())),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('寫現算的名次，不寫「第 0 名」', (t) async {
      final s = _state(others: [_other('強隊', 50, 5)]);
      await open(t, s);
      expect(find.text('第 0 名'), findsNothing);
      expect(find.text('第 2 名'), findsOneWidget, reason: '日常：強隊在前');
      expect(find.text('第 1 名'), findsOneWidget, reason: '限時：我 20 > 強隊 5');
    });

    testWidgets('不入榜寫「未入榜」', (t) async {
      final s = _state(peak: 2);
      await open(t, s);
      expect(find.text('未入榜'), findsNWidgets(2));
      expect(find.text('第 0 名'), findsNothing);
    });
  });
}
