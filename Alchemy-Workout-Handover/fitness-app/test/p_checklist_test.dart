// 第二批第 8 項：P77–P92 裡原本沒有結果紀錄的項目（P80–P85、P87–P92），
// 能用測試確定的先確定。每一條對應〈PROGRESS 0U〉表裡的 A（正確反應）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';

final _plan = kAllPlans.firstWhere((p) => p.id == 'p_push');

SettlementResult _train(AppState s, {WorkoutPlan? plan}) {
  s.startWorkout(plan ?? _plan);
  var guard = 0;
  while (s.currentRecord != null && guard++ < 80) {
    s.advanceDemoClock(const Duration(seconds: 45));
    if (!s.completeCurrentSet()) break;
  }
  return s.finishWorkout(EndKind.completed);
}

Post _othersPost(String id) => Post(
    id: id,
    author: '別人',
    authorUid: 'u-別人',
    authorRank: 10,
    text: '嗨 $id',
    at: DateTime(2026, 10, 1));

void main() {
  setUp(() {
    platformConfig.reset();
    resetAppClock();
    final n = appNow();
    appClockOffset += Duration(hours: 12 - n.hour, minutes: -n.minute);
  });
  tearDown(() {
    platformConfig.reset();
    resetAppClock();
  });

  group('P83 同一天練兩場', () {
    test('天數 +1、次數 +2', () {
      final s = AppState(demo: false);
      final d0 = s.totalWorkoutDays;
      final w0 = s.totalWorkouts;
      _train(s);
      _train(s);
      expect(s.totalWorkouts - w0, 2);
      expect(s.totalWorkoutDays - d0, 1);
    });
  });

  group('P82 刪貼文', () {
    test('貼文數跟著減，已解鎖的成就不收回', () async {
      final s = AppState(demo: false)..displayName = '我';
      s.publishPost('第一篇', PostVisibility.public);
      s.publishPost('第二篇', PostVisibility.public);
      expect(s.myPostCount, 2);
      // 讓某枚互動成就達標並解鎖。
      s.interactionTotals['發文'] = 9999;
      s.syncAchievementsAfterLoad();
      final unlocked = s.achievements.where((a) => a.unlocked).toList();
      expect(unlocked, isNotEmpty, reason: '前提：有成就解鎖');

      final target = s.posts.firstWhere((p) => p.text == '第一篇');
      await s.deletePost(target);

      expect(s.myPostCount, 1);
      for (final a in unlocked) {
        expect(a.unlocked, isTrue, reason: '${a.name} 一經解鎖不可撤銷');
      }
    });
  });

  group('P84 連續按讚', () {
    test('經驗值有每日上限，但成就計數照算', () {
      final s = AppState(demo: false)..displayName = '我';
      final cap = platformConfig.i('reward', 'capLike');
      final likeExp = platformConfig.i('reward', 'likeExp');
      final n = cap + 5;
      for (var i = 0; i < n; i++) {
        s.posts.add(_othersPost('p$i'));
      }
      final exp0 = s.totalExp;
      final c0 = s.interactionTotals['按讚'] ?? 0;
      for (var i = 0; i < n; i++) {
        s.toggleLike(s.posts.firstWhere((p) => p.id == 'p$i'));
      }
      expect((s.interactionTotals['按讚'] ?? 0) - c0, n,
          reason: '成就計數不被每日上限擋住');
      expect(s.totalExp - exp0, cap * likeExp, reason: '獎勵有每日上限');
    });
  });

  group('P85 訂閱', () {
    test('月訂：到期日 +30 天，AI 點數補到當月額度', () {
      final s = AppState(demo: false)..aiMonthly = 0;
      s.subscribe(yearly: false);
      expect(s.membershipExpiry!.difference(s.now).inDays, anyOf(29, 30));
      expect(s.aiMonthly, kMonthlyAiCredits);
      expect(s.isMember, isTrue);
    });

    test('年訂：到期日 +365 天', () {
      final s = AppState(demo: false);
      s.subscribe(yearly: true);
      expect(s.membershipExpiry!.difference(s.now).inDays, anyOf(364, 365));
      expect(s.isMember, isTrue);
    });
  });

  group('P87 取消訂閱', () {
    test('權益維持到期日，只是不再續約', () {
      final s = AppState(demo: false);
      s.subscribe(yearly: false);
      s.cancelSubscription();
      expect(s.membership, MembershipState.cancelledPending);
      expect(s.isMember, isTrue);
      addTearDown(resetAppClock);
      s.advanceDemoClock(const Duration(days: 29));
      expect(s.isMember, isTrue);
      s.advanceDemoClock(const Duration(days: 2));
      expect(s.isMember, isFalse);
    });
  });

  group('P88 非會員練滿 3 次', () {
    test('收不到建議，但計數照累計；訂閱當下立刻觸發一次', () {
      final s = AppState(demo: false);
      for (var i = 0; i < 3; i++) {
        _train(s);
      }
      expect(s.isMember, isFalse);
      expect(s.autoOptimizeCount, 3, reason: '計數照累計');
      expect(s.optimizedPlanId, isNull, reason: '非會員收不到建議');
      expect(s.session, isNull, reason: '也沒有擋住訓練');

      s.subscribe(yearly: false);
      expect(s.optimizedPlanId, isNotNull, reason: '訂閱當下已達 3 次 → 立即觸發');
      expect(s.autoOptimizeCount, 0);
    });
  });

  group('P89–P92 自訂課表', () {
    List<PlanExercise> exs(AppState s) => [
          PlanExercise(
              exercise: s.platformExercises.firstWhere(
                  (e) => e.type == ExerciseType.strength && !e.isBodyweight),
              planned: const [PlannedSet(40, 8), PlannedSet(40, 8)]),
        ];

    test('P89 建立並儲存：課表頁看得到，動作與組數沒跑掉', () {
      final s = AppState(demo: false);
      s.addPlan('我的課', exs(s));
      final p = s.customPlans.single;
      expect(p.state, CustomPlanState.saved);
      expect(p.totalSets, 2);
      expect(s.myPlanCount, 1);
    });

    test('P90 發布：狀態變已發布，自己選得到；不是公開', () {
      final s = AppState(demo: false);
      s.addPlan('我的課', exs(s));
      final p = s.customPlans.single;
      expect(s.selectableCustomPlans, isNot(contains(p)), reason: '儲存未啟用不可選用');
      s.publishPlan(p);
      expect(p.state, CustomPlanState.published);
      expect(s.selectableCustomPlans, contains(p));
      expect(p.state, isNot(CustomPlanState.public), reason: '發布不是公開');
    });

    test('P91 申請公開：顯示審核中並有 14 天期限，審核期間自己仍能用', () {
      final s = AppState(demo: false);
      s.addPlan('我的課', exs(s));
      final p = s.customPlans.single;
      s.publishPlan(p);
      s.applyPublic(p);
      expect(p.state, CustomPlanState.pendingPublic);
      expect(p.reviewDaysLeft, kPublicPlanReviewDays);
      expect(kPublicPlanReviewDays, 14);
      expect(s.selectableCustomPlans, contains(p), reason: '審核期間自己不能用就錯了');
    });

    test('P92 用它訓練後，使用次數 +1；沒做任何一組就不算', () {
      final s = AppState(demo: false);
      s.addPlan('我的課', exs(s));
      final p = s.customPlans.single;
      s.publishPlan(p);
      expect(p.myUses, 0);

      _train(s, plan: p.toWorkoutPlan());
      expect(p.myUses, 1);

      s.startWorkout(p.toWorkoutPlan());
      s.finishWorkout(EndKind.endedEarly); // 一組都沒做
      expect(p.myUses, 1, reason: '一組都沒完成不構成歷史訓練');
    });

    test('P92 別人的課表不會跟著動', () {
      final s = AppState(demo: false);
      s.addPlan('我的課', exs(s));
      final mine = s.customPlans.single;
      final theirs = CustomPlan(
        id: 'cp-他人',
        name: '別人的',
        exercises: exs(s),
        myUses: 0,
        state: CustomPlanState.public,
        author: '別人',
        isMine: false,
      );
      s.customPlans.add(theirs);
      _train(s, plan: mine.toWorkoutPlan());
      expect(theirs.myUses, 0);
    });

    test('P92 使用次數重新整理後還在；刪課表不影響訓練歷史', () async {
      final st = MemoryStore();
      final seed = AppState(demo: false);
      await seed.hydrate(MemoryStore());
      seed.signUpCompleted = true;
      await st.save(seed.toSnapshot());
      final s = AppState(demo: false);
      await s.hydrate(st);
      s.addPlan('我的課', exs(s));
      final p = s.customPlans.single;
      s.publishPlan(p);
      _train(s, plan: p.toWorkoutPlan());
      await s.saveNow();

      final back = AppState(demo: false);
      await back.hydrate(st);
      expect(back.customPlans.single.myUses, 1);

      final histBefore = back.history.length;
      back.customPlans.clear();
      expect(back.history.length, histBefore, reason: '刪課表不能連訓練歷史一起消失');
    });
  });

  group('P80 師徒頁（非示範帳號）', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: MentorScreen())),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('還沒解鎖：說明為什麼，並列出五項條件的進度', (t) async {
      final s = AppState(demo: false)..displayName = '我';
      s.interactionTotals.clear(); // 新帳號什麼都沒做過
      await open(t, s);

      expect(t.takeException(), isNull);
      expect(find.text('師徒功能尚未解鎖'), findsOneWidget);
      expect(find.text('尚未做過'), findsWidgets, reason: '要看得出還差哪幾項');
    });

    testWidgets('解鎖了但沒有教官可看：頁面正常，不是示範假資料', (t) async {
      final s = AppState(demo: false)..displayName = '我';
      s.followTotal = 1;
      for (final k in kInteractionKinds) {
        s.interactionTotals[k] = 1;
      }
      expect(s.mentorUnlocked, isTrue);
      await open(t, s);

      expect(t.takeException(), isNull);
      expect(s.instructors, isEmpty, reason: '非示範帳號不能有假教官');
      expect(find.text('師徒功能尚未解鎖'), findsNothing);
      for (final fake in ['教官甲', '阿教']) {
        expect(find.textContaining(fake), findsNothing);
      }
    });
  });
}
