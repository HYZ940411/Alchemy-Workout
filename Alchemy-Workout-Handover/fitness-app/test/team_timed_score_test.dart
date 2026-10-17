// 團隊限時任務：分數要真的加，而且重新整理後不能再做一次（使用者 2026-10-16 回報）。
//
// 兩個問題：
//
// 1. 成員完成限時任務時，排行榜上的「團隊限時分數」不會加。`Team.timedScore` 是個
//    從來沒人寫過的欄位 —— 完成只動了今日完成名單，月累計分數永遠是 0。
// 2. 重新整理後又可以再做一次、再領一次獎勵：「我今天完成了」與「獎勵領了沒」
//    只活在記憶體裡，存檔與雲端讀回都沒有把它們帶回來 —— 刷點數。

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/data/team_data_firestore.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/leaderboard.dart';
import 'package:fitness_app/screens/social/team_detail_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 不在重新分隊期（每月前兩天兩個團隊分數皆不累加）的展示時鐘。
AppState _state() {
  resetAppClock();
  final s = AppState()..myUid = 'u-me';
  var guard = 0;
  while (inRegroupWindow(s.now) && guard++ < 40) {
    s.advanceDemoClock(const Duration(days: 1));
  }
  // 示範資料裡已經有幾位隊友「完成」了 —— 清乾淨，從零數起才數得清楚加了多少。
  s.myTeam!.timedCredited.clear();
  s.timedTask.completedBy.clear();
  // 名冊上的我要帶著 uid。
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

String _day(AppState s) {
  final d = businessDate(s.now);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _viaJson(AppState s) =>
    jsonDecode(jsonEncode(s.toSnapshot())) as Map<String, dynamic>;

/// 雲端寫入可以指定失敗的隊伍來源（只有限時任務計分會被呼叫到）。
class _FailingTeams implements TeamSource {
  bool fail = true;
  int credited = 0;

  @override
  Future<void> creditTimed(String teamId, String uid, String day) async {
    if (fail) throw StateError('權限不足');
    credited++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(resetAppClock);
  tearDown(resetAppClock);

  group('團隊限時分數：本機', () {
    test('自己完成 → 團隊限時分數加 10', () {
      final s = _state();
      final before = s.myTeam!.timedScore;
      s.completeTimedTask();
      expect(
        s.myTeam!.timedScore,
        before + kTimedTaskPerMember,
        reason: '在此之前這個欄位永遠是原樣，排行榜的限時分數不會動',
      );
    });

    test('隊友完成也加；全員完成的那一刻再加 50', () {
      final s = _state();
      final t = s.myTeam!;
      final before = t.timedScore;
      s.completeTimedTask();
      final others = t.members
          .where(
            (m) => !AppState.sameUser(m.name, m.uid, s.displayName, 'u-me'),
          )
          .toList();
      for (final m in others.take(others.length - 1)) {
        expect(s.teammateCompletesTimedTask(m.name, uid: m.uid), isTrue);
      }
      final beforeLast = t.timedScore;
      expect(beforeLast, before + kTimedTaskPerMember * (t.members.length - 1));
      s.teammateCompletesTimedTask(others.last.name, uid: others.last.uid);
      expect(
        t.timedScore,
        beforeLast + kTimedTaskPerMember + kTimedTaskAllBonus,
        reason: '最後一位完成 → 全員完成，加成',
      );
    });

    test('同一個人按兩次只加一次', () {
      final s = _state();
      s.completeTimedTask();
      final after = s.myTeam!.timedScore;
      s.completeTimedTask();
      expect(s.myTeam!.timedScore, after);
    });

    test('重新分隊期（每月前兩天）不累加', () {
      resetAppClock();
      final s = AppState()..myUid = 'u-me';
      var guard = 0;
      while (!inRegroupWindow(s.now) && guard++ < 70) {
        s.advanceDemoClock(const Duration(days: 1));
      }
      expect(inRegroupWindow(s.now), isTrue, reason: '前提');
      final t = s.myTeam!;
      final i = t.members.indexWhere((m) => m.name == s.displayName);
      t.members[i] = TeamMember(
        t.members[i].name,
        t.members[i].rank,
        t.members[i].role,
        uid: 'u-me',
      );
      final before = t.timedScore;
      s.completeTimedTask();
      expect(t.timedScore, before);
    });

    test('排行榜上看得到：我的隊的限時分數就是 timedScore', () {
      final s = _state();
      s.completeTimedTask();
      expect(s.myTeamOnBoard!.timedScore, s.myTeam!.timedScore);
    });

    test('月結：團隊限時分數歸零', () {
      final s = _state();
      s.completeTimedTask();
      expect(s.myTeam!.timedScore, greaterThan(0));
      s.settleBoard(Board.teamTimed);
      expect(s.myTeam!.timedScore, 0);
    });
  });

  group('團隊限時分數：雲端交易', () {
    late FakeFirebaseFirestore db;
    FirestoreTeams as(String uid) => FirestoreTeams(uid: uid, firestore: db);
    setUp(() => db = FakeFirebaseFirestore());

    Future<void> makeTeam() => as('a').create(
      CloudTeam(
        id: 't1',
        name: '測試隊',
        members: {
          for (final u in ['a', 'b', 'c'])
            u: CloudMember(
              name: u.toUpperCase(),
              rank: 1,
              role: u == 'a' ? TeamRole.leader : TeamRole.member,
              joinedAt: DateTime(2026),
            ),
        },
      ),
    );

    Future<int> score() async => (await as('a').myTeam())!.timedScore;

    test('每位成員加 10，全員完成再加 50', () async {
      await makeTeam();
      await as('a').creditTimed('t1', 'a', '2026-10-15');
      expect(await score(), 10);
      await as('b').creditTimed('t1', 'b', '2026-10-15');
      expect(await score(), 20);
      await as('c').creditTimed('t1', 'c', '2026-10-15');
      expect(await score(), 20 + 10 + 50);
    });

    test('同一個人再送一次不再加（重新整理後再按也一樣）', () async {
      await makeTeam();
      await as('a').creditTimed('t1', 'a', '2026-10-15');
      await as('a').creditTimed('t1', 'a', '2026-10-15');
      expect(await score(), 10);
    });

    test('隔天是累加在月分數上，今日名單則整份換掉', () async {
      await makeTeam();
      await as('a').creditTimed('t1', 'a', '2026-10-15');
      await as('b').creditTimed('t1', 'b', '2026-10-16');
      final t = (await as('a').myTeam())!;
      expect(t.timedScore, 20, reason: '兩天各一位，月累計 20');
      expect(t.timedCredited, {'b'});
    });

    test('換月：不是疊在上個月上面，而且上個月的分數還留著（給月初結算讀）', () async {
      await makeTeam();
      await as('a').creditTimed('t1', 'a', '2026-10-20');
      await as('b').creditTimed('t1', 'b', '2026-11-10');
      // 現在是 11 月：看到的「本月」是 11 月那一份。
      final nov = (await FirestoreTeams(
                  uid: 'a', firestore: db, clock: () => DateTime(2026, 11, 12))
              .myTeam())!;
      expect(nov.timedScore, 10);
      expect(nov.timedPeriod, '2026-11');
      expect(nov.timedByMonth, {'2026-10': 10, '2026-11': 10},
          reason: '十月的 10 分沒有被十一月蓋掉 —— 管理員晚幾天按結算也讀得到');
    });

    test('重新分隊期（每月 1、2 日）不加分，但今日名單照記', () async {
      await makeTeam();
      await as('a').creditTimed('t1', 'a', '2026-10-02');
      final t = (await as('a').myTeam())!;
      expect(t.timedScore, 0);
      expect(t.timedCredited, {'a'});
    });
  });

  group('讀回雲端：分數與「我今天完成了」', () {
    CloudTeam cloud(
      AppState s, {
      int score = 80,
      String? period,
      String? day,
      Set<String> credited = const {'u-me'},
    }) => CloudTeam(
      id: 't1',
      name: '雲端隊',
      members: {
        'u-me': CloudMember(
          name: s.displayName,
          rank: 1,
          role: TeamRole.leader,
          joinedAt: DateTime(2026),
        ),
        'u-2': CloudMember(
          name: '隊友',
          rank: 1,
          role: TeamRole.member,
          joinedAt: DateTime(2026),
        ),
      },
      timedScore: score,
      timedPeriod: period ?? _day(s).substring(0, 7),
      timedDay: day ?? _day(s),
      timedCredited: credited,
    );

    test('本月的分數帶進來', () {
      final s = _state();
      s.applyCloudTeam(cloud(s));
      expect(s.myTeam!.timedScore, 80);
    });

    test('雲端記的是上個月的 → 當 0', () {
      final s = _state();
      s.applyCloudTeam(cloud(s, period: '2000-01'));
      expect(s.myTeam!.timedScore, 0);
    });

    test('雲端說我今天完成過 → 本機知道，按鈕不再出現、不能再按', () {
      final s = _state();
      expect(
        s.timedTask.doneBy(s.displayName, uid: 'u-me'),
        isFalse,
        reason: '前提：重新整理後一開始是空的',
      );
      s.applyCloudTeam(cloud(s));
      expect(s.timedTask.doneBy(s.displayName, uid: 'u-me'), isTrue);
      final score = s.myTeam!.timedScore;
      s.completeTimedTask();
      expect(s.myTeam!.timedScore, score, reason: '不能再做一次');
    });

    test('雲端那份是昨天的 → 不算今天完成', () {
      final s = _state();
      s.applyCloudTeam(cloud(s, day: '2000-01-01'));
      expect(s.timedTask.doneBy(s.displayName, uid: 'u-me'), isFalse);
    });
  });

  group('別人的隊伍也看得到分數', () {
    // 使用者截圖：團隊詳情頁（別人的隊）日常分數、限時分數都是 0 ——
    // 雲端有分數，但轉成清單項目時沒帶。
    CloudTeam other({String? period, int timed = 80}) => CloudTeam(
      id: 't9',
      name: '別人的隊',
      members: {
        'x': CloudMember(
          name: '甲',
          rank: 3,
          role: TeamRole.leader,
          joinedAt: DateTime(2026),
        ),
      },
      contributions: const {'x': 30, 'y': 12},
      timedScore: timed,
      timedPeriod: period ?? _day(_state()).substring(0, 7),
    );

    test('日常分數是各成員貢獻的加總，限時分數是本月的', () {
      final s = _state();
      s.applyPublicTeams([other()]);
      final t = s.publicTeams.single;
      expect(t.dailyScore, 42);
      expect(t.timedScore, 80);
    });

    test('限時分數是上個月的 → 當 0（日常不受影響）', () {
      final s = _state();
      s.applyPublicTeams([other(period: '2000-01')]);
      final t = s.publicTeams.single;
      expect(t.timedScore, 0);
      expect(t.dailyScore, 42);
    });

    test('自己的隊不在「別人的隊」裡', () {
      final s = _state();
      s.applyCloudTeam(
        CloudTeam(
          id: 't9',
          name: '我的隊',
          members: {
            'u-me': CloudMember(
              name: s.displayName,
              rank: 1,
              role: TeamRole.leader,
              joinedAt: DateTime(2026),
            ),
          },
        ),
      );
      s.applyPublicTeams([other()]);
      expect(s.publicTeams, isEmpty);
    });

    testWidgets('團隊詳情頁畫出別人的兩個分數', (t) async {
      final s = _state();
      s.applyPublicTeams([other()]);
      t.view.physicalSize = const Size(393 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        AppScope(
          state: s,
          child: MaterialApp(
            home: TeamDetailScreen(team: s.publicTeams.single),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('42'), findsOneWidget, reason: '日常分數');
      expect(find.text('80'), findsOneWidget, reason: '限時分數');
    });
  });

  group('雲端沒記上要能再按一次（2026-10-17 「沒辦法按完成」）', () {
    // 交易壞掉那段時間：本機先記成「已完成」，雲端寫入失敗，按鈕消失、分數沒加，
    // 重新整理後也救不回來。
    CloudTeam cloudWith(
      AppState s, {
      String id = 't1',
      Set<String> credited = const {},
    }) => CloudTeam(
      id: id,
      name: '雲端隊',
      members: {
        'u-me': CloudMember(
          name: s.displayName,
          rank: 1,
          role: TeamRole.leader,
          joinedAt: DateTime(2026),
        ),
        'u-2': CloudMember(
          name: '隊友',
          rank: 1,
          role: TeamRole.member,
          joinedAt: DateTime(2026),
        ),
      },
      timedDay: _day(s),
      timedCredited: credited,
    );

    test('雲端寫入失敗 → 撤銷本機的完成與分數，並說出原因；再按一次可以成功', () async {
      final s = _state();
      final src = _FailingTeams();
      s.teamSource = src;
      final team = s.myTeam!;
      final before = team.timedScore;

      s.completeTimedTask();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        s.timedTask.doneBy(s.displayName, uid: 'u-me'),
        isFalse,
        reason: '雲端沒記上，按鈕要回來',
      );
      expect(team.timedScore, before, reason: '本機先加的分數要一併撤銷');
      expect(s.timedTaskError, contains('請再按一次'));

      src.fail = false;
      s.completeTimedTask();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(s.timedTask.doneBy(s.displayName, uid: 'u-me'), isTrue);
      expect(s.timedTaskError, isNull);
      expect(src.credited, 1);
    });

    test('沒接雲端（示範／測試）不會被撤銷', () async {
      final s = _state();
      s.completeTimedTask();
      await Future<void>.delayed(Duration.zero);
      expect(s.timedTask.doneBy(s.displayName, uid: 'u-me'), isTrue);
      expect(s.timedTaskError, isNull);
    });

    AppState reloadWith(
      Map<String, dynamic> Function(Map<String, dynamic>) f,
      AppState from,
    ) {
      final snap = f(_viaJson(from));
      final back = AppState()..myUid = 'u-me';
      expect(back.applySnapshot(snap), isTrue);
      return back;
    }

    test('卡住的舊狀態（舊存檔沒有 teamId，雲端這支隊沒有我）→ 載入後自癒，按鈕回來', () {
      final s = _state();
      s.completeTimedTask();
      final back = reloadWith((j) {
        (j['timedDone'] as Map).remove('teamId');
        return j;
      }, s);
      expect(
        back.timedTask.doneBy(back.displayName, uid: 'u-me'),
        isTrue,
        reason: '前提：存檔說已完成',
      );
      back.applyCloudTeam(cloudWith(back));
      expect(
        back.timedTask.doneBy(back.displayName, uid: 'u-me'),
        isFalse,
        reason: '雲端沒有我，本機的「已完成」撤銷，才按得了',
      );
    });

    test('這支隊伍的雲端有我 → 維持已完成', () {
      final s = _state();
      s.completeTimedTask();
      final back = reloadWith((j) => j, s);
      back.applyCloudTeam(cloudWith(back, credited: {'u-me'}));
      expect(back.timedTask.doneBy(back.displayName, uid: 'u-me'), isTrue);
    });

    test('完成記在別支隊伍的帳上 → 不自癒（不能換隊再刷一次）', () {
      final s = _state();
      s.completeTimedTask();
      final back = reloadWith((j) {
        (j['timedDone'] as Map)['teamId'] = '別支隊伍';
        return j;
      }, s);
      back.applyCloudTeam(cloudWith(back, id: 't1'));
      expect(back.timedTask.doneBy(back.displayName, uid: 'u-me'), isTrue);
    });

    test('完成當下沒有隊伍 → 不自癒（之後加入隊伍也不能再做一次）', () {
      final s = _state();
      s.completeTimedTask();
      final back = reloadWith((j) {
        (j['timedDone'] as Map)['teamId'] = '';
        return j;
      }, s);
      back.applyCloudTeam(cloudWith(back));
      expect(back.timedTask.doneBy(back.displayName, uid: 'u-me'), isTrue);
    });

    test('存檔記著完成當時的隊伍 id', () {
      final s = _state();
      s.completeTimedTask();
      expect((_viaJson(s)['timedDone'] as Map)['teamId'], s.myTeam!.id);
    });

    test('換帳號：撤銷用的紀錄不留給下一個人', () {
      final s = _state();
      s.completeTimedTask();
      s.endSession();
      expect(s.timedTaskError, isNull);
    });
  });

  group('重新整理（存檔往返）後不能再刷一次', () {
    AppState reload(AppState s) {
      final back = AppState()..myUid = 'u-me';
      expect(back.applySnapshot(_viaJson(s)), isTrue);
      return back;
    }

    test('完成後重新整理：仍是已完成，不能再完成一次', () {
      final s = _state();
      s.completeTimedTask();
      final back = reload(s);
      expect(
        back.timedTask.doneBy(back.displayName, uid: 'u-me'),
        isTrue,
        reason: '在此之前重新整理就忘了，「開始限時任務」又出現',
      );
    });

    test('領過獎勵後重新整理：不能再領一次（刷點數）', () {
      final s = _state();
      s.completeTimedTask();
      expect(s.claimTimedReward(), isNotNull);
      final coins = s.coins;

      final back = reload(s);
      expect(back.timedRewardClaimed, isTrue);
      expect(back.canClaimTimedReward, isFalse);
      expect(back.claimTimedReward(), isNull);
      expect(back.coins, coins);
    });

    test('完成了但還沒領：重新整理後還能領，只能領一次', () {
      final s = _state();
      s.completeTimedTask();
      final back = reload(s);
      expect(back.canClaimTimedReward, isTrue);
      expect(back.claimTimedReward(), isNotNull);
      expect(back.claimTimedReward(), isNull);
    });

    test('存檔是昨天的 → 失效，今天可以重新做', () {
      final s = _state();
      s.completeTimedTask();
      s.claimTimedReward();
      final snap = _viaJson(s);
      (snap['timedDone'] as Map)['day'] = '2000-01-01';
      snap['timedClaimedOn'] = '2000-01-01';
      final back = AppState()..myUid = 'u-me';
      expect(back.applySnapshot(snap), isTrue);
      expect(back.timedTask.doneBy(back.displayName, uid: 'u-me'), isFalse);
      expect(back.timedRewardClaimed, isFalse);
    });

    test('沒完成過就沒有這兩個欄位的內容', () {
      final s = _state();
      final snap = _viaJson(s);
      expect(snap['timedDone'], isNull);
      expect(snap['timedClaimedOn'], isNull);
    });

    test('換帳號：上一個人的完成與領取不留給下一個人', () {
      final s = _state();
      s.completeTimedTask();
      s.claimTimedReward();
      s.endSession();
      expect(s.timedTask.completedBy, isEmpty);
      expect(s.timedRewardClaimed, isFalse);
    });
  });
}
