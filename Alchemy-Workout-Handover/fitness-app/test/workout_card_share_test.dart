// 訓練結算的分享：成果卡變豐富（使用者 2026-10-16 要求，方向 A）。
//
// 原本分享出去的只有一行字「課表名 · 總重量 · 組數」。現在貼文帶一張結構化的成果卡：
// 完成度、訓練時間、連續天數、練了哪些動作、階級提升、能力值成長、這場解鎖的成就。
//
// 重點是**隱私**：卡片存進雲端、所有人讀得到，所以「不公開能力值」要在建卡片時就擋，
// 不能只在畫面上藏（藏在畫面上，雲端那份照樣被讀走）。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/post_data_firestore.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/domain/workout_card.dart';
import 'package:fitness_app/screens/settlement_screen.dart';
import 'package:fitness_app/screens/social/post_card.dart';
import 'package:fitness_app/screens/social/post_detail_screen.dart';
import 'package:fitness_app/screens/social/workout_card_view.dart';
import 'package:fitness_app/state/app_state.dart';

SettlementResult _result(AppState s) => SettlementResult(
      plan: WorkoutPlan(
        id: 'p',
        name: '推日：胸肩三頭',
        source: PlanSource.official,
        exercises: const [],
      ),
      kind: EndKind.completed,
      rewards: const SettlementRewards.none(),
      gains: {Dim.chest: 12, Dim.back: 0, Dim.arms: 5},
      pointsAfter: const {},
      measured: const {},
      doneSets: 9,
      plannedSets: 12,
      duration: const Duration(minutes: 48),
      volume: 4321.5,
      calories: 300,
      streakDays: 6,
      rankBefore: 47,
      rankAfter: 51,
      newlyUnlocked: [
        Achievement(
            category: '累積訓練',
            name: '累積訓練 50 天',
            threshold: 50,
            rewardCoins: 1,
            rewardExp: 1),
        Achievement(
            category: '能力值',
            name: '能力值 450',
            threshold: 450,
            rewardCoins: 1,
            rewardExp: 1),
      ],
      exerciseSummary: const [
        (name: '槓鈴臥推', sets: 4),
        (name: '啞鈴肩推', sets: 3),
        (name: '繩索下壓', sets: 2),
      ],
    );

