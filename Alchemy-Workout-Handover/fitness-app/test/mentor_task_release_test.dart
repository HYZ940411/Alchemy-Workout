// 師徒任務：學徒標記完成之後，要教官「發放獎勵」才可以領；教官可以取消任務
// （使用者 2026-10-19）。
//
// 在此之前學徒自己按「標記完成」就變成可領取，沒有任何人確認他真的做了 ——
// 每週 3 次、最多白拿 60 經驗 + 45 金幣。
//
// 新流程：已指派 → 學徒標記完成 → 待發放（submitted）→ 教官發放獎勵 → 可領取（done）
//        → 學徒領取 → 已領取。教官在「已指派」與「待發放」時可以取消 → 已作廢。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/data/mentor_data_firestore.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/mentor_interaction_screen.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

/// 學徒那一側：已確認免責聲明、有一則指派給我的任務。
({AppState s, MentorTask t}) _apprentice({
  MentorTaskState state = MentorTaskState.assigned,
}) {
  final s = AppState(demo: false)
    ..myUid = 'u-a'
    ..myInstructor = Instructor(
      name: '老王',
      uid: 'u-m',
      rank: 40,
      reputation: 10,
      apprentices: 1,
      apprenticeCap: 5,
      ability: const {},
      specialties: const ['增肌'],
      avgRating: 4.5,
      ratingCount: 3,
    )
    ..markMentorUnlocked();
  s.confirmMentorDisclaimer();
  final t = MentorTask(id: 'mt-1', title: '練腿', detail: '', state: state);
  s.mentorTasks.add(t);
  return (s: s, t: t);
}

/// 教官那一側：有一位學徒、一則指派給他的任務。
({AppState s, MentorTask t}) _mentor({
  MentorTaskState state = MentorTaskState.assigned,
}) {
  final s = AppState(demo: false)
    ..myUid = 'u-m'
    ..isInstructor = true
    ..instructorDutyVersion = kInstructorDutyVersion;
  s.apprentices.add(Apprentice(
    name: '小明',
    uid: 'u-a',
    rank: 10,
    ability: {for (final d in Dim.values) d: 30},
    recentWorkouts: const [],
  ));
  final t = MentorTask(
      id: 'mt-1', title: '練腿', detail: '', apprenticeUid: 'u-a', state: state);
  s.mentorTasks.add(t);
  return (s: s, t: t);
}

