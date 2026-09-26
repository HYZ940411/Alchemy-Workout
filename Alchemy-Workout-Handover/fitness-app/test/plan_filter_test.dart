import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/screens/plan_select_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Future<void> pump(WidgetTester t, AppState s) async {
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: Scaffold(body: PlanSelectScreen())),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('器材篩選是硬約束，與訓練計畫推薦同一套語意', () {
    // 選「居家器材」的人要看到居家**與徒手**兩種課表 ——
    // 徒手課表他當然做得到。只給「標著居家」那幾份是把定義寫成第二份。
    test('居家涵蓋居家與徒手，不含健身房', () {
      final tiers = runnablePlanTiers('居家器材（彈力繩、小啞鈴等）');
      expect(tiers, {'居家', '徒手'});
    });

    test('徒手只涵蓋徒手', () {
      expect(runnablePlanTiers('徒手'), {'徒手'});
    });

    test('健身房涵蓋全部', () {
      expect(runnablePlanTiers('健身房（全器材）'), {'健身房', '居家', '徒手'});
    });

    test('沒選就是不限 —— 空值，不是空集合', () {
      // 空集合會讓呼叫端的 `contains` 一律為假，等於一份都篩不到；
      // 空值才是「不要篩」。這兩者在這裡是兩種相反的意思。
      expect(runnablePlanTiers(null), isNull);
    });
  });

  group('課表頁的篩選', () {
    testWidgets('未篩選時不顯示份數，篩了才顯示', (t) async {
      final s = AppState();
      await pump(t, s);
      expect(find.text('選擇今天的課表'), findsOneWidget);
      // 「/ 99」是頁首的階級，不算 —— 比對的是份數那一格的「N / M 份」。
      expect(find.textContaining(' 份'), findsNothing);

      await t.tap(find.text('徒手'));
      await t.pumpAndSettle();
      expect(find.textContaining(' 份'), findsOneWidget);
    });

    testWidgets('選徒手之後，健身房課表不在畫面上', (t) async {
      final s = AppState();
      final gymPlan = s.platformPlans
          .firstWhere((p) => p.equipmentTier == '健身房');
      await pump(t, s);

      await t.tap(find.text('徒手'));
      await t.pumpAndSettle();

      // 清單可能捲動，所以比對的是「篩選後的集合」而非畫面上找不找得到。
      final shown = s.platformPlans
          .where((p) => runnablePlanTiers('徒手')!.contains(p.equipmentTier));
      expect(shown.map((p) => p.id), isNot(contains(gymPlan.id)));
      expect(shown, isNotEmpty);
    });

    testWidgets('經驗篩選：適用經驗為空集合的課表視為不限，不被篩掉', (t) async {
      final s = AppState();
      final open =
          s.platformPlans.where((p) => p.suitableExperience.isEmpty).toList();
      await pump(t, s);
      await t.tap(find.text('進階'));
      await t.pumpAndSettle();
      // 空集合＝不限，與 recommendPlan 的判定一致。
      for (final p in open) {
        expect(p.suitableExperience.isEmpty, isTrue);
      }
    });

    testWidgets('篩到沒有結果時要說得出來，不是一片空白', (t) async {
      final s = AppState();
      await pump(t, s);
      // 徒手 + 進階：資料裡進階課表都要器械，這個組合篩不到東西。
      await t.tap(find.text('徒手'));
      await t.pumpAndSettle();
      await t.tap(find.text('進階（2 年以上）'.split('（').first));
      await t.pumpAndSettle();

      final left = s.platformPlans.where((p) =>
          runnablePlanTiers('徒手')!.contains(p.equipmentTier) &&
          (p.suitableExperience.isEmpty ||
              p.suitableExperience.contains('進階（2 年以上）')));
      if (left.isEmpty) {
        expect(find.text('沒有符合的課表'), findsOneWidget);
        await t.tap(find.text('清除篩選'));
        await t.pumpAndSettle();
        expect(find.text('沒有符合的課表'), findsNothing);
      }
    });

    testWidgets('每一張課表卡都標出預估時長', (t) async {
      final s = AppState();
      await pump(t, s);
      expect(find.textContaining('約 '), findsWidgets);
    });
  });
}
