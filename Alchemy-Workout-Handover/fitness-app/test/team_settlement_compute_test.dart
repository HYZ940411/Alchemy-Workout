// 團隊排行榜月結算的計算（`[QA-05]`，使用者裁決 D，2026-10-17）：純函式，只看傳進來的隊伍資料。
//
// 日常榜依人數分組、限時榜不分組；獎勵走百分比級距；同分並列同名次；
// 分數是 0 的隊結果照寫、獎勵是空的；已解散與從未成局的隊不上榜。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/settlement_data.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/leaderboard.dart';

const _p = '2026-10';

/// [size] 人的隊（曾達最高人數 [peak]，預設同 [size]），十月日常 [daily] 分、限時 [timed] 分。
CloudTeam _team(
  String id,
  int size, {
  int daily = 0,
  int timed = 0,
  int? peak,
  bool disbanded = false,
  Map<String, Map<String, int>>? byMonth,
  Map<String, int>? timedByMonth,
}) =>
    CloudTeam(
      id: id,
      name: '隊$id',
      members: {
        for (var i = 0; i < size; i++)
          '$id-u$i': CloudMember(
              name: 'U$i',
              rank: 1,
              role: i == 0 ? TeamRole.leader : TeamRole.member,
              joinedAt: DateTime(2026)),
      },
      peakSize: peak ?? size,
      disbanded: disbanded,
      contribByMonth: byMonth ??
          {
            _p: {'$id-u0': daily},
          },
      timedByMonth: timedByMonth ?? {_p: timed},
    );

TeamSettlementResult _of(List<TeamSettlementResult> r, String id) =>
    r.firstWhere((x) => x.teamId == id);

