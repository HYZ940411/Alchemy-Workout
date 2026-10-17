// 團隊分數按月份分開存（`[QA-05]` 階段二，使用者裁決 D，2026-10-17）。
//
// 為什麼：管理員每月初按「結算上月團隊排行榜」，可能比月初晚好幾天。日常分數若只有一個
// 會被覆蓋的欄位，上個月的最終分數在他按按鈕之前就沒了。改成 `contribByMonth.{月份}.{uid}`、
// `timedByMonth.{月份}`：沒有「換月重設」，新月份只是多一個鍵，舊月份原封不動。
//
// 規則沒有可跑的模擬器（沒有 Java／emulator），所以跟 `team_timed_score_rule_test.dart` 一樣分兩層驗：
// 規則**文字**（函式在、掛進 allow update、沒放寬舊的），以及 App 實際寫出去的每一筆都過得了
// 「照規則條件式重寫的 Dart 對照版」。**對照版不是規則本身** —— 規則語法與巢狀 map 的語意
// 要到部署規則時才會被 Firebase 驗證。

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

/// 照 `monthlyContribOk()` 的條件式寫的對照版。
bool _ruleAllows({
  required Map<String, Map<String, int>> before,
  required Map<String, Map<String, int>> after,
  required String period,
  required String uid,
}) {
  final months = {
    for (final m in {...before.keys, ...after.keys})
      if (!_same(before[m], after[m])) m,
  };
  if (months.isEmpty) return true;
  if (months.length != 1 || !months.contains(period)) return false;
  if (!RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(period)) return false;
  final b = before[period] ?? const <String, int>{};
  final a = after[period];
  if (a == null) return false;
  final changed = {
    for (final k in {...b.keys, ...a.keys})
      if (b[k] != a[k]) k,
  };
  return changed.every((k) => k == uid) && (a[uid] ?? 0) >= (b[uid] ?? 0);
}

bool _same(Map<String, int>? a, Map<String, int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  return a.entries.every((e) => b[e.key] == e.value);
}

