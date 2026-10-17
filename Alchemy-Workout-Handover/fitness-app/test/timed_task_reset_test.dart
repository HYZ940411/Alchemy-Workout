// 管理員重置「所有人今天的限時任務」（2026-10-17，Demo 前的緊急需求）。
//
// 完成紀錄分散在每個人自己的存檔（`timedDone`／`timedClaimedOn`）與各隊文件
// （`timedCredited`／`timedDay`）裡，沒有集中的地方可以逐一清，也不該用管理員工具去動每個人的資料。
// 做法是換一個「重置代數」：今天這一輪的識別變成「日期＋代數」，舊的紀錄自己就失效。

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_cache.dart';
import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/data/platform_data_firestore.dart';
import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

AppState _state() {
  resetAppClock();
  final s = AppState()..myUid = 'u-me';
  var guard = 0;
  while (inRegroupWindow(s.now) && guard++ < 40) {
    s.advanceDemoClock(const Duration(days: 1));
  }
  s.myTeam!.timedCredited.clear();
  s.timedTask.completedBy.clear();
  final t = s.myTeam!;
  final i = t.members.indexWhere((m) => m.name == s.displayName);
  t.members[i] = TeamMember(
    t.members[i].name,
    t.members[i].rank,
    t.members[i].role,
    uid: 'u-me',
  );
  return s;
}

Map<String, dynamic> _viaJson(AppState s) =>
    jsonDecode(jsonEncode(s.toSnapshot())) as Map<String, dynamic>;

bool _done(AppState s) => s.timedTask.doneBy(s.displayName, uid: 'u-me');

class _FakeSource implements PlatformDataSource, PlatformRevisioned {
  int resets = 0;
  @override
  Future<int> resetTimedTask() async {
    resets++;
    return 4242;
  }

  @override
  Future<void> ensureRev() async {}
  @override
  Future<void> put(String c, String id, Map<String, dynamic> d) async {}
  @override
  Future<void> remove(String c, String id) async {}
  @override
  Future<PlatformData> load() => const BundledPlatformData().load();
}

