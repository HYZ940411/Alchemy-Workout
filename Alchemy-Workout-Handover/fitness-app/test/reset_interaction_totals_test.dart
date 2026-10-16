// 互動計數的自救鍵（2026-09-28 使用者裁決 A）。
//
// 使用者的帳號上有一組假的互動計數（示範種子漏進真帳號，見 1F）。
// 根因修好了，但那個數字**早就被存進雲端**，而它**沒辦法從證據修補**——
// 天數可以從訓練歷史重算，「按過幾個讚」沒有一份完整的紀錄可查
//（讚存在每篇貼文底下，貼文會被刪、動態牆會分頁）。
//
// 與其硬湊一個數字，不如給一顆讓他自己歸零的按鈕。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('歸零之後四類都是 0', () {
    final s = AppState();
    expect(s.interactionTotals['按讚'], greaterThan(0), reason: '前提：本來有值');
    s.resetInteractionTotals();
    for (final k in kInteractionKinds) {
      expect(s.interactionTotals[k] ?? 0, 0, reason: k);
    }
  });

  // 規格：一經解鎖不可撤銷。`persistence_test` 也釘著這一條。
  test('已解鎖的成就不會被收回', () {
    final s = AppState();
    final before =
        s.achievements.where((a) => a.unlocked).map((a) => a.name).toSet();
    expect(before, isNotEmpty, reason: '前提：本來有解鎖的');
    s.resetInteractionTotals();
    final after =
        s.achievements.where((a) => a.unlocked).map((a) => a.name).toSet();
    expect(after.containsAll(before), isTrue);
  });

  Future<void> openSettings(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('一般使用者看不到這顆鍵', (t) async {
    await openSettings(t, AppState(demo: false));
    // **捲到底再看。** 不捲的話「找不到」可能只是因為它在畫面外，
    // 那樣這條測試永遠會過。
    for (var i = 0; i < 16; i++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await t.pumpAndSettle();
    }
    expect(find.text('重設互動計數'), findsNothing);
  });

  testWidgets('開發者模式看得到', (t) async {
    await openSettings(t, AppState(demo: false)..toggleDeveloperMode());
    await t.scrollUntilVisible(
      find.text('重設互動計數'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('重設互動計數'), findsOneWidget);
  });

  testWidgets('要先確認才歸零 —— 按了取消不動', (t) async {
    final s = AppState(demo: false)..toggleDeveloperMode();
    final before = s.interactionTotals['按讚'];
    expect(before, greaterThan(0));

    await openSettings(t, s);
    await t.scrollUntilVisible(
      find.text('重設互動計數'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible 只保證它在樹裡，不保證在螢幕內；設定頁加了一塊診斷面板之後，
    // 這顆鍵剛好落在 600 高的測試畫面外，點下去落空。先確保它真的在畫面內再點。
    await t.ensureVisible(find.text('重設互動計數'));
    await t.pumpAndSettle();
    await t.tap(find.text('重設互動計數'));
    await t.pumpAndSettle();
    expect(find.textContaining('已經解鎖的成就不會被收回'), findsOneWidget);

    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(s.interactionTotals['按讚'], before, reason: '取消就不該動');
  });
}
