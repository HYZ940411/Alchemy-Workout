import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/social.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/social/team_create_screen.dart';
import 'package:fitness_app/screens/social/team_detail_screen.dart';
import 'package:fitness_app/screens/social/team_leaderboard_screen.dart';
import 'package:fitness_app/state/app_state.dart';

PublicTeam team(String name, {int size = 3, int? peak, int daily = 0, int timed = 0}) =>
    PublicTeam(name, size, kTeamCapacity,
        id: name, peakSize: peak, dailyScore: daily, timedScore: timed);

void main() {
  group('分組與資格：一律取週期內最高值', () {
    test('3 人隊招滿 5 人後不會留在 3 人組', () {
      expect(team('a', size: 5, peak: 5).groupSize, 5);
    });

    test('5 人隊結算前踢到 3 人，仍在 5 人組', () {
      final t = team('b', size: 3, peak: 5);
      expect(t.groupSize, 5, reason: '不隨成員退出而降級');
    });

    test('曾達 3 人者即使跌破仍保留排名與獎勵資格', () {
      expect(team('c', size: 2, peak: 3).rankEligible, isTrue);
    });

    test('本月從未成局者排除於排行榜之外', () {
      expect(team('d', size: 2, peak: 2).rankEligible, isFalse);
    });

    test('分組與資格用的是同一個人數認定，不是兩套邏輯', () {
      final t = team('e', size: 2, peak: 4);
      expect(t.rankEligible, isTrue);
      expect(t.groupSize, 4);
    });
  });

  group('排行榜只跟同組別比', () {
    final all = [
      team('五人強隊', size: 5, peak: 5, daily: 99999),
      team('四人A', size: 4, peak: 4, daily: 500),
      team('四人B', size: 4, peak: 4, daily: 300),
      team('沒成局', size: 2, peak: 2, daily: 88888),
    ];

    test('4 人組的榜上沒有 5 人隊，也沒有未成局的隊', () {
      final r = teamRanking(all, TeamBoard.daily, 4);
      expect(r.map((t) => t.name), ['四人A', '四人B']);
    });

    test('兩個榜各自維護，分數不合併', () {
      final t = [
        team('x', size: 3, peak: 3, daily: 100, timed: 10),
        team('y', size: 3, peak: 3, daily: 10, timed: 100),
      ];
      expect(teamRanking(t, TeamBoard.daily, 3).first.name, 'x');
      expect(teamRanking(t, TeamBoard.timed, 3).first.name, 'y');
    });

    test('距前 3 還差幾分 —— 已在前三名者不給這個數字', () {
      final r = [
        team('1', peak: 3, daily: 100),
        team('2', peak: 3, daily: 90),
        team('3', peak: 3, daily: 80),
        team('4', peak: 3, daily: 55),
      ];
      expect(gapToTopThree(r, 3, TeamBoard.daily), 25);
      expect(gapToTopThree(r, 1, TeamBoard.daily), isNull);
    });
  });

  group('限時分數的公式', () {
    List<TeamMember> ms(int n) => [
          for (var i = 0; i < n; i++)
            TeamMember('m$i', 10, i == 0 ? TeamRole.leader : TeamRole.member),
        ];

    test('完成人數 × 10，全員完成另加 50', () {
      expect(
        TimedTaskTally(
                members: ms(3),
                credited: {personKey('m0', null), personKey('m1', null)})
            .score,
        2 * kTimedTaskPerMember,
      );
      expect(
        TimedTaskTally(members: ms(3), credited: {
          for (final n in ['m0', 'm1', 'm2']) personKey(n, null)
        }).score,
        3 * kTimedTaskPerMember + kTimedTaskAllBonus,
        reason: '全員完成另加固定分',
      );
    });

    test('名單向團隊要 —— 已離隊的人不算，也不佔分母', () {
      final tally = TimedTaskTally(
          members: ms(2),
          credited: {personKey('m0', null), personKey('已離隊的人', null)});
      expect(tally.total, 2);
      expect(tally.doneCount, 1);
      expect(tally.allDone, isFalse);
    });

    test('沒有成員時不成立全員完成', () {
      expect(TimedTaskTally(members: const [], credited: const {}).allDone,
          isFalse);
    });
  });

  group('加入申請的 Precondition', () {
    test('私密團隊不接受申請', () {
      final s = AppState()..myTeam = null;
      final t = PublicTeam('私', 2, kTeamCapacity, isPublic: false);
      expect(s.joinBlockedReason(t), contains('私密'));
    });

    test('滿員不接受申請', () {
      final s = AppState()..myTeam = null;
      expect(s.joinBlockedReason(team('滿', size: kTeamCapacity)),
          contains('已滿'));
    });

    test('一次只能屬於一個團隊', () {
      final s = AppState();
      expect(s.myTeam, isNotNull);
      expect(s.joinBlockedReason(team('別隊')), contains('先退出'));
    });

    test('換隊冷卻期間不可申請', () {
      final s = AppState()..leaveTeam();
      expect(s.switchCooldownLeft, greaterThan(const Duration(hours: 11)));
      expect(s.joinBlockedReason(team('別隊')), contains('冷卻'));
    });

    test('加入後 3 小時內退出不觸發冷卻期', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      expect(s.switchCooldownLeft, Duration.zero,
          reason: '誤入團隊是真實情境，冷卻期不該懲罰誤觸');
      expect(s.joinBlockedReason(team('別隊')), isNull);
    });

    test('送出申請後不可重複申請，撤回後可以再申請', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      final t = team('別隊');
      expect(s.applyToTeam(t), isTrue);
      expect(s.joinBlockedReason(t), contains('已送出'));
      expect(s.applyToTeam(t), isFalse);
      expect(s.sentApplications.length, 1);

      s.withdrawApplication(t.name);
      expect(s.joinBlockedReason(t), isNull);
    });

    test('申請自送出起算 168 小時逾期', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      s.applyToTeam(team('別隊'));
      final left = s.sentApplications.single.expiresAt.difference(s.now);
      expect(left.inHours, closeTo(168, 1));
    });
  });

  group('建立團隊', () {
    test('建立本身無門檻，但一人只能屬於一個團隊', () {
      final s = AppState();
      expect(s.createBlockedReason(), contains('先退出'));
      expect(s.createTeam('新隊'), isFalse);
    });

    test('換隊冷卻不擋建立，只擋加入別人的隊', () {
      final s = AppState()..leaveTeam();
      expect(s.switchCooldownLeft, greaterThan(Duration.zero));
      // 冷卻期的職責是避免既有團隊的名單與分數抖動，
      // 而自己開一支新隊不會動到任何既有團隊。
      expect(s.joinBlockedReason(team('別隊')), contains('冷卻'));
      expect(s.createBlockedReason(), isNull);
      expect(s.createTeam('新隊'), isTrue);
    });

    test('建立者預設為隊長，可見性預設公開', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      expect(s.createTeam('晨跑小隊'), isTrue);
      expect(s.myTeam!.name, '晨跑小隊');
      expect(s.myTeam!.isPublic, isTrue);
      expect(s.iAmLeader, isTrue);
      expect(s.myTeam!.members.single.role, TeamRole.leader);
    });

    test('可見性依建立時的指定值', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      s.createTeam('私密隊', isPublic: false);
      expect(s.myTeam!.isPublic, isFalse);
    });

    test('空白名稱不給建立', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      expect(s.createTeam('   '), isFalse);
      expect(s.myTeam, isNull);
    });

    test('新隊只有 1 人，本週期不列入排名但分數照常累積', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      expect(s.createTeam('新隊'), isTrue);
      expect(s.myTeamOnBoard!.rankEligible, isFalse);
      expect(
        teamRanking(s.boardTeams, TeamBoard.daily, kTeamMinSize)
            .any((t) => t.name == '新隊'),
        isFalse,
      );
    });

    test('建立後立刻解散，冷卻只擋加入，不擋再開一隊', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      expect(s.createTeam('第一隊'), isTrue);
      expect(s.teamJoinedAt, isNull, reason: '建立不是加入，不給無懲罰窗口');
      s.leaveTeam();
      expect(s.switchCooldownLeft, greaterThan(Duration.zero),
          reason: '退出仍照常起算冷卻');
      expect(s.joinBlockedReason(team('別隊')), contains('冷卻'));
      expect(s.createTeam('第二隊'), isTrue);
      expect(s.myTeam!.name, '第二隊');
    });

    test('無懲罰窗口只給加入的人 —— 剛加入就退出不觸發冷卻', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(minutes: 30))
        ..leaveTeam();
      expect(s.switchCooldownLeft, Duration.zero);
      expect(s.createTeam('馬上再開一隊'), isTrue);
    });
  });

  group('可見性變更與退出', () {
    AppState fresh() {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      s.createTeam('我的隊');
      return s;
    }

    test('隊長可事後變更可見性', () {
      final s = fresh();
      s.setTeamVisibility(false);
      expect(s.myTeam!.isPublic, isFalse);
      s.setTeamVisibility(true);
      expect(s.myTeam!.isPublic, isTrue);
    });

    test('改為私密時既有待處理的加入申請一律保留', () {
      final s = AppState();
      expect(s.iAmLeader, isTrue);
      final n = s.myTeam!.applications.length;
      expect(n, greaterThan(0));
      s.setTeamVisibility(false);
      expect(s.myTeam!.applications.length, n,
          reason: '申請已送出為既成事實，無聲作廢的體驗差');
    });

    test('只剩隊長一人時退出即解散，不進入無隊長狀態', () {
      final s = fresh();
      final o = s.leaveTeamOutcome();
      expect(o.disbanded, isTrue);
      expect(o.newLeader, isNull);
      s.leaveTeam();
      expect(s.myTeam, isNull);
      // 軟刪除：排行榜歷史紀錄存有團隊 ID，實體刪除會指向不存在的 ID。
      expect(s.disbandedTeams, contains('我的隊'));
    });

    test('隊長退出且尚有成員時，自動轉讓給最早加入的成員', () {
      final s = AppState();
      final o = s.leaveTeamOutcome();
      expect(o.disbanded, isFalse);
      expect(o.newLeader, s.myTeam!.members[1].name);
    });

    test('隊長轉讓後退出仍適用換隊冷卻，不因其為隊長而豁免', () {
      final s = AppState()..leaveTeam();
      expect(s.switchCooldownLeft, greaterThan(const Duration(hours: 11)));
    });

    test('冷卻期會自己走完 —— 它是倒數，不是到重開 App 為止的封鎖', () {
      final s = AppState()..leaveTeam();
      expect(s.joinBlockedReason(team('別隊')), contains('冷卻'));
      s.advanceDemoClock(kTeamSwitchCooldown + const Duration(minutes: 1));
      expect(s.switchCooldownLeft, Duration.zero);
      expect(s.joinBlockedReason(team('別隊')), isNull);
    });
  });

  group('走一遍團隊兩張', () {
    Future<void> boot(WidgetTester t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();
      await t.tap(find.text('社群').last);
      await t.pumpAndSettle();
      await t.tap(find.text('團隊').last);
      await t.pumpAndSettle();
    }

    testWidgets('我的團隊 → 團隊排行榜：只列同組別，自己的隊固定在最上面', (t) async {
      await boot(t);
      final list = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('看團隊排行榜'), 200, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(find.text('看團隊排行榜'));
      await t.pumpAndSettle();

      expect(find.byType(TeamLeaderboardScreen), findsOneWidget);
      expect(find.textContaining('距離前 3 還差'), findsOneWidget);
      // 我的隊 4 人組：榜上不該出現 5 人組的隊
      expect(find.text('增肌不增脂'), findsNothing);
      expect(find.text('週三練胸團'), findsWidgets);

      // 切到 5 人組
      await t.tap(find.text('5 人組'));
      await t.pumpAndSettle();
      expect(find.text('增肌不增脂'), findsWidgets);
      expect(find.textContaining('你的隊在 4 人組'), findsOneWidget);
    });

    testWidgets('限時榜與日常榜是兩份名次', (t) async {
      await boot(t);
      final list = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('看團隊排行榜'), 200, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(find.text('看團隊排行榜'));
      await t.pumpAndSettle();
      expect(find.textContaining('衡量訓練努力程度'), findsOneWidget);
      await t.tap(find.text('限時'));
      await t.pumpAndSettle();
      expect(find.textContaining('衡量動員參與率'), findsOneWidget);
    });

    testWidgets('沒有團隊時看得到建立團隊，建完就是隊長', (t) async {
      await boot(t);
      AppScope.of(t.element(find.byType(Scaffold).first))
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(AppButton, '建立團隊'));
      await t.pumpAndSettle();
      expect(find.byType(TeamCreateScreen), findsOneWidget);

      final create = find.widgetWithText(AppButton, '建立團隊');
      expect(t.widget<AppButton>(create).onPressed, isNull, reason: '沒名稱不給建');

      await t.enterText(find.byType(TextField).first, '晨跑小隊');
      await t.pumpAndSettle();
      await t.tap(find.text('私密'));
      await t.pumpAndSettle();
      await t.tap(create);
      await t.pumpAndSettle();

      expect(find.text('晨跑小隊'), findsWidgets);
      expect(find.text('私密'), findsWidgets);
      // 只剩自己一人 —— 按鈕要說的是解散，不是退出。
      final list = find.byType(Scrollable).last;
      await t.scrollUntilVisible(
          find.widgetWithText(AppButton, '解散團隊'), 200, scrollable: list);
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppButton, '解散團隊'), findsOneWidget);
    });

    testWidgets('重建團隊後，限時任務列的是新隊的成員', (t) async {
      await boot(t);
      final list = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('今日限時任務'), 200, scrollable: list);
      await t.pumpAndSettle();
      expect(find.text('早鳥訓練'), findsWidgets);
      expect(find.text('已完成 2 / 4 人'), findsOneWidget);

      final s = AppScope.of(t.element(find.byType(Scaffold).first))..leaveTeam();
      await t.pumpAndSettle();
      s.createTeam('新隊');
      await t.pumpAndSettle();

      final list2 = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('今日限時任務'), 200, scrollable: list2);
      await t.pumpAndSettle();
      expect(find.text('早鳥訓練'), findsNothing,
          reason: '名單屬於團隊，不該從任務裡複製一份');
      expect(find.text('核心怪物'), findsNothing);
      expect(find.text('已完成 0 / 1 人'), findsOneWidget);
    });

    testWidgets('完成後重建團隊：分數留在原隊，新隊從 0 起算並說明原因', (t) async {
      await boot(t);
      final s = AppScope.of(t.element(find.byType(Scaffold).first));
      s.completeTimedTask();
      await t.pumpAndSettle();

      final list = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('今日限時任務'), 200, scrollable: list);
      await t.pumpAndSettle();
      expect(find.text('已完成 3 / 4 人'), findsOneWidget);

      s.leaveTeam();
      await t.pumpAndSettle();
      s.createTeam('新隊');
      await t.pumpAndSettle();
      final list2 = find.byType(Scrollable).last;
      await t.scrollUntilVisible(find.text('今日限時任務'), 200, scrollable: list2);
      await t.pumpAndSettle();

      expect(find.text('已完成 0 / 1 人'), findsOneWidget);
      expect(find.textContaining('記在前一支隊伍帳上'), findsOneWidget);
    });

    testWidgets('冷卻訊息會自己倒數並消失，不是停在按下退出的那一刻', (t) async {
      await boot(t);
      final s = AppScope.of(t.element(find.byType(Scaffold).first))..leaveTeam();
      await t.pumpAndSettle();
      expect(find.textContaining('換隊冷卻剩餘'), findsOneWidget);
      // 冷卻不擋建立，只擋加入 —— 建立團隊全程都是亮的。
      expect(
        t.widget<AppButton>(find.widgetWithText(AppButton, '建立團隊')).onPressed,
        isNotNull,
      );

      // 只推進時鐘、不碰任何 setState：畫面自己要跟上。
      s.demoClockOffset = kTeamSwitchCooldown + const Duration(minutes: 1);
      await t.pump(const Duration(seconds: 2));
      expect(find.textContaining('換隊冷卻剩餘'), findsNothing);
      expect(find.textContaining('可以自己開一隊'), findsOneWidget);
    });

    testWidgets('私密團隊不出現在搜尋結果，公開的點得進詳情', (t) async {
      await boot(t);
      AppScope.of(t.element(find.byType(Scaffold).first)).leaveTeam();
      await t.pumpAndSettle();

      expect(find.text('硬舉愛好會'), findsNothing, reason: '私密團隊不可被搜尋');
      await t.tap(find.text('鐵人俱樂部'));
      await t.pumpAndSettle();
      expect(find.byType(TeamDetailScreen), findsOneWidget);
      expect(find.text('吳佩珊'), findsOneWidget);
      expect(find.text('隊長　·　階級 41'), findsOneWidget);

      // 剛退出 → 換隊冷卻中，按鈕要暗，且要寫出理由
      final btn = find.widgetWithText(AppButton, '申請加入');
      expect(t.widget<AppButton>(btn).onPressed, isNull);
      expect(find.textContaining('換隊冷卻中'), findsOneWidget);
    });
  });
}