void main() {
  group('學徒標記完成：先不發獎勵', () {
    test('標記完成 → 待發放，還不能領', () {
      final p = _apprentice();
      expect(p.s.completeMentorTask(p.t), isTrue);
      expect(p.t.state, MentorTaskState.submitted);
      expect(p.s.claimMentorTask(p.t), isNull, reason: '教官還沒發放');
      expect(p.t.state, MentorTaskState.submitted, reason: '領不了就不該動狀態');
    });

    test('沒領到就沒有入帳 —— 經驗與金幣都不動', () {
      final p = _apprentice();
      final exp = p.s.totalExp, coins = p.s.coins;
      p.s.completeMentorTask(p.t);
      p.s.claimMentorTask(p.t);
      expect(p.s.totalExp, exp);
      expect(p.s.coins, coins);
    });

    test('待發放的任務不能再標一次完成', () {
      final p = _apprentice(state: MentorTaskState.submitted);
      expect(p.s.completeMentorTask(p.t), isFalse);
    });

    test('待發放的任務不能評分', () {
      final p = _apprentice(state: MentorTaskState.submitted);
      expect(p.s.rateMentorTask(p.t, 5), RateResult.rejected);
      expect(p.t.rating, isNull);
    });

    test('教官發放之後可以評分', () {
      final p = _apprentice(state: MentorTaskState.done);
      expect(p.s.rateMentorTask(p.t, 5), isNot(RateResult.rejected));
    });

    test('已作廢的任務不能評分', () {
      final p = _apprentice(state: MentorTaskState.voided);
      expect(p.s.rateMentorTask(p.t, 5), RateResult.rejected);
    });

    test('教官發放之後學徒領得到，入帳照舊', () {
      final p = _apprentice(state: MentorTaskState.done);
      final coins = p.s.coins;
      final r = p.s.claimMentorTask(p.t)!;
      expect(r.coins, kMentorTaskCoin);
      expect(p.s.coins, coins + kMentorTaskCoin);
      expect(p.t.state, MentorTaskState.claimed);
    });
  });

  group('教官發放獎勵', () {
    test('待發放 → 可領取', () {
      final m = _mentor(state: MentorTaskState.submitted);
      expect(m.s.releaseMentorTaskReward(m.t), isTrue);
      expect(m.t.state, MentorTaskState.done);
    });

    test('學徒還沒標記完成（已指派）不能發放', () {
      final m = _mentor();
      expect(m.s.releaseMentorTaskReward(m.t), isFalse);
      expect(m.t.state, MentorTaskState.assigned);
    });

    test('已發放的不能再發一次', () {
      final m = _mentor(state: MentorTaskState.done);
      expect(m.s.releaseMentorTaskReward(m.t), isFalse);
    });

    test('已作廢的不能發放', () {
      final m = _mentor(state: MentorTaskState.voided);
      expect(m.s.releaseMentorTaskReward(m.t), isFalse);
      expect(m.t.state, MentorTaskState.voided);
    });

    test('不是教官 → 不能發放', () {
      final m = _mentor(state: MentorTaskState.submitted)..s.isInstructor = false;
      expect(m.s.releaseMentorTaskReward(m.t), isFalse);
      expect(m.t.state, MentorTaskState.submitted);
    });

    test('指派給我自己的任務不能自己發放（教官也是別人的學徒時）', () {
      final m = _mentor();
      final mine = MentorTask(
          id: 'mt-self',
          title: '我的任務',
          detail: '',
          state: MentorTaskState.submitted); // apprenticeUid 空 ＝ 指派給我的
      m.s.mentorTasks.add(mine);
      expect(m.s.releaseMentorTaskReward(mine), isFalse);
      expect(mine.state, MentorTaskState.submitted);
      expect(m.s.taskReviewBlockedReason(mine), contains('不能自己發放'));
    });

    test('沒確認指導責任聲明 → 不能發放，而且說得出原因', () {
      final m = _mentor(state: MentorTaskState.submitted)
        ..s.instructorDutyVersion = null;
      expect(m.s.releaseMentorTaskReward(m.t), isFalse);
      expect(m.s.taskReviewBlockedReason(m.t), contains('指導責任聲明'));
    });

    test('社群停權中 → 不能發放也不能取消', () {
      final m = _mentor(state: MentorTaskState.submitted)..s.punishment = null;
      expect(m.s.taskReviewBlockedReason(m.t), isNull, reason: '前提：平時可以');
      // 反覆判定檢舉成立，罰到社群停權。
      for (var i = 0; i < 3; i++) {
        m.s.fileReport(
          target: ReportTarget.post,
          targetKey: reportKey(ReportTarget.post, 'v$i'),
          content: '違規內容 $i',
          accused: m.s.displayName,
          reason: '騷擾辱罵',
        );
        final c = m.s.reports.first;
        m.s.reviewReport(c);
        m.s.upholdReport(c);
      }
      expect(m.s.communityBlocked, isTrue, reason: '前提：停權了');
      // 處罰會連帶撤銷教官資格，這裡把它還原，單獨驗「停權」這道守衛。
      m.s.isInstructor = true;
      expect(m.s.releaseMentorTaskReward(m.t), isFalse);
      expect(m.s.cancelMentorTask(m.t), isFalse);
      expect(m.s.taskReviewBlockedReason(m.t), contains('停權'));
    });
  });

  group('教官取消任務', () {
    test('已指派 → 已作廢', () {
      final m = _mentor();
      expect(m.s.cancelMentorTask(m.t), isTrue);
      expect(m.t.state, MentorTaskState.voided);
    });

    test('待發放 → 已作廢，沒有獎勵', () {
      final m = _mentor(state: MentorTaskState.submitted);
      expect(m.s.cancelMentorTask(m.t), isTrue);
      expect(m.t.state, MentorTaskState.voided);
    });

    test('已發放的不能取消 —— 獎勵已經放行', () {
      final m = _mentor(state: MentorTaskState.done);
      expect(m.s.cancelMentorTask(m.t), isFalse);
      expect(m.t.state, MentorTaskState.done);
    });

    test('已領取的不能取消', () {
      final m = _mentor(state: MentorTaskState.claimed);
      expect(m.s.cancelMentorTask(m.t), isFalse);
    });

    test('取消之後學徒標不了完成、領不了獎', () {
      final p = _apprentice(state: MentorTaskState.voided);
      expect(p.s.completeMentorTask(p.t), isFalse);
      expect(p.s.claimMentorTask(p.t), isNull);
    });

    test('不是教官 → 不能取消', () {
      final m = _mentor()..s.isInstructor = false;
      expect(m.s.cancelMentorTask(m.t), isFalse);
      expect(m.t.state, MentorTaskState.assigned);
    });

    test('指派給我自己的任務不能自己取消', () {
      final m = _mentor();
      final mine = MentorTask(id: 'mt-self', title: '我的', detail: '');
      m.s.mentorTasks.add(mine);
      expect(m.s.cancelMentorTask(mine), isFalse);
    });

    test('標完成之後被取消，不算進「本週完成」', () {
      final m = _mentor(state: MentorTaskState.submitted);
      m.t.doneAt = m.s.now;
      expect(m.s.weeklyCompleted, 1, reason: '前提：標完成算一次');
      m.s.cancelMentorTask(m.t);
      expect(m.s.weeklyCompleted, 0);
    });
  });

  group('關係解除：待發放的也一併作廢，已發放的留著', () {
    test('學徒側解除', () {
      final p = _apprentice();
      final sub = MentorTask(
          id: 'mt-2', title: 'b', detail: '', state: MentorTaskState.submitted);
      final done = MentorTask(
          id: 'mt-3', title: 'c', detail: '', state: MentorTaskState.done);
      p.s.mentorTasks.addAll([sub, done]);
      p.s.releaseMentor(MentorReleaseReason.byApprentice);
      expect(p.t.state, MentorTaskState.voided);
      expect(sub.state, MentorTaskState.voided);
      expect(done.state, MentorTaskState.done, reason: '已放行的獎勵不因解除而收回');
    });

    test('教官側解除', () {
      final m = _mentor(state: MentorTaskState.submitted);
      m.s.releaseApprentice('u-a', MentorReleaseReason.byInstructor);
      expect(m.t.state, MentorTaskState.voided);
    });
  });

  group('雲端', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());
    FirestoreMentor as(String uid) => FirestoreMentor(uid: uid, firestore: db);

    Future<void> put(String id, MentorTaskState st) => as('m').putTask(
        'm_a', CloudMentorTask(id: id, title: id, detail: '', state: st));

    test('待發放存得進去、讀得回來', () async {
      await as('m').bond(CloudBond(
        id: 'm_a',
        mentorUid: 'm',
        apprenticeUid: 'a',
        mentorName: '教官',
        apprenticeName: '學徒',
        bondedAt: DateTime(2026, 9, 1),
      ));
      await put('t1', MentorTaskState.submitted);
      final back = await as('m').tasks('m_a');
      expect(back.single.state, MentorTaskState.submitted);
    });

    test('解除：已指派與待發放都作廢，已發放與已領取不動', () async {
      await as('m').bond(CloudBond(
        id: 'm_a',
        mentorUid: 'm',
        apprenticeUid: 'a',
        mentorName: '教官',
        apprenticeName: '學徒',
        bondedAt: DateTime(2026, 9, 1),
      ));
      await put('assigned', MentorTaskState.assigned);
      await put('submitted', MentorTaskState.submitted);
      await put('done', MentorTaskState.done);
      await put('claimed', MentorTaskState.claimed);

      await as('m').release(
          'm_a', MentorReleaseReason.byInstructor, DateTime(2026, 9, 10));

      final after = {
        for (final t in await as('m').tasks('m_a')) t.id: t.state
      };
      expect(after['assigned'], MentorTaskState.voided);
      expect(after['submitted'], MentorTaskState.voided);
      expect(after['done'], MentorTaskState.done);
      expect(after['claimed'], MentorTaskState.claimed);
    });
  });

  group('畫面', () {
    Future<void> openApprentice(WidgetTester t, AppState s) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: MentorScreen())),
      ));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('練腿'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
    }

    testWidgets('學徒：已指派 → 「標記完成」', (t) async {
      final p = _apprentice();
      await openApprentice(t, p.s);
      expect(find.text('標記完成'), findsOneWidget);
    });

    testWidgets('學徒：待發放 → 「等教官發放」，沒有標記完成也沒有領取', (t) async {
      final p = _apprentice(state: MentorTaskState.submitted);
      await openApprentice(t, p.s);
      expect(find.text('等教官發放'), findsOneWidget);
      expect(find.text('標記完成'), findsNothing);
      expect(find.text('領取獎勵'), findsNothing);
    });

    testWidgets('學徒：待發放時沒有評分星星', (t) async {
      final p = _apprentice(state: MentorTaskState.submitted);
      await openApprentice(t, p.s);
      expect(find.textContaining('評這次任務'), findsNothing);
    });

    testWidgets('學徒：教官發放後 → 「領取獎勵」，按下去入帳', (t) async {
      final p = _apprentice(state: MentorTaskState.done);
      await openApprentice(t, p.s);
      final coins = p.s.coins;
      await t.tap(find.text('領取獎勵'));
      await t.pumpAndSettle();
      expect(p.s.coins, coins + kMentorTaskCoin);
    });

    Future<void> openMentor(WidgetTester t, AppState s) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: MentorInteractionScreen()),
      ));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('練腿'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
    }

    testWidgets('教官：待發放 → 有「發放獎勵」與「取消任務」，按發放就放行', (t) async {
      final m = _mentor(state: MentorTaskState.submitted);
      await openMentor(t, m.s);
      expect(find.text('發放獎勵'), findsOneWidget);
      expect(find.text('取消任務'), findsOneWidget);
      await t.tap(find.text('發放獎勵'));
      await t.pumpAndSettle();
      expect(m.t.state, MentorTaskState.done);
    });

    testWidgets('教官：已指派 → 只有「取消任務」，不能發放', (t) async {
      final m = _mentor();
      await openMentor(t, m.s);
      expect(find.text('取消任務'), findsOneWidget);
      expect(find.text('發放獎勵'), findsNothing);
    });

    testWidgets('教官：取消要先確認，確認後任務作廢並從進行中消失', (t) async {
      final m = _mentor();
      await openMentor(t, m.s);
      await t.tap(find.text('取消任務'));
      await t.pumpAndSettle();
      expect(m.t.state, MentorTaskState.assigned, reason: '還沒按確認');
      await t.tap(find.widgetWithText(AppButton, '取消任務').last);
      await t.pumpAndSettle();
      expect(m.t.state, MentorTaskState.voided);
    });

    testWidgets('教官：已發放 → 沒有任何按鈕（獎勵已放行，收不回來）', (t) async {
      final m = _mentor(state: MentorTaskState.done);
      await openMentor(t, m.s);
      expect(find.text('取消任務'), findsNothing);
      expect(find.text('發放獎勵'), findsNothing);
      expect(find.text('已發放，等學徒領取'), findsOneWidget);
    });
  });
}
