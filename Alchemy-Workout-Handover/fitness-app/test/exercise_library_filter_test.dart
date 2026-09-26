import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/mock/mock_equipment.dart';
import 'package:fitness_app/screens/train/exercise_library_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 動作庫頁的搜尋與器材篩選。
///
/// **這一頁的篩選行為原本一條自動測試都沒有** —— 而 2026-09-27 我把它的
/// 判準（`exerciseMatchesFilter`）與篩選條（`EquipmentFilterBar`）抽出去
/// 與「加入動作」抽屜共用，把私有副本刪了。那種重構最容易靜默地改掉行為，
/// 而當時唯一守著這一頁的是 `screen_crawl_test`（只驗不爆版）。
///
/// 抽出去的兩樣東西在抽屜那一側有 `exercise_picker_filter_test.dart` 守著；
/// 這一份守的是**動作庫這一側仍然照原來的方式使用它們**。
void main() {
  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: ExerciseLibraryScreen()),
    ));
    await t.pumpAndSettle();
  }

  group('器材篩選', () {
    testWidgets('預設帶入持有器材明細 —— 不是全部不篩', (t) async {
      // 這一頁與抽屜刻意不同：瀏覽介面要回答「我做得到什麼」。
      final s = AppState();
      await open(t, s);
      expect(find.textContaining('器材篩選：${s.equipmentForFiltering.length} 項'),
          findsOneWidget);
    });

    testWidgets('八個品項都有一顆鍵', (t) async {
      await open(t, AppState());
      for (final item in kEquipmentItems) {
        expect(find.text(item), findsWidgets, reason: '$item 應該有一顆鍵');
      }
    });

    testWidgets('「清除」之後變成不篩', (t) async {
      await open(t, AppState());
      await t.tap(find.text('清除'));
      await t.pumpAndSettle();
      expect(find.textContaining('器材篩選：全部動作'), findsOneWidget);
    });

    testWidgets('點一個品項會改變篩選的項數', (t) async {
      final s = AppState();
      await open(t, s);
      final before = s.equipmentForFiltering.length;
      // 取一個他沒有的品項，點下去就是「多選一項」。
      final notOwned =
          kEquipmentItems.firstWhere((i) => !s.equipmentForFiltering.contains(i));
      await t.tap(find.text(notOwned).first);
      await t.pumpAndSettle();
      expect(find.textContaining('器材篩選：${before + 1} 項'), findsOneWidget);
    });
  });

  group('名稱搜尋', () {
    testWidgets('搜不到東西時說得出來，不是一片空白', (t) async {
      await open(t, AppState());
      await t.enterText(find.byType(TextField).first, '不可能有這個動作的名字');
      await t.pumpAndSettle();
      expect(find.textContaining('換個關鍵字'), findsWidgets);
    });

    testWidgets('搜尋跨全部分頁生效 —— 不是只篩當前分頁', (t) async {
      // 「名稱搜尋與器材篩選皆為頁面層級，跨全部分頁生效」（這一頁的註解）。
      final s = AppState();
      await open(t, s);
      await t.enterText(find.byType(TextField).first, '不可能有這個動作的名字');
      await t.pumpAndSettle();
      // 切到另一個分頁，空狀態仍然在 —— 搜尋沒有隨分頁重置。
      await t.tap(find.text('有氧'));
      await t.pumpAndSettle();
      expect(find.textContaining('換個關鍵字'), findsWidgets);
    });
  });

  group('與「加入動作」抽屜共用同一個判準', () {
    // 兩邊各寫一份的話，同一個關鍵字在兩處會篩出不同的結果。
    test('判準是同一支函式', () {
      final s = AppState();
      final owned = s.equipmentForFiltering;
      for (final e in s.platformExercises.take(30)) {
        final byShared = exerciseMatchesFilter(
            (name: e.name, equipment: e.equipment),
            owned: owned,
            query: '');
        // 手寫一次原本的邏輯，兩者必須一致。
        final need = requiredEquipment(e.equipment);
        final byHand =
            owned.isEmpty || (need.isNotEmpty && need.every(owned.contains));
        expect(byShared, byHand, reason: e.name);
      }
    });
  });
}