void main() {
  setUp(resetAppClock);
  tearDown(resetAppClock);

  group('本機：換代數 → 今天的完成與領取一起歸零', () {
    test('完成、領過獎勵、隊上的完成名單都清掉；按鈕回來', () {
      final s = _state();
      s.completeTimedTask();
      s.claimTimedReward();
      expect(_done(s), isTrue);
      expect(s.timedRewardClaimed, isTrue);

      s.applyTimedEpoch(1700000001);
      expect(_done(s), isFalse);
      expect(s.timedRewardClaimed, isFalse, reason: 'Demo 要能再領一次');
      expect(s.myTeam!.timedCredited, isEmpty);
    });

    test('同一個代數再套一次不動；讀不到（空值）也不動', () {
      final s = _state();
      s.applyTimedEpoch(7);
      s.completeTimedTask();
      s.applyTimedEpoch(7);
      expect(_done(s), isTrue, reason: '同代數不能又清一次，否則每次載入都被清掉');
      s.applyTimedEpoch(null);
      expect(_done(s), isTrue, reason: '雲端讀不到不能當成「代數歸零」');
      expect(s.timedEpoch, 7);
    });

    test('換代數之後再完成一次，照樣加分', () {
      final s = _state();
      s.completeTimedTask();
      final after1 = s.myTeam!.timedScore;
      s.applyTimedEpoch(9);
      s.completeTimedTask();
      expect(_done(s), isTrue);
      expect(s.myTeam!.timedScore, greaterThan(after1 - 1));
    });
  });

  group('存檔：舊代數的完成紀錄不再算數', () {
    AppState reload(AppState from, {int epochBefore = 0}) {
      final back = AppState()..myUid = 'u-me';
      back.timedEpoch = epochBefore;
      expect(back.applySnapshot(_viaJson(from)), isTrue);
      return back;
    }

    test('重置之前存的完成與領取，重置之後載入就是沒做', () {
      final s = _state();
      s.completeTimedTask();
      s.claimTimedReward();
      final back = reload(s, epochBefore: 5); // 載入時已經知道代數是 5
      expect(_done(back), isFalse);
      expect(back.timedRewardClaimed, isFalse);
    });

    test('重置之後存的，同代數載入仍然有效', () {
      final s = _state();
      s.applyTimedEpoch(5);
      s.completeTimedTask();
      s.claimTimedReward();
      final back = reload(s, epochBefore: 5);
      expect(_done(back), isTrue);
      expect(back.timedRewardClaimed, isTrue);
    });

    test('先載入存檔、之後才讀到新代數（兩個非同步誰先到都一樣）', () {
      final s = _state();
      s.completeTimedTask();
      final back = reload(s); // 還不知道代數
      expect(_done(back), isTrue, reason: '前提：先套用存檔時還看得到');
      back.applyTimedEpoch(5);
      expect(_done(back), isFalse);
    });
  });

  group('隊伍文件：舊代數的完成名單不算今天的', () {
    CloudTeam cloud(AppState s, String timedDay) => CloudTeam(
      id: 't1',
      name: '雲端隊',
      members: {
        'u-me': CloudMember(
          name: s.displayName,
          rank: 1,
          role: TeamRole.leader,
          joinedAt: DateTime(2026),
        ),
      },
      timedDay: timedDay,
      timedCredited: const {'u-me'},
    );

    String today(AppState s) {
      final d = businessDate(s.now);
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    test('代數 0：日期對就算（既有行為）', () {
      final s = _state();
      s.applyCloudTeam(cloud(s, today(s)));
      expect(s.myTeam!.timedCredited, {'u-me'});
    });

    test('換了代數：只有日期（沒帶代數）的舊名單當作別天', () {
      final s = _state();
      s.applyTimedEpoch(5);
      s.applyCloudTeam(cloud(s, today(s)));
      expect(s.myTeam!.timedCredited, isEmpty);
      expect(_done(s), isFalse);
    });

    test('換了代數：帶同代數的名單才算', () {
      final s = _state();
      s.applyTimedEpoch(5);
      s.applyCloudTeam(cloud(s, '${today(s)}#5'));
      expect(s.myTeam!.timedCredited, {'u-me'});
      expect(_done(s), isTrue);
    });
  });

  group('雲端：帶代數的日期照樣算分', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    test('creditTimed 的日期帶 #代數：分數照加、月份照算、日期原樣存', () async {
      final teams = FirestoreTeams(uid: 'a', firestore: db);
      await teams.create(
        CloudTeam(
          id: 't1',
          name: '隊',
          members: {
            'a': CloudMember(
              name: 'A',
              rank: 1,
              role: TeamRole.leader,
              joinedAt: DateTime(2026),
            ),
          },
        ),
      );
      await teams.creditTimed('t1', 'a', '2026-10-20#5');
      final t = (await teams.myTeam())!;
      expect(t.timedScore, greaterThan(0));
      expect(t.timedPeriod, '2026-10');
      expect(t.timedDay, '2026-10-20#5');
      expect(t.timedCredited, {'a'});
    });

    test('重新分隊期（每月 1、2 日）帶代數也不加分', () async {
      final teams = FirestoreTeams(uid: 'a', firestore: db);
      await teams.create(
        CloudTeam(
          id: 't1',
          name: '隊',
          members: {
            'a': CloudMember(
              name: 'A',
              rank: 1,
              role: TeamRole.leader,
              joinedAt: DateTime(2026),
            ),
          },
        ),
      );
      await teams.creditTimed('t1', 'a', '2026-10-02#5');
      expect((await teams.myTeam())!.timedScore, 0);
    });
  });

  group('平台資料來源：讀、寫代數', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());
    Future<Map<String, dynamic>?> meta() async =>
        (await db.collection('platform_config').doc('_meta').get()).data();

    test('載入時帶出代數（跟版本同一份文件，不多讀）', () async {
      await db.collection('platform_config').doc('_meta').set({
        'rev': 'r1',
        'timedEpoch': 77,
      });
      final d = await FirestorePlatformData(firestore: db).load();
      expect(d.timedEpoch, 77);
    });

    test('文件裡沒有代數 → 0（沒重置過）', () async {
      await db.collection('platform_config').doc('_meta').set({'rev': 'r1'});
      expect((await FirestorePlatformData(firestore: db).load()).timedEpoch, 0);
    });

    test('命中快取時也讀得到最新的代數（代數不進快取）', () async {
      await db.collection('platform_config').doc('_meta').set({'rev': 'r1'});
      final cache = MemoryPlatformCache();
      final src = FirestorePlatformData(firestore: db, cache: cache);
      await src.load(); // 存快取
      await db.collection('platform_config').doc('_meta').set({
        'rev': 'r1',
        'timedEpoch': 5,
      });
      expect((await src.load()).timedEpoch, 5);
    });

    test('resetTimedTask：寫入新代數、不動版本、回傳新代數', () async {
      await db.collection('platform_config').doc('_meta').set({'rev': 'r1'});
      final e = await FirestorePlatformData(firestore: db).resetTimedTask();
      final m = await meta();
      expect(m!['timedEpoch'], e);
      expect(m['rev'], 'r1', reason: '平台資料沒變，不該讓所有人重讀快取');
      expect(e, greaterThan(1700000000));
    });

    test('之後後台改平台資料換版本、補版本，都不能把代數蓋掉', () async {
      await db.collection('platform_config').doc('_meta').set({
        'rev': 'r1',
        'timedEpoch': 5,
      });
      final src = FirestorePlatformData(firestore: db);
      await src.put('exercises', 'x1', {'name': '新動作'});
      expect((await meta())!['timedEpoch'], 5, reason: '換版本把代數蓋掉，等於悄悄撤銷重置');
      await db.collection('platform_config').doc('_meta').set({
        'timedEpoch': 5,
      });
      await src.ensureRev(); // 沒有 rev → 補
      expect((await meta())!['timedEpoch'], 5);
      expect((await meta())!['rev'], isA<String>());
    });
  });

  group('AppState.resetTimedTaskForAll', () {
    test('不是管理員 → 不做，說一句話', () async {
      final s = _state()..platformSource = _FakeSource();
      expect(await s.resetTimedTaskForAll(), contains('管理員'));
      expect((s.platformSource! as _FakeSource).resets, 0);
    });

    test('管理員 → 呼叫雲端換代數，並且本機立刻套用', () async {
      final src = _FakeSource();
      final s = _state()
        ..applyAdminClaim(true)
        ..platformSource = src;
      s.completeTimedTask();
      expect(await s.resetTimedTaskForAll(), isNull);
      expect(src.resets, 1);
      expect(s.timedEpoch, 4242);
      expect(_done(s), isFalse);
    });

    test('沒接雲端 → 說出來，不假裝成功', () async {
      final s = _state()..applyAdminClaim(true);
      expect(await s.resetTimedTaskForAll(), contains('沒有接雲端'));
    });
  });
}