void main() {
  group('成果卡的內容', () {
    test('完成度、時間、連續天數、動作、階級提升、成就都在', () {
      final s = AppState();
      final c = s.workoutCardOf(_result(s));
      expect(c.planName, '推日：胸肩三頭');
      expect(c.volumeKg, 4321.5);
      expect(c.doneSets, 9);
      expect(c.plannedSets, 12);
      expect(c.completionPercent, 75);
      expect(c.durationMinutes, 48);
      expect(c.streakDays, 6);
      expect([for (final e in c.exercises) (e.name, e.sets)],
          [('槓鈴臥推', 4), ('啞鈴肩推', 3), ('繩索下壓', 2)]);
      expect(c.rankedUp, isTrue);
      expect((c.rankFrom, c.rankTo), (47, 51));
      expect(c.achievements, contains('累積訓練 50 天'));
    });

    test('沒升階就沒有階級提升欄位', () {
      final s = AppState();
      final r = _result(s);
      final c = s.workoutCardOf(SettlementResult(
        plan: r.plan,
        kind: r.kind,
        rewards: r.rewards,
        gains: r.gains,
        pointsAfter: r.pointsAfter,
        measured: r.measured,
        doneSets: r.doneSets,
        plannedSets: r.plannedSets,
        duration: r.duration,
        volume: r.volume,
        calories: r.calories,
        streakDays: r.streakDays,
        rankBefore: 51,
        rankAfter: 51,
        newlyUnlocked: const [],
      ));
      expect(c.rankedUp, isFalse);
      expect(c.toJson().containsKey('rankFrom'), isFalse);
    });

    test('自由訓練（計畫組數 0）沒有完成度百分比', () {
      const c = WorkoutCard(
          planName: '自由訓練',
          volumeKg: 0,
          doneSets: 3,
          plannedSets: 0,
          durationMinutes: 10,
          streakDays: 0);
      expect(c.completionPercent, isNull);
    });
  });

  group('隱私：不公開能力值，卡片就不能有能力值', () {
    test('公開 → 附六維成長（只列有成長的）與能力值類成就', () {
      final s = AppState()..abilityPublic = true;
      final c = s.workoutCardOf(_result(s));
      expect(c.abilityGains, {Dim.chest: 12, Dim.arms: 5});
      expect(c.achievements, contains('能力值 450'));
    });

    test('不公開 → 沒有六維成長，也沒有「能力值 N」這類成就', () {
      final s = AppState()..abilityPublic = false;
      final c = s.workoutCardOf(_result(s));
      expect(c.abilityGains, isEmpty);
      expect(c.achievements, isNot(contains('能力值 450')));
      expect(c.achievements, contains('累積訓練 50 天'),
          reason: '其他成就照附');
      // 藏的是存進雲端的那一份，不只是畫面。
      expect(c.toJson().containsKey('abilityGains'), isFalse);
      expect(c.toJson().toString(), isNot(contains('450')));
    });

    test('教官身分讓開關失效（規格：成為教官等同接受這部分公開）', () {
      final s = AppState()
        ..abilityPublic = false
        ..isInstructor = true;
      expect(s.workoutCardOf(_result(s)).abilityGains, isNotEmpty);
    });

    test('階級提升不受開關影響（階級本來就公開）', () {
      final s = AppState()..abilityPublic = false;
      expect(s.workoutCardOf(_result(s)).rankedUp, isTrue);
    });

    test('只附前三個成就、前八個動作', () {
      final s = AppState();
      final r = _result(s);
      final many = SettlementResult(
        plan: r.plan,
        kind: r.kind,
        rewards: r.rewards,
        gains: r.gains,
        pointsAfter: r.pointsAfter,
        measured: r.measured,
        doneSets: r.doneSets,
        plannedSets: r.plannedSets,
        duration: r.duration,
        volume: r.volume,
        calories: r.calories,
        streakDays: r.streakDays,
        rankBefore: r.rankBefore,
        rankAfter: r.rankAfter,
        newlyUnlocked: [
          for (var i = 0; i < 6; i++)
            Achievement(
                category: '分享',
                name: '成就$i',
                threshold: i,
                rewardCoins: 1,
                rewardExp: 1),
        ],
        exerciseSummary: [for (var i = 0; i < 12; i++) (name: '動作$i', sets: 1)],
      );
      final c = s.workoutCardOf(many);
      expect(c.achievements, hasLength(3));
      expect(c.exercises, hasLength(8));
    });
  });

  group('真的分享出去', () {
    test('分享的貼文帶成果卡，也保留一行摘要給舊畫面', () {
      final s = AppState();
      final out = s.shareWorkout(_result(s), '練完了')!;
      expect(out.post.workoutCard, isNotNull);
      expect(out.post.attachedWorkout, contains('推日：胸肩三頭'));
      expect(out.post.attachedWorkout, contains('4322 kg'));
    });

    test('從真實的訓練走一趟：卡片裡有動作名稱與完成組數', () {
      final s = AppState();
      final plan = s.platformPlans.firstWhere(
          (p) => p.source == PlanSource.official && p.exercises.length >= 2);
      s.beginWorkout(plan);
      s.completeCurrentSet();
      final r = s.finishWorkout(EndKind.endedEarly);
      final c = s.shareWorkout(r, '')!.post.workoutCard!;
      expect(c.exercises, hasLength(1), reason: '只練了一組，沒碰的動作不列');
      expect(c.exercises.first.name, plan.exercises.first.exercise.name);
      expect(c.exercises.first.sets, 1);
      expect(c.doneSets, 1);
    });
  });

  group('存進雲端再讀回來', () {
    test('別人讀到完整的成果卡', () async {
      final db = FakeFirebaseFirestore();
      final s = AppState();
      final card = s.workoutCardOf(_result(s));
      await FirestorePosts(uid: 'a', firestore: db).publish(
        Post(
          id: 'share-1',
          author: '阿昶',
          authorRank: 51,
          text: '練完了',
          at: DateTime(2026, 9, 13, 10),
          attachedWorkout: card.summaryLine,
          workoutCard: card,
        ),
        authorUid: 'a',
      );
      final reader = FirestorePosts(uid: 'b', firestore: db);
      final back = (await reader.recent()).first.workoutCard!;
      expect(back.planName, card.planName);
      expect(back.completionPercent, 75);
      expect(back.durationMinutes, 48);
      expect([for (final e in back.exercises) (e.name, e.sets)],
          [('槓鈴臥推', 4), ('啞鈴肩推', 3), ('繩索下壓', 2)]);
      expect((back.rankFrom, back.rankTo), (47, 51));
      expect(back.abilityGains, {Dim.chest: 12, Dim.arms: 5});
    });

    test('舊貼文（只有一行摘要）照樣讀得回來', () async {
      final db = FakeFirebaseFirestore();
      await FirestorePosts(uid: 'a', firestore: db).publish(
        Post(
          id: 'old',
          author: '阿昶',
          authorRank: 45,
          text: '舊的',
          at: DateTime(2026, 9, 1),
          attachedWorkout: '胸推日　·　500 kg　·　12 組',
        ),
        authorUid: 'a',
      );
      final p = (await FirestorePosts(uid: 'b', firestore: db).recent()).first;
      expect(p.workoutCard, isNull);
      expect(p.attachedWorkout, '胸推日　·　500 kg　·　12 組');
    });

    test('成果卡格式壞掉：當作沒有，不拖垮動態牆', () {
      expect(WorkoutCard.fromJson('亂寫'), isNull);
      expect(WorkoutCard.fromJson({'volumeKg': 1}), isNull);
      expect(WorkoutCard.fromJson(null), isNull);
    });
  });

  group('畫面', () {
    Future<void> show(WidgetTester t, Post p) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: PostWorkoutAttachment(post: p)),
      ));
    }

    Post post(AppState s, {bool card = true}) {
      final c = s.workoutCardOf(_result(s));
      return Post(
        id: 'p',
        author: 'a',
        authorRank: 51,
        text: '',
        at: DateTime(2026, 9, 13),
        attachedWorkout: c.summaryLine,
        workoutCard: card ? c : null,
      );
    }

    testWidgets('成果卡畫出完成度、時間、動作、階級提升、能力值與成就', (t) async {
      final s = AppState();
      await show(t, post(s));
      expect(find.byKey(const ValueKey('workout-card')), findsOneWidget);
      expect(find.text('推日：胸肩三頭'), findsOneWidget);
      expect(find.textContaining('9 / 12 組（75%）'), findsOneWidget);
      // 三個數字磚：標籤＋數值＋單位。
      expect(find.text('總重量'), findsOneWidget);
      expect(find.text('4322'), findsOneWidget);
      expect(find.text('訓練時間'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('連續訓練'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.textContaining('槓鈴臥推 × 4'), findsOneWidget);
      expect(find.textContaining('47 → 51 階'), findsOneWidget);
      expect(find.textContaining('胸 +12'), findsOneWidget);
      expect(find.textContaining('累積訓練 50 天'), findsOneWidget);
    });

    testWidgets('動態牆的貼文卡與貼文詳情頁都畫成果卡，不是舊的一行', (t) async {
      t.view.physicalSize = const Size(393 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState();
      final p = post(s);
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: PostCard(post: p))),
        ),
      ));
      expect(find.byKey(const ValueKey('workout-card')), findsOneWidget);
      expect(find.textContaining('9 / 12 組（75%）'), findsOneWidget);

      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(home: PostDetailScreen(post: p)),
      ));
      await t.pump();
      expect(find.byKey(const ValueKey('workout-card')), findsOneWidget);
      expect(find.textContaining('9 / 12 組（75%）'), findsOneWidget);
    });

    testWidgets('窄螢幕上數字很長也不爆版', (t) async {
      t.view.physicalSize = const Size(320 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      const big = WorkoutCard(
        planName: '一個名字很長很長很長很長很長很長很長的課表',
        volumeKg: 123456,
        doneSets: 120,
        plannedSets: 120,
        durationMinutes: 1234,
        streakDays: 365,
        exercises: [
          WorkoutCardExercise('一個名字很長很長的動作 · 啞鈴', 12),
          WorkoutCardExercise('另一個名字很長很長的動作 · 槓鈴', 12),
        ],
        rankFrom: 100,
        rankTo: 101,
        abilityGains: {Dim.chest: 123, Dim.back: 123, Dim.legs: 123},
        achievements: ['成就名稱很長很長很長很長', '另一個很長很長的成就名稱'],
      );
      // 版面爆掉時 Flutter 會丟 RenderFlex overflow，測試就會紅。
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: WorkoutCardView(card: big))),
      ));
      await t.pump();
      expect(find.byKey(const ValueKey('workout-card')), findsOneWidget);
      // 數字縮小之後仍在磚裡面：單位「kg」的右緣不能超過它所在那格的右緣。
      final box = find
          .ancestor(of: find.text('kg'), matching: find.byType(FittedBox))
          .first;
      expect(t.getTopRight(find.text('kg')).dx,
          lessThanOrEqualTo(t.getTopRight(box).dx + 0.5),
          reason: '不縮小的話數字會被截掉，畫面上只剩半個數字');
    });

    testWidgets('品牌列：「健金術」與「階級提升」徽章同一行時至少隔一格間距', (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.view.devicePixelRatio = 1.0;
      const card = WorkoutCard(
        planName: '推日：胸肩三頭',
        volumeKg: 1920,
        doneSets: 4,
        plannedSets: 13,
        durationMinutes: 15,
        streakDays: 1,
        exercises: [],
        rankFrom: 64,
        rankTo: 67,
        abilityGains: {},
        achievements: [],
      );
      var sameRow = 0;
      // 掃過各種螢幕寬度：兩者剛好塞滿一行、中間沒縫的那個寬度一定會被掃到。
      for (var w = 260.0; w <= 460.0; w += 1) {
        t.view.physicalSize = Size(w, 2400);
        await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: WorkoutCardView(card: card))),
        ));
        final brand = t.getRect(find
            .ancestor(of: find.text('健金術'), matching: find.byType(Row))
            .first);
        final badge = t.getRect(find
            .ancestor(
                of: find.textContaining('階級提升'), matching: find.byType(Container))
            .first);
        if ((brand.center.dy - badge.center.dy).abs() < brand.height) {
          sameRow++;
          expect(badge.left - brand.right, greaterThanOrEqualTo(8 - 0.01),
              reason: '寬度 $w：品牌與徽章貼在一起了');
        }
      }
      expect(sameRow, greaterThan(0), reason: '掃描範圍內要有「同一行」的情形，否則測不到東西');
    });

    testWidgets('分享對話框先預覽要發出去的那張卡', (t) async {
      t.view.physicalSize = const Size(393 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState();
      final plan = s.platformPlans.firstWhere(
          (p) => p.source == PlanSource.official && p.exercises.length >= 2);
      s.beginWorkout(plan);
      s.completeCurrentSet();
      s.finishWorkout(EndKind.endedEarly);
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: SettlementScreen()),
      ));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('分享成果'), 300,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('分享成果'));
      await t.pumpAndSettle();
      expect(find.text('分享這次訓練'), findsOneWidget);
      expect(find.byKey(const ValueKey('workout-card')), findsOneWidget,
          reason: '發出去之前要先看得到那張卡');
      expect(find.textContaining(plan.name), findsWidgets);
    });

    testWidgets('舊貼文只畫一行摘要', (t) async {
      final s = AppState();
      await show(t, post(s, card: false));
      expect(find.byKey(const ValueKey('workout-card')), findsNothing);
      expect(find.textContaining('4322 kg'), findsOneWidget);
    });

    testWidgets('不公開能力值的人發的卡，畫面上沒有能力值', (t) async {
      final s = AppState()..abilityPublic = false;
      await show(t, post(s));
      expect(find.textContaining('胸 +12'), findsNothing);
      expect(find.textContaining('能力值'), findsNothing);
    });
  });
}
