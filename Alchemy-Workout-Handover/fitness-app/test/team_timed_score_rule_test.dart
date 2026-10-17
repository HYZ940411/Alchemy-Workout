// 團隊限時分數的安全規則（使用者裁決 A，2026-10-17）：只能往上、單次最多 +60。
//
// 規則沒有可跑的模擬器（沒有 Java／emulator），所以分兩層驗：
// 1. 規則**文字**：函式在、數字在、而且真的掛進 `allow update`；
// 2. App 實際寫出去的每一筆，都過得了這條規則（用 Dart 照規則的條件式重寫一份比對）——
//    否則規則一部署，所有人完成限時任務都會被拒。

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

/// 照 `timedMonthOk()` 的條件式寫的對照版（`timedByMonth.{月份}`，月份取自 `timedPeriod`）。
bool _ruleAllows({
  required Map<String, int> before,
  required Map<String, int> after,
  required String period,
}) {
  final keys = {...before.keys, ...after.keys};
  final changed = {
    for (final k in keys)
      if (before[k] != after[k]) k,
  };
  if (changed.isEmpty) return true;
  return changed.length == 1 &&
      changed.contains(period) &&
      RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(period) &&
      after[period] != null &&
      after[period]! >= (before[period] ?? 0) &&
      after[period]! - (before[period] ?? 0) <= 60;
}

void main() {
  group('規則文字', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('match /teams/{teamId}');
    final block = rules.substring(
      i,
      rules.indexOf('match /requests/{targetUid}', i),
    );

    test('有 timedScoreOk()，單次上限 60、只能往上', () {
      expect(block, contains('function timedScoreOk()'));
      // 數字後面不能還有數字："<= 600" 也包含 "<= 60"。
      expect(block, contains(RegExp(r'after - before <= 60(?!\d)')));
      expect(block, contains('after > before'));
    });

    test('換月重設也不能超過 60', () {
      expect(
        block,
        contains(RegExp(r'!samePeriod && after >= 0 && after <= 60(?!\d)')),
      );
    });

    test('真的掛進 allow update（只寫函式不掛等於沒有）', () {
      final upd = block.substring(block.indexOf('allow update'));
      expect(upd.substring(0, upd.indexOf('&& (')), contains('timedScoreOk()'));
    });

    test('有 timedMonthOk()：按月份分開存，單次上限 60、只能往上，並掛進 allow update', () {
      expect(block, contains('function timedMonthOk()'));
      expect(block, contains("'timedByMonth'"));
      expect(block, contains(RegExp(r'after\[p\] - before\.get\(p, 0\) <= 60(?!\d)')));
      final upd = block.substring(block.indexOf('allow update'));
      expect(upd.substring(0, upd.indexOf('&& (')), contains('timedMonthOk()'));
    });

    test('沒有放寬原本的兩道（貢獻分數、完成名單）', () {
      final upd = block.substring(block.indexOf('allow update'));
      expect(
        upd.substring(0, upd.indexOf('&& (')),
        allOf(contains('contribOk()'), contains('timedOk()')),
      );
    });
  });

  group('App 實際寫出去的每一筆都過得了規則', () {
    late FakeFirebaseFirestore db;
    FirestoreTeams as(String uid) => FirestoreTeams(uid: uid, firestore: db);
    setUp(() => db = FakeFirebaseFirestore());

    Future<void> makeTeam(int n) => as('u0').create(
      CloudTeam(
        id: 't1',
        name: '測試隊',
        members: {
          for (var k = 0; k < n; k++)
            'u$k': CloudMember(
              name: 'U$k',
              rank: 1,
              role: k == 0 ? TeamRole.leader : TeamRole.member,
              joinedAt: DateTime(2026),
            ),
        },
      ),
    );

    Future<(Map<String, int>, String)> read() async {
      final d = (await db.collection('teams').doc('t1').get()).data()!;
      return (
        {
          for (final e in ((d['timedByMonth'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).round(),
        },
        (d['timedPeriod'] as String?) ?? '',
      );
    }

    Future<void> credit(String uid, String day) async {
      final (before, _) = await read();
      await as(uid).creditTimed('t1', uid, day);
      final (after, period) = await read();
      expect(
        _ruleAllows(before: before, after: after, period: period),
        isTrue,
        reason: '$uid 於 $day：$before → $after（期別 $period）會被規則拒絕',
      );
    }

    test('五人隊整天走完（含全員完成的 +60）', () async {
      await makeTeam(5);
      for (var k = 0; k < 5; k++) {
        await credit('u$k', '2026-10-15');
      }
      expect((await read()).$1['2026-10'], 5 * 10 + 50);
    });

    test('隔天、換月、第一次得分都過得了', () async {
      await makeTeam(3);
      await credit('u0', '2026-10-15'); // 第一次：空 → 有期別
      await credit('u1', '2026-10-16'); // 隔天
      await credit('u2', '2026-10-20'); // 同月
      await credit('u0', '2026-11-10'); // 換月：十一月多一個鍵，十月原封不動
      final (byMonth, period) = await read();
      expect(period, '2026-11');
      expect(byMonth['2026-10'], 30, reason: '三人各一次、分散在不同天，所以沒有全員完成的加碼');
      expect(byMonth['2026-11'], 10);
    });

    test('對照版本身：一次加 61、往下改、改成幾萬、動到別的月份都會被擋', () {
      bool ok(Map<String, int> b, Map<String, int> a, String p) =>
          _ruleAllows(before: b, after: a, period: p);
      expect(ok({'2026-10': 100}, {'2026-10': 161}, '2026-10'), isFalse);
      expect(ok({'2026-10': 100}, {'2026-10': 50}, '2026-10'), isFalse);
      expect(ok({'2026-10': 0}, {'2026-10': 99999}, '2026-10'), isFalse);
      expect(ok({'2026-10': 100}, {'2026-10': 160}, '2026-10'), isTrue);
      // 帶的期別是十一月，卻去動十月 → 擋。
      expect(ok({'2026-10': 100}, {'2026-10': 110}, '2026-11'), isFalse);
      // 一次動兩個月份 → 擋。
      expect(
          ok({'2026-10': 1, '2026-11': 1}, {'2026-10': 2, '2026-11': 2}, '2026-11'),
          isFalse);
      // 把別的月份刪掉 → 擋。
      expect(ok({'2026-10': 100, '2026-11': 5}, {'2026-11': 10}, '2026-11'),
          isFalse);
      // 月份格式不對 → 擋。
      expect(ok({}, {'x': 10}, 'x'), isFalse);
    });
  });
}
