// 交易裡的守衛：判斷留在交易裡，例外丟在交易外面（`PROGRESS.md` 3M）。
//
// 3F／3G：守衛在交易裡靜靜 `return`，呼叫端記成「成功」而雲端一個字沒變；
// 守衛改成在交易裡 `throw` 之後，Web 上例外穿過 JS 邊界、訊息全失，
// 連續六輪讀不出原因。兩個都不能再發生，而競爭條件是真的，所以交易不拿掉。

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show TransactionHandler;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/guarded_transaction.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/data/violation_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';

/// 交易一定失敗的資料庫：可以選擇在跑 body 之前丟，或 body 做完（提交）時丟。
class _ThrowingDb extends FakeFirebaseFirestore {
  final bool throwBeforeBody;
  _ThrowingDb({required this.throwBeforeBody});

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (throwBeforeBody) throw Object();
    await super.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
    throw Object();
  }
}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  FirestoreTeams as(String uid) => FirestoreTeams(uid: uid, firestore: db);

  CloudMember member(String name, {TeamRole role = TeamRole.member}) =>
      CloudMember(
        name: name,
        rank: 20,
        role: role,
        joinedAt: DateTime(2026, 9, 13),
      );

  Future<void> createTeam({Map<String, CloudMember>? members}) =>
      as('a').create(
        CloudTeam(
          id: 't1',
          name: '鐵人小隊',
          members: members ?? {'a': member('一', role: TeamRole.leader)},
        ),
      );

  Matcher refusal(String contains_) => throwsA(
    isA<StateError>().having((e) => e.message, 'message', contains(contains_)),
  );

  group('guardedTransaction', () {
    test('body 回原因 → 交易外面丟 StateError，訊息帶名字與原因', () async {
      await expectLater(
        guardedTransaction(db, '做某事', (tx) async => '條件不成立'),
        refusal('做某事：條件不成立'),
      );
    });

    test('body 回 null → 正常完成', () async {
      await guardedTransaction(db, '做某事', (tx) async {
        tx.set(db.collection('x').doc('y'), {'v': 1});
        return null;
      });
      expect((await db.collection('x').doc('y').get()).data(), {'v': 1});
    });
  });

  group('交易失敗時要說出是哪一段壞的（2026-10-17）', () {
    // 所有交易都失敗，錯誤只有一個沒有內容的物件，連是哪一段都看不出來。
    test('交易根本沒開始就丟 → 階段寫「還沒進到 body」，帶類型', () async {
      final bad = _ThrowingDb(throwBeforeBody: true);
      await expectLater(
        guardedTransaction(bad, '做某事', (tx) async => null),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('做某事：交易失敗'),
              contains('還沒進到 body'),
              contains('錯誤類型'),
            ),
          ),
        ),
      );
    });

    test('body 做完、提交時丟 → 階段寫「等伺服器提交」', () async {
      final bad = _ThrowingDb(throwBeforeBody: false);
      await expectLater(
        guardedTransaction(bad, '做某事', (tx) async => null),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('等伺服器提交'),
          ),
        ),
      );
    });

    test('body 裡丟 → 階段寫「正在跑 body」', () async {
      await expectLater(
        guardedTransaction(db, '做某事', (tx) async => throw 'body 壞了'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('正在跑 body'),
          ),
        ),
      );
    });

    test('正常的拒絕（回原因）不受影響，仍是原本那句', () async {
      await expectLater(
        guardedTransaction(db, '做某事', (tx) async => '條件不成立'),
        refusal('做某事：條件不成立'),
      );
    });
  });

  group('加入團隊 putMember', () {
    test('隊伍不存在 → 說出口，不是「成功」', () async {
      await expectLater(
        as('a').putMember('nope', 'b', member('二')),
        refusal('找不到這支隊伍'),
      );
    });

    test('隊伍已解散 → 說出口', () async {
      await createTeam();
      await as('a').disband('t1');
      await expectLater(
        as('a').putMember('t1', 'b', member('二')),
        refusal('已解散'),
      );
    });

    test('人滿 → 說出口，名冊不動', () async {
      await createTeam(
        members: {
          'a': member('一', role: TeamRole.leader),
          'b': member('二'),
          'c': member('三'),
          'd': member('四'),
          'e': member('五'),
        },
      );
      await expectLater(
        as('a').putMember('t1', 'f', member('六')),
        refusal('隊伍已滿'),
      );
      expect((await as('a').myTeam())!.members, hasLength(5));
    });

    test('有空位 → 照常加入', () async {
      await createTeam();
      await as('a').putMember('t1', 'b', member('二'));
      expect((await as('a').myTeam())!.members.keys, containsAll(['a', 'b']));
    });
  });

  group('離開團隊 removeMember', () {
    test('隊伍不存在 → 說出口', () async {
      await expectLater(as('a').removeMember('nope', 'b'), refusal('找不到這支隊伍'));
    });

    test('本來就不在名冊上 → 冪等，不算失敗也不動名冊', () async {
      await createTeam();
      await as('a').removeMember('t1', 'z');
      expect((await as('a').myTeam())!.members.keys, ['a']);
    });

    test('最後一人離開 → 解散', () async {
      await createTeam();
      await as('a').removeMember('t1', 'a');
      expect(await as('a').myTeam(), isNull);
    });
  });

  group('限時任務計分 creditTimed', () {
    test('隊伍不存在 → 說出口（分數不能無聲消失）', () async {
      await expectLater(
        as('a').creditTimed('nope', 'a', '2026-10-15'),
        refusal('找不到這支隊伍'),
      );
    });

    test('同一天疊上去、新的一天換掉', () async {
      await createTeam();
      await as('a').creditTimed('t1', 'a', '2026-10-15');
      await as('a').creditTimed('t1', 'b', '2026-10-15');
      var t = await db.collection('teams').doc('t1').get();
      expect(t.data()!['timedCredited'], containsAll(['a', 'b']));

      await as('a').creditTimed('t1', 'c', '2026-10-16');
      t = await db.collection('teams').doc('t1').get();
      expect(t.data()!['timedCredited'], ['c']);
      expect(t.data()!['timedDay'], '2026-10-16');
    });
  });

  group('累計違規（同一個 helper）', () {
    test('記一次、再記一次、撤銷一次，值對得上；撤銷不會低於 0', () async {
      final v = FirestoreViolations(firestore: db);
      expect(await v.increment('u1', name: '甲'), 1);
      expect(await v.increment('u1', name: '甲'), 2);
      expect(await v.decrement('u1'), 1);
      expect(await v.decrement('u1'), 0);
      expect(await v.decrement('u1'), 0);
      expect(await v.countOf('u1'), 0);
    });
  });

  test('lib 裡只有 guarded_transaction.dart 可以直接呼叫 runTransaction', () {
    final offenders = <String>[];
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('guarded_transaction.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.contains('.runTransaction') && !l.trimLeft().startsWith('//')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '直接用 runTransaction 的話，守衛要嘛靜靜 return、'
          '要嘛在交易裡 throw（Web 上訊息全失）。請改用 guardedTransaction',
    );
  });
}