void main() {
  group('teamMonthKey：月份以 04:00 換日為界', () {
    test('一般日子', () {
      expect(teamMonthKey(DateTime(2026, 10, 17, 12)), '2026-10');
    });

    test('每月 1 日 03:59 還屬上個月，04:00 起才是新的月', () {
      expect(teamMonthKey(DateTime(2026, 11, 1, 3, 59)), '2026-10');
      expect(teamMonthKey(DateTime(2026, 11, 1, 4, 0)), '2026-11');
    });

    test('跨年：1 月 1 日 03:59 還是去年 12 月', () {
      expect(teamMonthKey(DateTime(2027, 1, 1, 3, 59)), '2026-12');
      expect(teamMonthKey(DateTime(2027, 1, 1, 4)), '2027-01');
    });
  });

  group('規則文字', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('match /teams/{teamId}');
    final block = rules.substring(
      i,
      rules.indexOf('match /requests/{targetUid}', i),
    );

    test('有 monthlyContribOk()：只動一個月份、只動自己、只能往上，並掛進 allow update', () {
      expect(block, contains('function monthlyContribOk()'));
      expect(block, contains("'contribByMonth'"));
      expect(block, contains('hasOnly([p])'));
      expect(block, contains('hasOnly([request.auth.uid])'));
      expect(block, contains('>= before.get(p, {}).get(request.auth.uid, 0)'));
      final upd = block.substring(block.indexOf('allow update'));
      expect(
          upd.substring(0, upd.indexOf('&& (')), contains('monthlyContribOk()'));
    });

    test('月份格式被規則限制（YYYY-MM）—— 兩個函式各自都要有', () {
      final daily = block.substring(block.indexOf('function monthlyContribOk()'),
          block.indexOf('function timedMonthOk()'));
      final timed = block.substring(block.indexOf('function timedMonthOk()'),
          block.indexOf('allow update'));
      const guard = r"p.matches('^[0-9]{4}-[0-9]{2}$')";
      expect(daily, contains(guard), reason: '日常');
      expect(timed, contains(guard), reason: '限時');
    });

    test('沒有放寬舊的三道：貢獻、完成名單、限時分數', () {
      final upd = block.substring(block.indexOf('allow update'));
      final head = upd.substring(0, upd.indexOf('&& ('));
      expect(
          head,
          allOf(contains('contribOk()'), contains('timedOk()'),
              contains('timedScoreOk()')));
    });
  });

  group('寫入與讀回', () {
    late FakeFirebaseFirestore db;
    FirestoreTeams as(String uid, {DateTime Function()? clock}) =>
        FirestoreTeams(uid: uid, firestore: db, clock: clock);
    setUp(() => db = FakeFirebaseFirestore());

    Future<void> makeTeam() => as('a').create(
          CloudTeam(
            id: 't1',
            name: '測試隊',
            members: {
              for (final u in ['a', 'b'])
                u: CloudMember(
                    name: u.toUpperCase(),
                    rank: 1,
                    role: u == 'a' ? TeamRole.leader : TeamRole.member,
                    joinedAt: DateTime(2026)),
            },
          ),
        );

    Future<Map<String, dynamic>> raw() async =>
        (await db.collection('teams').doc('t1').get()).data()!;

    Map<String, Map<String, int>> byMonth(Map<String, dynamic> d) => {
          for (final e in ((d['contribByMonth'] as Map?) ?? const {}).entries)
            e.key as String: {
              for (final x in (e.value as Map).entries)
                x.key as String: (x.value as num).round(),
            },
        };

    DateTime oct() => DateTime(2026, 10, 17, 12);
    DateTime nov() => DateTime(2026, 11, 3, 12);

    test('新建的隊：按月份分開存的兩個欄位是空的，沒有舊的 contributions／timedScore', () async {
      await makeTeam();
      final d = await raw();
      expect(d['contribByMonth'], isEmpty);
      expect(d['timedByMonth'], isEmpty);
      expect(d.containsKey('contributions'), isFalse);
      expect(d.containsKey('timedScore'), isFalse);
    });

    test('加分寫進本月那一格，並帶 dailyPeriod（規則靠它知道動的是哪個月）', () async {
      await makeTeam();
      await as('a', clock: oct).addScore('t1', 'a', 10);
      await as('a', clock: oct).addScore('t1', 'a', 10);
      await as('b', clock: oct).addScore('t1', 'b', 30);
      final d = await raw();
      expect(byMonth(d), {
        '2026-10': {'a': 20, 'b': 30},
      });
      expect(d['dailyPeriod'], '2026-10');
      expect(d.containsKey('contributions'), isFalse,
          reason: '舊欄位不再寫，否則兩份對不起來');
    });

    test('換月：十一月多一個鍵，十月原封不動', () async {
      await makeTeam();
      await as('a', clock: oct).addScore('t1', 'a', 40);
      await as('a', clock: nov).addScore('t1', 'a', 10);
      expect(byMonth(await raw()), {
        '2026-10': {'a': 40},
        '2026-11': {'a': 10},
      });
    });

    test('讀回：contributions 是「本月」那一份，完整的按月份紀錄另外保留給結算', () async {
      await makeTeam();
      await as('a', clock: oct).addScore('t1', 'a', 40);
      await as('a', clock: nov).addScore('t1', 'a', 10);

      final inNov = (await as('a', clock: nov).myTeam())!;
      expect(inNov.contributions, {'a': 10}, reason: '十一月看到的本月只有十一月的');
      expect(inNov.contribByMonth['2026-10'], {'a': 40},
          reason: '十月的最終分數還在 —— 管理員晚幾天按結算也讀得到');

      final inOct = (await as('a', clock: oct).myTeam())!;
      expect(inOct.contributions, {'a': 40});
    });

    test('本月還沒人得分：本月是空的，不是上個月的', () async {
      await makeTeam();
      await as('a', clock: oct).addScore('t1', 'a', 40);
      final inNov = (await as('a', clock: nov).myTeam())!;
      expect(inNov.contributions, isEmpty);
    });

    test('delta 為 0 不寫', () async {
      await makeTeam();
      await as('a', clock: oct).addScore('t1', 'a', 0);
      expect(byMonth(await raw()), isEmpty);
    });

    test('04:00 之前的分數記在上個月（與排行榜週期同一個時點）', () async {
      await makeTeam();
      await as('a', clock: () => DateTime(2026, 11, 1, 3, 59))
          .addScore('t1', 'a', 10);
      await as('a', clock: () => DateTime(2026, 11, 1, 4, 0))
          .addScore('t1', 'a', 5);
      expect(byMonth(await raw()), {
        '2026-10': {'a': 10},
        '2026-11': {'a': 5},
      });
    });
  });

  group('App 實際寫出去的每一筆都過得了規則', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    test('三人、跨三個月、反覆加分，每一筆寫入前後都過規則對照版', () async {
      final src = {
        for (final u in ['a', 'b', 'c'])
          u: FirestoreTeams(uid: u, firestore: db, clock: () => DateTime(2026)),
      };
      await src['a']!.create(CloudTeam(
        id: 't1',
        name: '測試隊',
        members: {
          for (final u in ['a', 'b', 'c'])
            u: CloudMember(
                name: u,
                rank: 1,
                role: u == 'a' ? TeamRole.leader : TeamRole.member,
                joinedAt: DateTime(2026)),
        },
      ));

      Future<Map<String, Map<String, int>>> read() async {
        final d = (await db.collection('teams').doc('t1').get()).data()!;
        return {
          for (final e in ((d['contribByMonth'] as Map?) ?? const {}).entries)
            e.key as String: {
              for (final x in (e.value as Map).entries)
                x.key as String: (x.value as num).round(),
            },
        };
      }

      Future<String> period() async =>
          ((await db.collection('teams').doc('t1').get()).data()!['dailyPeriod']
              as String?) ??
          '';

      final steps = <(String, DateTime, int)>[
        ('a', DateTime(2026, 10, 5, 12), 10),
        ('b', DateTime(2026, 10, 5, 13), 20),
        ('a', DateTime(2026, 10, 6, 12), 30),
        ('c', DateTime(2026, 11, 4, 12), 10),
        ('a', DateTime(2026, 11, 4, 13), 10),
        ('b', DateTime(2026, 12, 9, 12), 50),
        ('b', DateTime(2026, 12, 9, 13), 50),
      ];
      for (final (u, at, n) in steps) {
        final before = await read();
        await FirestoreTeams(uid: u, firestore: db, clock: () => at)
            .addScore('t1', u, n);
        final after = await read();
        expect(
          _ruleAllows(
              before: before, after: after, period: await period(), uid: u),
          isTrue,
          reason: '$u 於 $at 加 $n：$before → $after 會被規則拒絕',
        );
      }
      expect(await read(), {
        '2026-10': {'a': 40, 'b': 20},
        '2026-11': {'c': 10, 'a': 10},
        '2026-12': {'b': 100},
      });
    });

    test('對照版本身：動別人那格、往下改、同時動兩個月份、改別的月份、格式錯都會被擋', () {
      bool ok(Map<String, Map<String, int>> b, Map<String, Map<String, int>> a,
              String p, String u) =>
          _ruleAllows(before: b, after: a, period: p, uid: u);
      final base = {
        '2026-10': {'a': 10, 'b': 20},
      };
      expect(
          ok(base, {'2026-10': {'a': 15, 'b': 20}}, '2026-10', 'a'), isTrue);
      expect(
          ok(base, {'2026-10': {'a': 10, 'b': 99}}, '2026-10', 'a'), isFalse,
          reason: '動到隊友那格');
      expect(
          ok(base, {'2026-10': {'a': 5, 'b': 20}}, '2026-10', 'a'), isFalse,
          reason: '自己的分數往下改');
      expect(
          ok(base, {'2026-10': {'a': 11, 'b': 20}}, '2026-11', 'a'), isFalse,
          reason: '帶的月份是十一月，卻去動十月');
      expect(
          ok(base, {
            '2026-10': {'a': 11, 'b': 20},
            '2026-11': {'a': 1},
          }, '2026-11', 'a'),
          isFalse,
          reason: '一次動兩個月份');
      expect(ok(base, {}, '2026-10', 'a'), isFalse, reason: '把整個月份刪掉');
      expect(ok({}, {'bad': {'a': 1}}, 'bad', 'a'), isFalse, reason: '月份格式錯');
      expect(ok(base, base, '2026-10', 'a'), isTrue, reason: '沒動任何月份');
    });
  });
}
