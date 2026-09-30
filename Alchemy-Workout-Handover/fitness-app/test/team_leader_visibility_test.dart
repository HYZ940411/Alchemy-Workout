import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/team_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 使用者回報「B 使用者申請加入團隊時，A 隊長還是沒看到 B 的申請。
/// 我的『收件匣』也沒看到」。
///
/// **雲端讀到了那一筆** —— 開發者模式的登入同步顯示「團隊請求：1 筆
/// （邀請 0／申請 1）」。藏起它的是畫面上這一行：
///
/// ```dart
/// final isLeader = team.members.any((m) => m.name == '你' && …);
/// ```
///
/// `'你'` 是**示範帳號的預設暱稱，寫死在畫面裡**。真的登入的使用者有
/// 自己的暱稱，所以這個條件對他永遠是假 —— 待審申請那一區從來不會出現。
void main() {
  Team teamWith({
    required String leaderName,
    String? leaderUid,
    List<PendingRequest> applications = const [],
  }) =>
      Team(
        id: 't1',
        name: '鐵人小隊',
        isPublic: true,
        capacity: 10,
        members: [
          TeamMember(leaderName, 20, TeamRole.leader, uid: leaderUid),
          const TeamMember('隊友', 15, TeamRole.member, uid: 'u2'),
        ],
      )..applications.addAll(applications);

  final pending = [PendingRequest('小美', 12, DateTime(2027), uid: 'u9')];

  group('隊長判定', () {
    test('暱稱不是「你」的真實使用者也是隊長', () {
      final s = AppState()
        ..displayName = '阿昶'
        ..myUid = 'u1'
        ..myTeam = teamWith(leaderName: '阿昶', leaderUid: 'u1');
      expect(s.iAmLeader, isTrue);
    });

    test('以 uid 為準 —— 改了暱稱仍然是隊長', () {
      final s = AppState()
        ..displayName = '新暱稱'
        ..myUid = 'u1'
        ..myTeam = teamWith(leaderName: '舊暱稱', leaderUid: 'u1');
      expect(s.iAmLeader, isTrue);
    });

    test('撞名的人不是隊長', () {
      final s = AppState()
        ..displayName = '阿昶'
        ..myUid = 'u1'
        ..myTeam = teamWith(leaderName: '阿昶', leaderUid: 'u2');
      expect(s.iAmLeader, isFalse);
    });

    test('沒有 uid 的示範資料退回比暱稱', () {
      final s = AppState()
        ..displayName = '你'
        ..myTeam = teamWith(leaderName: '你');
      expect(s.iAmLeader, isTrue);
    });

    test('隊員不是隊長', () {
      final s = AppState()
        ..displayName = '隊友'
        ..myUid = 'u2'
        ..myTeam = teamWith(leaderName: '阿昶', leaderUid: 'u1');
      expect(s.iAmLeader, isFalse);
    });
  });

  group('團隊頁：待審申請', () {
    Future<void> open(WidgetTester t, AppState s) async {
      // 團隊頁是一條長 ListView，待審申請在很下面 —— 預設 600 高的
      // 測試視窗只會建出畫面內的那幾個 child，找不到不代表沒有。
      // 把視窗拉高，驗的才是「有沒有渲染」而不是「有沒有捲到」。
      await t.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: TeamScreen())),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('暱稱不是「你」的隊長看得到申請', (t) async {
      final s = AppState()
        ..displayName = '阿昶'
        ..myUid = 'u1'
        ..myTeam = teamWith(
            leaderName: '阿昶', leaderUid: 'u1', applications: pending);
      await open(t, s);
      expect(find.text('小美'), findsWidgets, reason: '待審申請要看得到');
    });

    testWidgets('不是隊長就看不到', (t) async {
      final s = AppState()
        ..displayName = '隊友'
        ..myUid = 'u2'
        ..myTeam = teamWith(
            leaderName: '阿昶', leaderUid: 'u1', applications: pending);
      await open(t, s);
      expect(find.text('小美'), findsNothing);
    });
  });
}
