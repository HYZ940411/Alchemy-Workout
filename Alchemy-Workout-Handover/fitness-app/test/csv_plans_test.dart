// 《健身計劃.csv》匯入的 27 份課表。
//
// 這些不是假資料 —— 是有人整理過、附學理依據、使用者會照著練的內容。
// 所以它們要驗的東西比假資料嚴格：動作要真的存在、組數次數要落在
// 人做得到的範圍、說明性內容不能是空的。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/screens/train/plan_detail_screen.dart';

import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';
import 'package:fitness_app/mock/platform_plans.g.dart';
import 'package:fitness_app/state/app_state.dart';

/// 只取《健身計劃.csv》產生的那 27 份。
///
/// 2026-09-29 起 `buildCsvPlans()` 還包含四份從 `kPlans` 搬上雲的官方課表
/// （見 `kLegacyPlanSpecs`），而本檔驗的是 **CSV 這個來源**的性質 ——
/// 「目標重量一律為 0」「不設階級門檻」那些只對 CSV 成立，
/// 搬過來的四份本來就帶著重量與階級。
List<WorkoutPlan> csvOnly() =>
    buildCsvPlansFrom(kPlatformPlans, kPlatformExercises);

void main() {
  group('資料本身', () {
    test('27 份課表，四個級別都在', () {
      expect(kPlatformPlans, hasLength(27));
      expect(kPlatformPlans.map((p) => p.level).toSet(), {
        '學員級',
        '戰士級',
        '精銳級',
        '功能重啟級',
      });
    });

    test('每個動作都對得上動作庫', () {
      final ids = kPlatformExercises.map((e) => e.id).toSet();
      for (final p in kPlatformPlans) {
        for (final it in p.items) {
          expect(
            ids,
            contains(it.exerciseId),
            reason: '${p.name} 引用了不存在的動作 ${it.exerciseId}',
          );
        }
      }
    });

    test('課表 ID 不重複，也不跟既有的七份假課表撞', () {
      final ids = kPlatformPlans.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(kPlans.any((p) => p.id == id), isFalse, reason: 'ID 撞了：$id');
      }
    });

    test('說明性內容一段都不能空', () {
      for (final p in kPlatformPlans) {
        for (final (label, text) in [
          ('介紹', p.intro),
          ('使用說明', p.howTo),
          ('負荷', p.load),
          ('訓練效果', p.effect),
          ('技術特點', p.technique),
          ('時長', p.duration),
          // 一份說得出依據的課表與一份憑空編的，對使用者是兩件事。
          ('學理依據', p.reference),
        ]) {
          expect(text.trim(), isNotEmpty, reason: '${p.name} 的「$label」是空的');
        }
      }
    });

    test('組數與每組量都落在人做得到的範圍', () {
      for (final p in kPlatformPlans) {
        for (final it in p.items) {
          final where = '${p.name} / ${it.exerciseId}';
          expect(
            it.sets,
            inInclusiveRange(1, 8),
            reason: '$where 組數 ${it.sets}',
          );
          expect(
            it.restSeconds,
            inInclusiveRange(0, 300),
            reason: '$where 休息 ${it.restSeconds} 秒',
          );
          if (it.unit == PlanUnit.reps) {
            expect(
              it.amount,
              inInclusiveRange(1, 50),
              reason: '$where 次數 ${it.amount}',
            );
          } else {
            expect(
              it.amount,
              inInclusiveRange(5, 600),
              reason: '$where 秒數 ${it.amount}',
            );
          }
        }
      }
    });

    test('每份課表至少一個動作', () {
      for (final p in kPlatformPlans) {
        expect(p.items, isNotEmpty, reason: '${p.name} 沒有動作');
      }
    });

    test('27 份全部不設階級門檻', () {
      // 2026-09-09 使用者裁示：級別只作為難度提示，不擋人。
      // Beta 期間多數測試者階級都低，設了門檻等於大半內容收不到回饋；
      // 回歸課表更不該鎖 —— 退步的人才需要它。
      for (final p in kPlatformPlans) {
        expect(p.requiredRank, isNull, reason: '${p.name} 不該設門檻');
      }
    });

    test('級別仍然標得出來 —— 不擋人不等於不標示難度', () {
      for (final p in kPlatformPlans) {
        expect(p.level.trim(), isNotEmpty);
      }
    });
  });

  group('轉成 App 的課表', () {
    test('27 份都進得了平台課表清單', () {
      final s = AppState();
      for (final spec in kPlatformPlans) {
        expect(
          s.platformPlans.any((p) => p.id == spec.id),
          isTrue,
          reason: '${spec.name} 沒進到 platformPlans',
        );
      }
      // 目錄 = 31 份平台課表（27 CSV ＋ 4 份 2026-09-29 搬上雲的官方課表）
      // ＋ 示範課表 ＋ 空白課表。
      expect(s.platformPlans.length,
          kAllPlanSpecs.length + kDemoPlans.length + kPlans.length);
    });

    test('組數展開成同樣多的 PlannedSet', () {
      final plans = csvOnly();
      for (var i = 0; i < plans.length; i++) {
        final spec = kPlatformPlans[i];
        for (var j = 0; j < spec.items.length; j++) {
          expect(
            plans[i].exercises[j].planned,
            hasLength(spec.items[j].sets),
            reason: '${spec.name} 第 ${j + 1} 個動作的組數對不上',
          );
        }
      }
    });

    test('目標重量一律為 0 —— 這份資料以 RPE 開處方，不指定公斤', () {
      for (final p in csvOnly()) {
        for (final e in p.exercises) {
          for (final st in e.planned) {
            expect(st.targetWeight, 0, reason: '${p.name} 出現了一個憑空指定的重量');
          }
        }
      }
    });

    test('組間休息帶過去了 —— 課表指定值是取值優先序的第一順位', () {
      final plans = csvOnly();
      for (var i = 0; i < plans.length; i++) {
        for (var j = 0; j < plans[i].exercises.length; j++) {
          expect(
            plans[i].exercises[j].restSeconds,
            kPlatformPlans[i].items[j].restSeconds,
          );
        }
      }
    });

    test('階級 1 的新帳號，27 份全部打得開', () {
      final s = AppState()..resetToNewAccount();
      expect(s.rank, 1);
      for (final spec in kPlatformPlans) {
        final plan = s.platformPlans.firstWhere((p) => p.id == spec.id);
        expect(
          s.planUnlocked(plan),
          isTrue,
          reason: '${spec.name}（${spec.level}）階級 1 打不開',
        );
      }
    });

    test('真的練得起來 —— 隨便挑一份走完一次訓練', () {
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.id == 'csv00');
      s.startWorkout(plan);
      expect(s.session, isNotNull);
      var guard = 0;
      while (s.currentRecord != null && guard++ < 200) {
        s.completeCurrentSet();
        s.skipRest();
      }
      final r = s.finishWorkout(EndKind.completed);
      expect(r, isNotNull);
      expect(r.doneSets, greaterThan(0));
      expect(s.history.first.planName, plan.name);
    });
  });

  group('課表詳情頁', () {
    Future<AppState> open(WidgetTester t, String planId) async {
      t.view.physicalSize = const Size(375 * 3, 667 * 3); // 最窄機型
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final s = AppState();
      final plan = s.platformPlans.firstWhere((p) => p.id == planId);
      await t.pumpWidget(
        AppScope(
          state: s,
          child: MaterialApp(home: PlanDetailScreen(plan: plan)),
        ),
      );
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('CSV 課表看得到介紹與依據', (t) async {
      await open(t, 'csv00');
      expect(find.text('這份課表在做什麼'), findsOneWidget);

      // 依據那一塊在螢幕外 —— ListView 不會建出沒進到視窗的節點，
      // 不捲下去就等於斷言了一個從未存在的東西。
      await t.dragUntilVisible(
        find.text('依據'),
        find.byType(Scrollable).first,
        const Offset(0, -220),
      );
      await t.pumpAndSettle();

      expect(find.text('依據'), findsOneWidget);
      expect(find.text('學員級'), findsWidgets);
      expect(
        find.textContaining('ACSM'),
        findsWidgets,
        reason: '學理依據要真的印出來，不是留一塊空白',
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('長段落收合得起來，也展得開', (t) async {
      await open(t, 'csv00');
      final head = find.text('怎麼練');
      expect(head, findsOneWidget);
      await t.tap(head);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '展開時爆了');
      await t.tap(head);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('沒有說明資料的假課表不擠出空白區塊', (t) async {
      await open(t, 'p_push');
      expect(find.text('這份課表在做什麼'), findsNothing);
      expect(find.text('依據'), findsNothing);
      expect(find.text('課表內容'), findsOneWidget, reason: '該有的還是要有');
    });

    testWidgets('最窄機型也不爆版', (t) async {
      // 使用說明平均 295 字，技術特點 180 字 —— 這是最容易爆的一頁。
      for (final id in ['csv00', 'csv05', 'csv18', 'csv26']) {
        await open(t, id);
        expect(t.takeException(), isNull, reason: '$id 爆了');
      }
    });
  });

  // 2026-09-26 使用者裁決（第二次，範圍擴大到側棒式）：
  // 等長支撐不以「下」計量。
  //
  // 使用者回報「棒式在一份課表裡被開成 2 組 × 12 下」。前棒式是純等長支撐，
  // 沒有「一下」這回事 —— 而課表卡與詳情頁會照著顯示「12 下」，
  // 預估時長也會把它當成 12 次 × 5 秒來算。
  //
  // 改的是來源 CSV（`健身計劃-組數次數.csv` 課表 9 動作序 8）不是生成檔，
  // 換算取自同一份資料裡作者自己寫的等式：課表 14（同為戰士級）
  // 「每個動作 12–15 下（或 45 秒）」。
  //
  // 側棒式那三列一開始沒動，理由是側棒式抬臀（hip dips）是真的可以數下的
  // 動作。2026-09-26 使用者確認那三份課表的原意不是抬臀，一併改成秒。
  //
  // 換算一律取自**同一份資料裡作者自己寫的等式**，不是我估的：
  // 課表 13（學員級）「每個動作 10–12 下（或 30 秒）」、
  // 課表 14（戰士級）「每個動作 12–15 下（或 45 秒）」。
  group('等長支撐以秒計量', () {
    /// 純等長支撐的動作 ID。這幾個動作沒有「一下」這回事。
    const isometric = {'plank', 'p194', 'p248'};

    test('沒有任何一份課表以「下」開等長支撐', () {
      final bad = [
        for (final p in kPlatformPlans)
          for (final it in p.items)
            if (isometric.contains(it.exerciseId) && it.unit == PlanUnit.reps)
              '${p.id} ${p.name} ${it.exerciseId}',
      ];
      expect(bad, isEmpty);
    });

    // 逐列釘住換算結果。只驗「不是 reps」的話，把秒數改錯也測不出來。
    test('四列的秒數各自正確，且組數與休息不動', () {
      final cases = [
        // 課表, 動作, 組數, 秒數, 休息, 換算依據
        ('csv09', 'plank', 2, 45, 60, '戰士級 12–15 下 ≡ 45 秒'),
        ('csv11', 'p194', 2, 20, 60, '學員級 3 秒／下 × 6 下 ≈ 20 秒'),
        ('csv16', 'p248', 3, 30, 45, '學員級 10–12 下 ≡ 30 秒'),
        ('csv17', 'p248', 3, 45, 60, '戰士級 12–15 下 ≡ 45 秒'),
      ];
      for (final (planId, exId, sets, secs, rest, why) in cases) {
        final plan = kPlatformPlans.firstWhere((p) => p.id == planId);
        final it = plan.items.firstWhere((i) => i.exerciseId == exId);
        expect(it.unit, PlanUnit.seconds, reason: '$planId $exId');
        expect(it.amount, secs, reason: '$planId $exId：$why');
        expect(it.sets, sets, reason: '$planId $exId：組數不動');
        expect(it.restSeconds, rest, reason: '$planId $exId：休息不動');
      }
    });

    // 作者自己寫過等式的那兩列不該被動到 —— 它們本來就有秒數。
    test('本來就有秒數的那幾列不受影響', () {
      for (final (planId, exId, secs) in [
        ('csv13', 'plank', 30),
        ('csv14', 'p248', 45),
      ]) {
        final plan = kPlatformPlans.firstWhere((p) => p.id == planId);
        final it = plan.items.firstWhere((i) => i.exerciseId == exId);
        expect(it.unit, PlanUnit.seconds);
        expect(it.amount, secs);
      }
    });
  });
}
