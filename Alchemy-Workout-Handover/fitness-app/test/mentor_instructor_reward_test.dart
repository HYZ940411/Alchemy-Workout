// 師徒任務：教官也能獲得獎勵（使用者 2026-10-20）。
//
// 學徒領取成功時，教官同步得到經驗值 [kMentorInstructorExp]、金幣 [kMentorInstructorCoin]。
// 學徒的領取發生在學徒的裝置上，所以這裡用同一個假資料庫跑一次教官 ↔ 學徒的完整往返：
//   指派 → 學徒完成 → 教官發放 → 學徒領取 → 教官讀回來。
//
// 規則：
//   · 正常發放、學徒領取：雙方都有
//   · 學徒本週已領滿 3 次：學徒不發，教官也不發
//   · 教官取消、或學徒還沒領：教官沒有

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/mentor_interaction_screen.dart';
import 'package:fitness_app/state/app_state.dart';

CloudBond get _bond => CloudBond(
      id: 'T_A',
      mentorUid: 'T',
      apprenticeUid: 'A',
      mentorName: '教官',
      apprenticeName: '學徒',
      state: MentorBondState.active,
      bondedAt: DateTime(2026, 9, 1),
    );

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

({AppState t, AppState a, FakeFirebaseFirestore db}) _pair() {
  final db = FakeFirebaseFirestore();
  final t = AppState(demo: false)
    ..myUid = 'T'
    ..displayName = '教官'
    ..isInstructor = true
    ..instructorDutyVersion = kInstructorDutyVersion
    ..mentorSource = FirestoreMentor(uid: 'T', firestore: db);
  final a = AppState(demo: false)
    ..myUid = 'A'
    ..displayName = '學徒'
    ..mentorSource = FirestoreMentor(uid: 'A', firestore: db);
  t.applyCloudBonds([_bond]);
  a.applyCloudBonds([_bond]);
  a.confirmMentorDisclaimer();
  return (t: t, a: a, db: db);
}

/// 教官指派 → 學徒完成 → 教官發放。回傳學徒那一側的任務，停在「可領取」。
Future<MentorTask> _toClaimable(
    ({AppState t, AppState a, FakeFirebaseFirestore db}) p, String title) async {
  expect(p.t.assignMentorTask(title, '', apprenticeUid: 'A'), isTrue);
  await settle();
  await p.a.loadMyApprenticeSide();
  final mine = p.a.mentorTasks.firstWhere((x) => x.title == title);
  expect(p.a.completeMentorTask(mine), isTrue);
  await settle();
  await p.t.loadMentorSideOf('A');
  final theirs = p.t.mentorTasks.firstWhere((x) => x.title == title);
  expect(p.t.releaseMentorTaskReward(theirs), isTrue);
  await settle();
  await p.a.loadMyApprenticeSide();
  return p.a.mentorTasks.firstWhere((x) => x.title == title);
}

