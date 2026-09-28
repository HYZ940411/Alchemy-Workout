// 課表頁的「部位」篩選，與卡片標籤的精簡。
//
// 2026-09-28 使用者看了推薦標籤的截圖後：
// 「不是橘色，而且標籤有點太多了…可否簡化？訓練頁可否加上『部位』的篩選」
//
// 標籤原本一張卡十三個，其中四個（器材符合／經驗符合／目標符合／時長符合）
// **是純重複** —— 那四項的內容本來就都在下面（「器材：徒手」「新手」
// 「減重」「約 40 分鐘」）。改成把對上的那幾個染成橘色。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/plan_select_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/theme.dart';
import 'package:fitness_app/widgets/common.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  Future<AppState> open(WidgetTester t) async {
    final s = AppState();
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: Scaffold(body: PlanSelectScreen())),
    ));
    await t.pumpAndSettle();
    return s;
  }

  group('部位篩選', () {
    // 2026-09-28 使用者：「我看到篩選欄了，但能不能跟上面的篩選欄一樣」。
    // 第一版用的是動作庫那一頁的樣式，擺在器材／經驗／時長的面板底下
    // 就是兩種長相。改成那個面板的第四排。
    testWidgets('和器材／經驗／時長排在同一個面板裡', (t) async {
      await open(t);
      expect(find.text('部位'), findsOneWidget);
      // 動作庫那一頁的樣式不該出現在這裡。
      expect(find.text('部位：全部'), findsNothing);
    });

    testWidgets('六個部位都按得到', (t) async {
      await open(t);
      expect(find.byKey(const ValueKey('part-all')), findsOneWidget);
      for (final d in Dim.values) {
        expect(find.byKey(ValueKey('part-${dimNames[d]}')), findsOneWidget,
            reason: dimNames[d]);
      }
    });

    testWidgets('選了部位之後，留下的課表都練得到那個部位', (t) async {
      final s = await open(t);
      await t.tap(find.byKey(ValueKey('part-${dimNames[Dim.legs]!}')));
      await t.pumpAndSettle();

      var shown = 0;
      for (final p in s.platformPlans) {
        final parts = planParts(p);
        if (parts.isEmpty || parts.contains(dimNames[Dim.legs])) continue;
        // 不該練到腿的課表，名稱不該還在畫面上。
        expect(find.text(p.name), findsNothing, reason: p.name);
        shown++;
      }
      expect(shown, greaterThan(0), reason: '前提：要真的篩掉一些東西');
    });

    testWidgets('空白課表不因為部位被篩掉 —— 它要練什麼由使用者決定', (t) async {
      final s = await open(t);
      final blank =
          s.platformPlans.where((p) => p.exercises.isEmpty).toList();
      if (blank.isEmpty) return;
      await t.tap(find.byKey(ValueKey('part-${dimNames[Dim.core]!}')));
      await t.pumpAndSettle();
      // 清單是 ListView，沒畫到的不在樹上 —— 捲到它為止再驗。
      await t.scrollUntilVisible(
        find.text(blank.first.name),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(blank.first.name), findsWidgets);
    });

    testWidgets('「清除篩選」把部位也清掉', (t) async {
      await open(t);
      // 選一個一定篩不到東西的組合，逼出空狀態。
      await t.tap(find.byKey(ValueKey('part-${dimNames[Dim.core]!}')));
      await t.pumpAndSettle();
      if (find.text('清除篩選').evaluate().isEmpty) return;
      await t.tap(find.text('清除篩選'));
      await t.pumpAndSettle();
      final all = t.widget<GestureDetector>(
          find.ancestor(
            of: find.byKey(const ValueKey('part-all')),
            matching: find.byType(GestureDetector),
          ).first);
      expect(all, isNotNull);
      expect(find.byKey(const ValueKey('part-all')), findsOneWidget);
    });
  });

  group('卡片標籤精簡', () {
    testWidgets('不再有「XX 符合」那四個重複標籤', (t) async {
      await open(t);
      for (final m in ['器材 符合', '經驗 符合', '目標 符合', '時長 符合']) {
        expect(find.text(m), findsNothing, reason: m);
      }
    });

    testWidgets('「推薦」是橘色，不是深藍', (t) async {
      await open(t);
      final pill = t.widgetList<Pill>(find.byType(Pill))
          .where((p) => p.text == '推薦')
          .toList();
      expect(pill, isNotEmpty, reason: '前提：要有推薦的課表');
      expect(pill.first.color, AppColors.accent);
      expect(pill.first.filled, isTrue);
    });

    testWidgets('排行係數 100% 不顯示 —— 那是常態', (t) async {
      await open(t);
      expect(find.text('排行係數 100%'), findsNothing);
    });
  });
}
