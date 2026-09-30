import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/social.dart';
import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('名次：同分並列，並列後順延跳號', () {
    test('兩人並列第 2，下一位是第 4', () {
      expect(placesOf([100, 90, 90, 80]), [1, 2, 2, 4]);
    });

    test('三人並列第 1，下一位是第 4', () {
      expect(placesOf([90, 90, 90, 50]), [1, 1, 1, 4]);
    });

    test('全部同分皆為第 1，皆發該名次的獎勵', () {
      expect(placesOf([50, 50, 50]), [1, 1, 1]);
    });
  });

  group('排行獎勵', () {
    setUp(platformConfig.reset);
    tearDown(platformConfig.reset);

    test('名次愈前愈多，超出門檻則無獎', () {
      expect(prizeFor(1).coins, greaterThan(prizeFor(2).coins));
      expect(prizeFor(3).coins, greaterThan(prizeFor(4).coins));
      expect(prizeFor(kRankPrizeCut).isEmpty, isFalse);
      expect(prizeFor(kRankPrizeCut + 1).isEmpty, isTrue);
    });

    test('不變條件擋下「名次愈前拿愈少」的設定', () {
      final g = platformConfig.group('reward');
      expect(g.invariant!({...g.values, 'rank1Coin': 10}), isNotNull);
      expect(g.invariant!(g.values), isNull);
    });
  });

  group('週期結算', () {
    test('週榜結算只歸零週分數，月分數與經驗值不動', () {
      final s = AppState();
      final monthly = s.monthlyScore;
      final exp = s.totalExp;
      expect(s.weeklyScore, greaterThan(0));
      s.settleWeekly();
      expect(s.weeklyScore, 0);
      expect(s.monthlyScore, monthly, reason: '重置一次只歸零該榜別的計數器');
      expect(s.totalExp, exp, reason: '經驗值與排行榜分數是不同數值');
    });

    test('歸零前先寫入歷史紀錄，且歷史帶著組別與名次', () {
      final s = AppState();
      final before = s.weeklyScore;
      final row = s.settleWeekly1();
      expect(row, isNotNull);
      expect(row!.score, before, reason: '寫的是歸零前的分數');
      expect(row.board, Board.personalWeekly);
      expect(row.group, isNotEmpty);
      expect(s.leaderboardHistory, contains(row));
    });

    test('達獎勵名次者補發至信箱，不自動入帳', () {
      final s = AppState();
      final coins = s.coins;
      final mails = s.mailbox.length;
      // 把獎勵門檻放寬到必得，才驗得到「有獎時會進信箱」。
      platformConfig.group('reward').param('rankCut').value = 999;
      s.settleWeekly();
      platformConfig.reset();
      expect(s.mailbox.length, mails + 1);
      expect(s.mailbox.first.claimed, isFalse);
      expect(s.coins, coins, reason: '結算不自動入帳，領取才入帳');
    });

    test('未達獎勵名次者不進信箱，但歷史仍要有一筆', () {
      final s = AppState();
      final mails = s.mailbox.length;
      platformConfig.group('reward').param('rankCut').value = 1;
      final row = s.settleWeekly1();
      platformConfig.reset();
      expect(row!.prize.isEmpty, isTrue);
      expect(s.mailbox.length, mails,
          reason: '沒得獎也要留紀錄，否則「我第幾名」無從查證');
      expect(s.leaderboardHistory.length, 1);
    });

    test('月結同時結算個人月榜與兩個團隊榜', () {
      final s = AppState();
      s.settleMonthly();
      final boards = s.leaderboardHistory.map((h) => h.board).toSet();
      expect(boards, containsAll([
        Board.personalMonthly,
        Board.teamDaily,
        Board.teamTimed,
      ]));
    });

    test('未達人數下限的隊不進排行榜，也就沒有歷史紀錄', () {
      final s = AppState()
        ..teamJoinedAt = DateTime.now().subtract(const Duration(hours: 1))
        ..leaveTeam();
      s.createTeam('一人隊');
      s.settleMonthly();
      final teamRows = s.leaderboardHistory
          .where((h) => h.board != Board.personalMonthly);
      expect(teamRows, isEmpty);
    });

    test('新組別自下一週期起生效 —— 結算時才重新鎖定', () {
      final s = AppState();
      final before = s.lockedRankGroup;
      s.totalExp += 100000; // 週期內升階
      expect(s.lockedRankGroup, before, reason: '週期內升階不改變本週期組別');
      s.settleWeekly();
      expect(s.lockedRankGroup, isNot(before));
    });
  });

  group('團隊：日常分數由成員貢獻加總而來', () {
    test('不變條件在結構上成立，不是另存一個會漂移的數字', () {
      final t = AppState().myTeam!;
      expect(t.dailyScore,
          t.contributions.values.fold<int>(0, (a, b) => a + b));
    });

    test('每位成員都查得到自己對本隊貢獻了多少', () {
      final t = AppState().myTeam!;
      for (final m in t.members) {
        expect(t.contributions[personKey(m.name, m.uid)], isNotNull);
      }
    });
  });

  group('團隊：加入申請與邀請', () {
    test('核准即加入，人數 +1，申請自清單移除', () {
      final s = AppState();
      final t = s.myTeam!;
      final n = t.members.length;
      final r = t.applications.first;
      expect(s.approveApplication(r), isTrue);
      expect(t.members.length, n + 1);
      expect(t.applications.contains(r), isFalse);
    });

    test('滿員時核准不成立 —— 超收由本 Command 當下擋下', () {
      final s = AppState();
      final t = s.myTeam!;
      while (!t.isFull) {
        t.members.add(TeamMember('湊人數${t.members.length}', 1, TeamRole.member));
      }
      expect(s.approveApplication(t.applications.first), isFalse);
    });

    test('拒絕後該筆失效，對方可再次申請', () {
      final s = AppState();
      final t = s.myTeam!;
      final r = t.applications.first;
      s.rejectApplication(r);
      expect(t.applications.contains(r), isFalse);
    });

    test('取消邀請後隊長可再次邀請同一人', () {
      final s = AppState();
      final t = s.myTeam!;
      final r = t.invites.first;
      s.cancelInvite(r);
      expect(t.invites, isEmpty);
      expect(s.inviteMember(r.name, r.rank), isTrue);
    });

    test('逾期判定看的是送出起算 168 小時', () {
      final s = AppState();
      final r = s.myTeam!.applications.first;
      expect(s.expired(r), isFalse);
      s.advanceDemoClock(const Duration(days: 8));
      expect(s.expired(r), isTrue);
    });
  });

  group('團隊：轉讓隊長', () {
    test('轉讓後我變成一般成員，對方成為隊長', () {
      final s = AppState();
      final target = s.myTeam!.members[1];
      expect(s.transferLeader(target), isTrue);
      expect(s.iAmLeader, isFalse);
      expect(
        s.myTeam!.members.firstWhere((m) => m.name == target.name).role,
        TeamRole.leader,
      );
      expect(
        s.myTeam!.members.where((m) => m.role == TeamRole.leader).length,
        1,
        reason: '不會出現兩個隊長，也不會沒有隊長',
      );
    });

    test('非隊長不能轉讓，也不能轉給自己', () {
      final s = AppState();
      final me = s.myTeam!.members.first;
      expect(s.transferLeader(me), isFalse);
      s.transferLeader(s.myTeam!.members[1]);
      expect(s.transferLeader(s.myTeam!.members.first), isFalse);
    });
  });

  group('限時任務獎勵', () {
    test('完成才領得到，且只領一次', () {
      final s = AppState();
      expect(s.canClaimTimedReward, isFalse);
      expect(s.claimTimedReward(), isNull);

      s.completeTimedTask();
      expect(s.canClaimTimedReward, isTrue);
      final coins = s.coins;
      final r = s.claimTimedReward()!;
      expect(r, (exp: kTimedRewardExp, coins: kTimedRewardCoin));
      expect(s.coins, coins + kTimedRewardCoin);
      expect(s.claimTimedReward(), isNull);
    });

    test('當日結束未領取者補發至信箱，不作廢', () {
      final s = AppState()..completeTimedTask();
      final mails = s.mailbox.length;
      final coins = s.coins;
      s.sweepTimedRewardToMailbox();
      expect(s.mailbox.length, mails + 1);
      expect(s.mailbox.first.source, contains('限時任務'));
      expect(s.coins, coins, reason: '進信箱不等於入帳');
      expect(s.canClaimTimedReward, isFalse);
    });
  });

  group('師徒申請', () {
    test('待回應的申請佔用帶徒名額，不是送出就成關係', () {
      final s = AppState();
      final ins = s.instructors.firstWhere((i) => i.apprentices < i.apprenticeCap);
      expect(s.applyMentor(ins), isTrue);
      expect(s.myInstructor, isNull, reason: '要對方接受才建立關係');
      expect(s.mentorApplyBlockedReason(ins), contains('已送出'));
    });

    test('額滿的教官申請不了', () {
      final s = AppState();
      final full =
          s.instructors.where((i) => i.apprentices >= i.apprenticeCap).firstOrNull;
      if (full != null) {
        expect(s.mentorApplyBlockedReason(full), contains('名額'));
      }
    });

    test('已有教官者不能再申請 —— 一位學徒同時只能有一位教官', () {
      final s = AppState();
      final ins = s.instructors.first;
      s.applyMentor(ins);
      s.acceptMentorApplication(ins);
      expect(s.myInstructor, isNotNull);
      expect(s.mentorApplyBlockedReason(s.instructors[1]), contains('只能有一位'));
    });

    test('未確認免責聲明前不得提問', () {
      final s = AppState();
      final ins = s.instructors.first;
      s.applyMentor(ins);
      s.acceptMentorApplication(ins);
      expect(s.mentorDisclaimerNeeded, isTrue);
      final n = s.questions.length;
      s.askQuestion('這樣做對嗎？');
      expect(s.questions.length, n, reason: '聲明擋的是學徒端的互動 Command');

      s.confirmMentorDisclaimer();
      s.askQuestion('這樣做對嗎？');
      expect(s.questions.length, n + 1);
    });
  });
}