void main() {
  setUp(() {
    // 吃真實時鐘：挪到正午，免得在換日時點或週界附近跑會跨週。
    resetAppClock();
    final n = appNow();
    appClockOffset += Duration(hours: 12 - n.hour, minutes: -n.minute);
  });
  tearDown(resetAppClock);

  test('常數：教官 10 經驗、8 金幣', () {
    expect(kMentorInstructorExp, 10);
    expect(kMentorInstructorCoin, 8);
  });

  group('正常發放', () {
    test('學徒領取成功 → 雙方都有', () async {
      final p = _pair();
      final task = await _toClaimable(p, '練腿');
      final aExp = p.a.totalExp, aCoins = p.a.coins;
      final tExp = p.t.totalExp, tCoins = p.t.coins;

      final r = p.a.claimMentorTask(task)!;
      expect(r.exp, kMentorTaskExp);
      expect(p.a.totalExp, aExp + kMentorTaskExp);
      expect(p.a.coins, aCoins + kMentorTaskCoin);
      await settle();

      await p.t.loadMentorSideOf('A');
      expect(p.t.totalExp, tExp + kMentorInstructorExp);
      expect(p.t.coins, tCoins + kMentorInstructorCoin);
      expect(p.t.instructorRewardUnseen,
          (exp: kMentorInstructorExp, coins: kMentorInstructorCoin));
    });

    test('重讀、重開 App 都不會重複發', () async {
      final p = _pair();
      final task = await _toClaimable(p, '練腿');
      p.a.claimMentorTask(task);
      await settle();
      await p.t.loadMentorSideOf('A');
      final exp = p.t.totalExp, coins = p.t.coins;

      await p.t.loadMentorSideOf('A');
      expect(p.t.totalExp, exp, reason: '同一則任務讀兩次只發一次');
      expect(p.t.coins, coins);

      // 重開 App：記帳進存檔，讀回來不會再發。
      final fresh = AppState(demo: false)
        ..myUid = 'T'
        ..isInstructor = true
        ..instructorDutyVersion = kInstructorDutyVersion
        ..mentorSource = FirestoreMentor(uid: 'T', firestore: p.db);
      fresh.applyCloudBonds([_bond]);
      expect(fresh.applySnapshot(p.t.toSnapshot()), isTrue);
      final before = fresh.totalExp;
      await fresh.loadMentorSideOf('A');
      expect(fresh.totalExp, before);
    });

    test('「知道了」只清掉提示，不動已入帳的獎勵', () async {
      final p = _pair();
      final task = await _toClaimable(p, '練腿');
      p.a.claimMentorTask(task);
      await settle();
      await p.t.loadMentorSideOf('A');
      final exp = p.t.totalExp;
      p.t.acknowledgeInstructorReward();
      expect(p.t.instructorRewardUnseen, (exp: 0, coins: 0));
      expect(p.t.totalExp, exp);
    });
  });

  group('每週上限：跟著學徒的「本週已發 N／3 次」', () {
    test('前 3 次雙方都發，第 4 次雙方都不發', () async {
      final p = _pair();
      final t0Exp = p.t.totalExp, t0Coins = p.t.coins;
      for (var i = 1; i <= 3; i++) {
        final task = await _toClaimable(p, '任務$i');
        expect(p.a.claimMentorTask(task)!.exp, kMentorTaskExp, reason: '第 $i 次');
        await settle();
        await p.t.loadMentorSideOf('A');
      }
      expect(p.a.mentorRewardsThisWeek, 3);
      expect(p.t.totalExp, t0Exp + 3 * kMentorInstructorExp);
      expect(p.t.coins, t0Coins + 3 * kMentorInstructorCoin);

      final aExp = p.a.totalExp, aCoins = p.a.coins;
      final tExp = p.t.totalExp, tCoins = p.t.coins;
      final fourth = await _toClaimable(p, '任務4');
      final r = p.a.claimMentorTask(fourth)!;
      expect(r, (exp: 0, coins: 0), reason: '學徒超過上限不發');
      await settle();
      await p.t.loadMentorSideOf('A');

      expect(p.a.totalExp, aExp);
      expect(p.a.coins, aCoins);
      expect(p.t.totalExp, tExp, reason: '學徒那次被擋，教官也不發');
      expect(p.t.coins, tCoins);
    });

    test('學徒領取時已滿額 → 任務不標記為已入帳', () async {
      final p = _pair();
      p.a.mentorRewardsThisWeek = kMentorTaskRewardWeeklyCap;
      final task = await _toClaimable(p, '練腿');
      p.a.claimMentorTask(task);
      expect(task.state, MentorTaskState.claimed, reason: '任務照常完成');
      expect(task.rewarded, isFalse);
    });
  });

  group('教官不該拿到的情況', () {
    test('教官發放了、學徒還沒領 → 教官沒有', () async {
      final p = _pair();
      final exp = p.t.totalExp, coins = p.t.coins;
      await _toClaimable(p, '練腿');
      await p.t.loadMentorSideOf('A');
      expect(p.t.totalExp, exp);
      expect(p.t.coins, coins);
      expect(p.t.instructorRewardUnseen, (exp: 0, coins: 0));
    });

    test('教官取消任務 → 教官沒有，學徒也領不到', () async {
      final p = _pair();
      final exp = p.t.totalExp, coins = p.t.coins;
      p.t.assignMentorTask('練腿', '', apprenticeUid: 'A');
      await settle();
      await p.a.loadMyApprenticeSide();
      p.a.completeMentorTask(p.a.mentorTasks.single);
      await settle();
      await p.t.loadMentorSideOf('A');
      final theirs = p.t.mentorTasks.single;
      expect(p.t.cancelMentorTask(theirs), isTrue);
      await settle();

      await p.a.loadMyApprenticeSide();
      expect(p.a.claimMentorTask(p.a.mentorTasks.single), isNull);
      await p.t.loadMentorSideOf('A');
      expect(p.t.totalExp, exp);
      expect(p.t.coins, coins);
    });

    test('舊任務（已領取但沒有已入帳標記）不追發', () async {
      final p = _pair();
      final exp = p.t.totalExp, coins = p.t.coins;
      await p.db
          .collection('mentor_bonds')
          .doc('T_A')
          .collection('tasks')
          .doc('old')
          .set({'title': '舊任務', 'detail': '', 'state': 'claimed', 'rewardCoins': 15});
      await p.t.loadMentorSideOf('A');
      expect(p.t.totalExp, exp);
      expect(p.t.coins, coins);
    });
  });

  test('已入帳標記存得進雲端、讀得回來', () async {
    final p = _pair();
    final task = await _toClaimable(p, '練腿');
    p.a.claimMentorTask(task);
    await settle();
    final doc = await p.db
        .collection('mentor_bonds')
        .doc('T_A')
        .collection('tasks')
        .doc(task.id)
        .get();
    expect(doc.data()!['rewarded'], isTrue);
    await p.t.loadMentorSideOf('A');
    expect(p.t.mentorTasks.single.rewarded, isTrue);
  });

  group('畫面', () {
    Future<AppState> openMentor(WidgetTester t, MentorTaskState st,
        {({int exp, int coins}) unseen = (exp: 0, coins: 0)}) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState(demo: false)
        ..myUid = 'T'
        ..isInstructor = true
        ..instructorDutyVersion = kInstructorDutyVersion
        ..instructorRewardUnseen = unseen;
      s.apprentices.add(Apprentice(
        name: '小明',
        uid: 'A',
        rank: 10,
        ability: {for (final d in Dim.values) d: 30},
        recentWorkouts: const [],
      ));
      s.mentorTasks.add(MentorTask(
          id: 'mt-1', title: '練腿', detail: '', apprenticeUid: 'A', state: st));
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: MentorInteractionScreen()),
      ));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('練腿'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('入帳後教官端顯示「你獲得 經驗值 X、金幣 Y」，按「知道了」收起', (t) async {
      await openMentor(t, MentorTaskState.done);
      expect(find.textContaining('你獲得'), findsNothing, reason: '還沒入帳');
      await t.pumpWidget(const SizedBox());
      await openMentor(t, MentorTaskState.done,
          unseen: (exp: kMentorInstructorExp, coins: kMentorInstructorCoin));
      expect(find.text('學徒已領取，你獲得 經驗值 10、金幣 8'), findsOneWidget);
      await t.tap(find.text('知道了'));
      await t.pumpAndSettle();
      expect(find.textContaining('你獲得'), findsNothing);
    });

    testWidgets('按「發放獎勵」→ 提示學徒領取後教官會獲得多少', (t) async {
      await openMentor(t, MentorTaskState.submitted);
      await t.tap(find.text('發放獎勵'));
      await t.pump();
      expect(find.textContaining('學徒領取後你會獲得 經驗值 10、金幣 8'), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}