void main() {
  test('previousMonthKey：一般月份與跨年', () {
    expect(previousMonthKey('2026-10'), '2026-09');
    expect(previousMonthKey('2026-01'), '2025-12');
    expect(previousMonthKey('2026-12'), '2026-11');
  });

  group('日常榜依人數分組', () {
    test('三個人數組各自排名：每組第 1 名都是第 1 名', () {
      final r = computeTeamSettlement([
        _team('a', 3, daily: 100),
        _team('b', 4, daily: 50),
        _team('c', 5, daily: 10),
      ], _p);
      expect(_of(r, 'a').daily.place, 1);
      expect(_of(r, 'b').daily.place, 1, reason: '4 人組只有它，不跟 3 人組比');
      expect(_of(r, 'c').daily.place, 1);
      expect(_of(r, 'a').daily.group, '3 人組');
      expect(_of(r, 'b').daily.group, '4 人組');
      expect(_of(r, 'c').daily.group, '5 人組');
    });

    test('同組內依分數排名，同分並列、並列後順延跳號', () {
      final r = computeTeamSettlement([
        _team('a', 3, daily: 100),
        _team('b', 3, daily: 80),
        _team('c', 3, daily: 80),
        _team('d', 3, daily: 10),
      ], _p);
      expect([for (final id in 'abcd'.split('')) _of(r, id).daily.place],
          [1, 2, 2, 4]);
    });

    test('分組看「曾達最高人數」，不是結算當下人數', () {
      // 招滿 5 人後踢到 3 人：仍在 5 人組。
      final r = computeTeamSettlement([
        _team('a', 3, daily: 100, peak: 5),
        _team('b', 3, daily: 10),
      ], _p);
      expect(_of(r, 'a').daily.group, '5 人組');
      expect(_of(r, 'b').daily.group, '3 人組');
    });
  });

  group('限時榜不分組', () {
    test('不同人數的隊排同一張榜，組別標「全部隊伍」', () {
      final r = computeTeamSettlement([
        _team('a', 3, timed: 30),
        _team('b', 4, timed: 80),
        _team('c', 5, timed: 50),
      ], _p);
      expect(_of(r, 'b').timed.place, 1);
      expect(_of(r, 'c').timed.place, 2);
      expect(_of(r, 'a').timed.place, 3);
      expect(_of(r, 'a').timed.group, '全部隊伍');
    });
  });

  group('獎勵', () {
    test('10 隊同組：第 1 名 90＋AI 1、第 2 名 50、第 3–5 名 25、其餘有分數的 10', () {
      final r = computeTeamSettlement([
        for (var i = 0; i < 10; i++) _team('t$i', 3, daily: 1000 - i * 10),
      ], _p);
      expect(_of(r, 't0').daily.prize.coins, 90);
      expect(_of(r, 't0').daily.prize.aiCredits, 1);
      expect(_of(r, 't1').daily.prize.coins, 50);
      for (final i in [2, 3, 4]) {
        expect(_of(r, 't$i').daily.prize.coins, 25);
      }
      for (final i in [5, 9]) {
        expect(_of(r, 't$i').daily.prize.coins, 10);
      }
    });

    test('限時榜用自己那張表：第 1 名 100＋AI 2', () {
      final r = computeTeamSettlement([
        _team('a', 3, timed: 100),
        _team('b', 3, timed: 10),
      ], _p);
      expect(_of(r, 'a').timed.prize.coins, 100);
      expect(_of(r, 'a').timed.prize.aiCredits, 2);
    });

    test('分數是 0：結果照寫，獎勵是空的（沒得獎也要留紀錄）', () {
      final r = computeTeamSettlement([
        _team('a', 3, daily: 100, timed: 50),
        _team('b', 3, daily: 0, timed: 0),
      ], _p);
      expect(_of(r, 'b').daily.prize.isEmpty, isTrue);
      expect(_of(r, 'b').timed.prize.isEmpty, isTrue);
      expect(_of(r, 'b').daily.place, 2);
    });
  });

  group('誰上榜', () {
    test('已解散的隊不上榜', () {
      final r = computeTeamSettlement([
        _team('a', 3, daily: 100),
        _team('x', 3, daily: 999, disbanded: true),
      ], _p);
      expect(r.map((e) => e.teamId), ['a']);
      expect(_of(r, 'a').daily.place, 1, reason: '解散的隊不佔名次');
    });

    test('本月從未成局（曾達最高人數 < 3）的隊不上榜、不領獎勵', () {
      final r = computeTeamSettlement([
        _team('a', 3, daily: 10),
        _team('x', 2, daily: 999, peak: 2),
      ], _p);
      expect(r.map((e) => e.teamId), ['a']);
    });

    test('曾經成局、結算當下跌破 3 人的隊仍保留資格', () {
      final r = computeTeamSettlement([
        _team('a', 2, daily: 100, peak: 4),
      ], _p);
      expect(r.single.daily.group, '4 人組');
      expect(r.single.daily.prize.coins, 90);
    });

    test('沒有任何隊伍符合資格：空結果', () {
      expect(computeTeamSettlement([_team('x', 2, peak: 2)], _p), isEmpty);
      expect(computeTeamSettlement([], _p), isEmpty);
    });
  });

  group('只看那個月的分數', () {
    test('別的月份的分數不算進來', () {
      final r = computeTeamSettlement([
        _team('a', 3, byMonth: {
          '2026-09': {'a-u0': 9999},
          _p: {'a-u0': 10, 'a-u1': 5},
        }, timedByMonth: {
          '2026-09': 500,
          _p: 20,
        }),
        _team('b', 3, daily: 12, timed: 0),
      ], _p);
      expect(_of(r, 'a').daily.score, 15, reason: '十月各成員加總');
      expect(_of(r, 'a').timed.score, 20);
      expect(_of(r, 'a').daily.place, 1);
    });

    test('日常分數是各成員那格加總', () {
      final r = computeTeamSettlement([
        _team('a', 3, byMonth: {
          _p: {'a-u0': 10, 'a-u1': 20, 'a-u2': 30, '已離隊的人': 40},
        }),
      ], _p);
      expect(r.single.daily.score, 100, reason: '退出的人的貢獻仍計入（分數計入即歸團隊所有）');
    });
  });

  test('結果帶著結算當下的成員 uid 名單與隊名', () {
    final r = computeTeamSettlement([_team('a', 3, daily: 1)], _p).single;
    expect(r.memberUids, ['a-u0', 'a-u1', 'a-u2']);
    expect(r.teamName, '隊a');
    expect(r.period, _p);
    expect(r.daily.board, Board.teamDaily);
    expect(r.timed.board, Board.teamTimed);
  });
}
