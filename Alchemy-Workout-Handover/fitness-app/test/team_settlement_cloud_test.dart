// 團隊月結算的雲端讀寫與管理員按鈕（`[QA-05]` 階段三之一，使用者裁決 D，2026-10-17）。
//
// 規則沒有可跑的模擬器，所以規則分兩層驗：規則**文字**，以及 App 實際寫出去的東西符合規則要的形狀。
// 規則語意要到部署時才會被 Firebase 驗證。

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/settlement_data.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

CloudTeam _cloud(String id, int size, int daily, int timed) => CloudTeam(
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
      peakSize: size,
      contribByMonth: {
        '2026-10': {'$id-u0': daily},
      },
      timedByMonth: {'2026-10': timed},
    );

void main() {
  group('規則文字', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('match /team_settlements/{period}');
    final block = rules.substring(i, rules.indexOf('collection group 查詢吃的不是'));

    test('標記與結果都只有管理員能建立、不可修改、不可刪除', () {
      expect(i, greaterThan(0), reason: '規則裡有這一段');
      expect(block, contains('allow create: if isAdmin() && period.matches'));
      expect(block, contains('allow update, delete: if false;'));
      expect(block, contains('allow create: if isAdmin();'));
      // 兩處（標記、結果）都不能 update／delete。
      expect('allow update, delete: if false;'.allMatches(block).length, 2);
    });

    test('結果只有結算當下的成員與管理員讀得到；文件不存在時不報錯', () {
      expect(block, contains('request.auth.uid in resource.data.memberUids'));
      expect(block, contains('resource == null'));
      expect(block, contains('isAdmin()'));
    });

    test('月份格式被限制（YYYY-MM）', () {
      expect(block, contains(r"period.matches('^[0-9]{4}-[0-9]{2}$')"));
    });
  });

  group('FirestoreTeams：月結算讀寫', () {
    late FakeFirebaseFirestore db;
    FirestoreTeams src() => FirestoreTeams(uid: 'admin', firestore: db);
    setUp(() => db = FakeFirebaseFirestore());

    test('還沒結算：settledAt 是空的，resultFor 是空的', () async {
      expect(await src().settledAt('2026-10'), isNull);
      expect(await src().resultFor('2026-10', 'a'), isNull);
    });

    test('publish 一次寫下標記與每支隊伍的結果，讀得回來', () async {
      final results = computeTeamSettlement(
          [_cloud('a', 3, 100, 50), _cloud('b', 3, 10, 5)], '2026-10');
      await src().publish('2026-10', results, by: 'admin');

      expect(await src().settledAt('2026-10'), isNotNull);
      final marker = (await db.collection('team_settlements').doc('2026-10').get()).data()!;
      expect(marker['teams'], 2);
      expect(marker['settledBy'], 'admin');

      final a = (await src().resultFor('2026-10', 'a'))!;
      expect(a.teamName, '隊a');
      expect(a.memberUids, ['a-u0', 'a-u1', 'a-u2']);
      expect(a.daily.place, 1);
      expect(a.daily.group, '3 人組');
      expect(a.daily.score, 100);
      expect(a.daily.prize.coins, 90);
      expect(a.daily.prize.aiCredits, 1, reason: 'AI 點數也要存得下來');
      expect(a.timed.group, '全部隊伍');
      expect(a.timed.prize.coins, 100);
      expect(a.timed.prize.aiCredits, 2);

      final b = (await src().resultFor('2026-10', 'b'))!;
      expect(b.daily.place, 2);
      expect(b.daily.prize.coins, 10,
          reason: '同組只有 2 隊：前 20%、前 50% 進位後都只有 1 隊，第 2 名是「其餘參與者」');
    });

    test('別的月份、別支隊伍沒有結果', () async {
      await src().publish('2026-10',
          computeTeamSettlement([_cloud('a', 3, 1, 1)], '2026-10'),
          by: 'admin');
      expect(await src().resultFor('2026-09', 'a'), isNull);
      expect(await src().resultFor('2026-10', 'zzz'), isNull);
    });

    test('allTeams 讀回所有隊伍（含按月份的完整紀錄）', () async {
      await src().create(_cloud('a', 3, 0, 0));
      await FirestoreTeams(
              uid: 'a-u0', firestore: db, clock: () => DateTime(2026, 10, 5, 12))
          .addScore('a', 'a-u0', 40);
      final all = await src().allTeams();
      expect(all.single.contribByMonth['2026-10'], {'a-u0': 40});
    });

    test('結果文件的形狀符合規則要的欄位（memberUids 是 uid 清單）', () async {
      await src().publish('2026-10',
          computeTeamSettlement([_cloud('a', 3, 1, 1)], '2026-10'),
          by: 'admin');
      final d = (await db
              .collection('team_settlements')
              .doc('2026-10')
              .collection('results')
              .doc('a')
              .get())
          .data()!;
      expect(d['memberUids'], isA<List>());
      expect((d['memberUids'] as List).first, isA<String>());
    });
  });

  group('AppState.settleTeamBoardsForAll', () {
    late FakeFirebaseFirestore db;
    late FirestoreTeams src;
    setUp(() {
      db = FakeFirebaseFirestore();
      src = FirestoreTeams(uid: 'admin', firestore: db);
    });

    AppState admin() {
      final s = AppState()..myUid = 'admin';
      s.applyAdminClaim(true);
      s.settlementSource = src;
      return s;
    }

    /// 結算的是「上個月」。測試不綁死今天是幾月：分數放在 [period] 那格。
    String lastMonth(AppState s) => previousMonthKey(teamMonthKey(s.now));

    Future<void> seed(String period) async {
      for (final t in [_cloud('a', 3, 100, 50), _cloud('b', 4, 30, 90)]) {
        await db.collection('teams').doc(t.id).set({
          'name': t.name,
          'memberUids': t.members.keys.toList(),
          'members': {
            for (final e in t.members.entries)
              e.key: {
                'name': e.value.name,
                'rank': 1,
                'role': e.value.role.name,
                'joinedAt': Timestamp.fromDate(DateTime(2026)),
              },
          },
          'peakSize': t.peakSize,
          'disbanded': false,
          'contribByMonth': {
            period: {'${t.id}-u0': t.contribByMonth['2026-10']!.values.first},
          },
          'timedByMonth': {period: t.timedByMonth['2026-10']},
        });
      }
    }

    test('不是管理員 → 不做，說一句話', () async {
      final s = AppState()..settlementSource = src;
      final r = await s.settleTeamBoardsForAll();
      expect(r.error, contains('只有管理員可以結算'),
          reason: '要是被「沒有管理員標記」那一句蓋掉，代表第一道把關沒了');
      expect(await src.settledAt('2026-10'), isNull);
    });

    test('沒接雲端 → 說出來，不假裝成功', () async {
      final s = AppState()..applyAdminClaim(true);
      expect((await s.settleTeamBoardsForAll()).error, contains('沒有接雲端'));
    });

    test('沒有符合資格的隊伍：不寫標記（之後還可以再按）', () async {
      final s = admin();
      final r = await s.settleTeamBoardsForAll();
      expect(r.error, contains('沒有符合資格'));
      expect(await src.settledAt(lastMonth(s)), isNull);
    });

    test('結算成功：寫下標記與結果，回傳隊伍數；結算的是「上個月」', () async {
      final s = admin();
      final period = lastMonth(s);
      await seed(period);
      final r = await s.settleTeamBoardsForAll();
      expect(r.error, isNull);
      expect(r.teams, 2);
      expect(await src.settledAt(period), isNotNull);
      final a = (await src.resultFor(period, 'a'))!;
      expect(a.daily.score, 100);
      expect(a.timed.place, 2, reason: '限時 b 是 90、a 是 50，不分組');
    });

    test('分數在「這個月」不算：只結算上個月', () async {
      final s = admin();
      await seed(teamMonthKey(s.now)); // 分數放在本月
      final r = await s.settleTeamBoardsForAll();
      // 隊伍符合資格（曾達 3 人），但上個月沒有分數 → 結果照寫、全是 0 分，不是本月的分數。
      expect(r.error, isNull);
      final a = (await src.resultFor(lastMonth(s), 'a'))!;
      expect(a.daily.score, 0);
      expect(a.timed.score, 0);
    });

    test('同一個月只能結算一次：第二次說出來，不覆蓋', () async {
      final s = admin();
      final period = lastMonth(s);
      await seed(period);
      // 直接把標記塞進去，模擬「已經結算過」。
      await db.collection('team_settlements').doc(period).set({
        'settledAt': Timestamp.now(),
        'teams': 7,
      });
      final r = await s.settleTeamBoardsForAll();
      expect(r.error, contains('已經結算過'));
      expect(
          (await db.collection('team_settlements').doc(period).get()).data()!['teams'],
          7);
    });
  });
}
