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

/// 照 `timedScoreOk()` 的條件式寫的對照版。
bool _ruleAllows({
  required int beforeScore,
  required String beforePeriod,
  required int afterScore,
  required String afterPeriod,
}) {
  final samePeriod = afterPeriod == beforePeriod;
  return afterScore == beforeScore ||
      (samePeriod &&
          afterScore > beforeScore &&
          afterScore - beforeScore <= 60) ||
      (!samePeriod && afterScore >= 0 && afterScore <= 60);
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

    Future<(int, String)> read() async {
      final d = (await db.collection('teams').doc('t1').get()).data()!;
      return (
        (d['timedScore'] as num?)?.round() ?? 0,
        (d['timedPeriod'] as String?) ?? '',
      );
    }

    Future<void> credit(String uid, String day) async {
      final (bs, bp) = await read();
      await as(uid).creditTimed('t1', uid, day);
      final (as_, ap) = await read();
      expect(
        _ruleAllows(
          beforeScore: bs,
          beforePeriod: bp,
          afterScore: as_,
          afterPeriod: ap,
        ),
        isTrue,
        reason: '$uid 於 $day：$bs/$bp → $as_/$ap 會被規則拒絕',
      );
    }

    test('五人隊整天走完（含全員完成的 +60）', () async {
      await makeTeam(5);
      for (var k = 0; k < 5; k++) {
        await credit('u$k', '2026-10-15');
      }
      expect((await read()).$1, 5 * 10 + 50);
    });

    test('隔天、換月、第一次得分都過得了', () async {
      await makeTeam(3);
      await credit('u0', '2026-10-15'); // 第一次：空 → 有期別
      await credit('u1', '2026-10-16'); // 隔天
      await credit('u2', '2026-10-20'); // 同月
      await credit('u0', '2026-11-10'); // 換月：分數重設
      expect((await read()).$2, '2026-11');
    });

    test('對照版本身：一次加 61、往下改、改成幾萬都會被擋', () {
      expect(
        _ruleAllows(
          beforeScore: 100,
          beforePeriod: 'a',
          afterScore: 161,
          afterPeriod: 'a',
        ),
        isFalse,
      );
      expect(
        _ruleAllows(
          beforeScore: 100,
          beforePeriod: 'a',
          afterScore: 50,
          afterPeriod: 'a',
        ),
        isFalse,
      );
      expect(
        _ruleAllows(
          beforeScore: 0,
          beforePeriod: 'a',
          afterScore: 99999,
          afterPeriod: 'a',
        ),
        isFalse,
      );
      expect(
        _ruleAllows(
          beforeScore: 100,
          beforePeriod: 'a',
          afterScore: 99999,
          afterPeriod: 'b',
        ),
        isFalse,
      );
      expect(
        _ruleAllows(
          beforeScore: 100,
          beforePeriod: 'a',
          afterScore: 160,
          afterPeriod: 'a',
        ),
        isTrue,
      );
    });
  });
}
