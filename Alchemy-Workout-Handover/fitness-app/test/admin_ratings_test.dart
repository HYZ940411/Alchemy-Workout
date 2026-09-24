// 管理員評分彙總：真帳號不該看到編出來的數字（2026-09-24）。
//
// 使用者問「確認管理員能看到他們的評分嗎」。查證結果是**看不到**，
// 而且比「看不到」更糟：
//
//   · `ratingSummaries` **沒有 `demo` 開關**（旁邊的 `posts`／`socialUsers`
//     ／`instructors` 全都有），所以真實的管理員打開「評分彙總」，
//     看到的是一張編出來的表：幾份訓練計畫、各自的平均星等與則數。
//   · 而使用者真正的評分存在 `users/{uid}` 的存檔裡 ——
//     依 `firestore.rules`，那棵樹**只有本人讀得到**。
//
// 這張表的用途正是回答「哪一份訓練計畫該改」（`02_Aggregate定義.md`
// 明寫「本評分的唯一讀者（管理員評分彙總）」）。拿假數字回答那個問題，
// 比回答不了更糟 —— 守則第 5 條：填錯的數字比留白更糟，
// 留白會被看見，錯的不會。
//
// 真正接上要讓評分獨立成自己的 collection（規格本來就說它是獨立
// Aggregate，理由正是「需要逐筆下鑽查詢」）。見 PROGRESS.md `[BE-18]`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/screens/admin/admin_ratings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Future<void> _pump(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
      AppScope(state: s, child: const MaterialApp(home: AdminRatingsScreen())));
  await t.pumpAndSettle();
}

void main() {
  test('非示範帳號沒有編出來的彙總', () {
    expect(AppState(demo: false).ratingSummaries, isEmpty);
  });

  test('示範身分維持原樣 —— 那張表還撐著「這一頁長什麼樣」', () {
    expect(AppState().ratingSummaries, isNotEmpty);
  });

  testWidgets('空的時候說清楚為什麼空，而不是留一張空表', (t) async {
    await _pump(t, AppState(demo: false));

    expect(find.textContaining('評分尚未接上後台'), findsOneWidget);
    // 「延遲更新　·　資料更新於 2 小時前」在沒有資料時是句假話。
    expect(find.textContaining('資料更新於'), findsNothing);
  });

  testWidgets('有資料時照常畫彙總', (t) async {
    await _pump(t, AppState());

    expect(find.textContaining('評分尚未接上後台'), findsNothing);
    expect(find.textContaining('延遲更新'), findsOneWidget);
  });
}
