// 團隊榜（日常／限時）的獎勵照規格：百分比級距，不是名次制（`[QA-05]`，使用者 2026-10-17 裁決 A）。
//
// 規格〈團隊日常排行獎勵已發放〉〈團隊限時排行獎勵已發放〉：
// 前 5%／前 20%／前 50%／其餘有參加的；名次門檻依組內實際隊數無條件進位、至少 1 隊；
// AI 點數只發最高檔；「有參加」＝本週期分數 > 0。個人榜不動，仍是名次制。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

RankPrize _daily(int place, int teams, {int score = 100}) => teamPrizeFor(
    Board.teamDaily,
    place: place,
    teamsInGroup: teams,
    score: score);

RankPrize _timed(int place, int teams, {int score = 100}) => teamPrizeFor(
    Board.teamTimed,
    place: place,
    teamsInGroup: teams,
    score: score);

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('teamPrizeFor：級距與進位', () {
    test('10 隊：前 5% 進位為 1 隊、前 20% 為 2 隊、前 50% 為 5 隊', () {
      expect(_daily(1, 10).coins, 90);
      expect(_daily(1, 10).aiCredits, 1, reason: 'AI 點數只發最高檔');
      expect(_daily(2, 10).coins, 50);
      expect(_daily(2, 10).aiCredits, 0);
      for (final p in [3, 4, 5]) {
        expect(_daily(p, 10).coins, 25, reason: '第 $p 名在前 50%');
      }
      for (final p in [6, 10]) {
        expect(_daily(p, 10).coins, 10, reason: '第 $p 名是其餘參與者');
      }
    });

    test('3 隊：進位後最高檔 1 隊、次高檔也只有 1 隊，第三檔含第 2 名', () {
      expect(_daily(1, 3).coins, 90);
      expect(_daily(2, 3).coins, 25, reason: '前 20% 進位仍是 1 隊，第 2 名落在前 50%（進位為 2 隊）');
      expect(_daily(3, 3).coins, 10);
    });

    test('只有 1 隊也是最高檔（至少 1 隊）', () {
      expect(_daily(1, 1).coins, 90);
    });

    test('分數是 0 的隊什麼都沒有（沒參加），不論名次', () {
      expect(_daily(1, 10, score: 0).isEmpty, isTrue);
      expect(_daily(10, 10, score: 0).isEmpty, isTrue);
    });

    test('限時榜用自己那張表', () {
      expect(_timed(1, 10).coins, 100);
      expect(_timed(1, 10).aiCredits, 2);
      expect(_timed(2, 10).coins, 55);
      expect(_timed(3, 10).coins, 25);
      expect(_timed(10, 10).coins, 10);
    });

    test('數額與門檻是平台參數：管理員改了就跟著變', () {
      final g = platformConfig.group('reward');
      g.param('teamTier1Pct').value = 10;
      g.param('teamDailyT1Coin').value = 777;
      expect(_daily(1, 10).coins, 777);
      // 前 10% 的 10 隊組仍是 1 隊；改成 30% 之後前 3 隊都在最高檔。
      g.param('teamTier1Pct').value = 30;
      g.param('teamTier2Pct').value = 40;
      expect(_daily(3, 10).coins, 777);
    });
  });

  group('平台參數的不變條件', () {
    test('預設值通過', () {
      final g = platformConfig.group('reward');
      expect(g.invariant!(g.values), isNull);
    });

    test('門檻要由小到大', () {
      final g = platformConfig.group('reward');
      expect(g.invariant!({...g.values, 'teamTier2Pct': 5}), isNotNull);
      expect(g.invariant!({...g.values, 'teamTier3Pct': 120}), isNotNull);
      expect(g.invariant!({...g.values, 'teamTier1Pct': 0}), isNotNull);
    });

    test('檔位愈前獎勵不得愈少', () {
      final g = platformConfig.group('reward');
      expect(g.invariant!({...g.values, 'teamDailyT2Coin': 999}), isNotNull);
      expect(g.invariant!({...g.values, 'teamTimedT4Coin': 999}), isNotNull);
    });
  });

  group('settleBoard：團隊榜真的走百分比級距', () {
    PublicTeam other(String name, int daily, int timed) => PublicTeam(
        name, 3, 5,
        id: 'x-$name', dailyScore: daily, timedScore: timed);

    /// 我的隊（3 人組）日常 [daily]、限時 [timed]；另有 9 支同組隊，分數 10..90（日常）與 10..90（限時）。
    AppState state({required int daily, required int timed}) {
      final s = AppState()
        ..displayName = '阿昶'
        ..myUid = 'u1';
      s.publicTeams = [
        for (var i = 1; i <= 9; i++) other('隊$i', i * 10, i * 10),
      ];
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
        lockedGroupSize: 3,
      );
      return s;
    }

    test('日常榜第 1 名（10 隊）：信箱 90 金幣 ＋ 1 點 AI，歷史也寫這個', () {
      final s = state(daily: 1000, timed: 0);
      final mails = s.mailbox.length;
      final row = s.settleBoard(Board.teamDaily)!;
      expect(row.place, 1);
      expect(row.prize.coins, 90);
      expect(row.prize.aiCredits, 1);
      expect(s.mailbox.length, mails + 1);
      expect(s.mailbox.first.coins, 90);
      expect(s.mailbox.first.aiCredits, 1);
      expect(s.mailbox.first.exp, 0, reason: '規格的團隊獎勵沒有經驗值');
    });

    test('日常榜第 2 名：50 金幣，沒有 AI 點數', () {
      final s = state(daily: 85, timed: 0); // 最高的別隊是 90
      final row = s.settleBoard(Board.teamDaily)!;
      expect(row.place, 2);
      expect(row.prize.coins, 50);
      expect(row.prize.aiCredits, 0);
    });

    test('同分並列第 1：兩隊都拿最高檔（我跟隊 9 同為 90）', () {
      final s = state(daily: 90, timed: 0);
      final row = s.settleBoard(Board.teamDaily)!;
      expect(row.place, 1, reason: '並列同一名次');
      expect(row.prize.coins, 90);
      expect(row.prize.aiCredits, 1);
    });

    test('日常榜最後一名但有分數：拿其餘參與者的 10 金幣', () {
      final s = state(daily: 5, timed: 0); // 全場最低
      final row = s.settleBoard(Board.teamDaily)!;
      expect(row.place, 10);
      expect(row.prize.coins, 10);
    });

    test('日常榜沒有分數：歷史照寫，但信箱沒有獎勵', () {
      final s = state(daily: 0, timed: 0);
      final mails = s.mailbox.length;
      final row = s.settleBoard(Board.teamDaily)!;
      expect(row.prize.isEmpty, isTrue);
      expect(s.mailbox.length, mails);
      expect(s.leaderboardHistory, contains(row), reason: '沒得獎也要留紀錄');
    });

    test('限時榜第 1 名：100 金幣 ＋ 2 點 AI', () {
      final s = state(daily: 0, timed: 1000);
      final row = s.settleBoard(Board.teamTimed)!;
      expect(row.place, 1);
      expect(row.prize.coins, 100);
      expect(row.prize.aiCredits, 2);
    });

    test('領取信箱獎勵：AI 點數真的進永久餘額', () {
      final s = state(daily: 1000, timed: 0);
      s.settleBoard(Board.teamDaily);
      final ai = s.aiPermanent;
      final coins = s.coins;
      s.claimMail(s.mailbox.first);
      expect(s.aiPermanent, ai + 1);
      expect(s.coins, coins + 90);
    });

    test('個人榜不受影響，仍是名次制', () {
      final p = prizeFor(1);
      expect(p.coins, 300, reason: '個人榜第 1 名仍是名次制的 300');
      expect(p.aiCredits, 0);
    });
  });
}
