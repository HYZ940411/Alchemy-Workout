// 排行榜的入口（`[QA-02j]`）。
//
// 使用者回報「排行榜應該不只在設定中看到」。它原本只掛在「我的」選單的
// 第 11 項 —— 要先切到「我的」、往下捲過十個項目才找得到，等於沒有入口。
//
// 放在首頁而不是社群分頁：卡片上的**分數是本機算得出來的真值**，
// 需要後端的只有「名次」。所以在 `[BE-07]` 完成之前，這張卡仍然說得出
// 真話；而一個永遠是空狀態的社群分頁只會讓人以為壞了。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/screens/home_screen.dart';
import 'package:fitness_app/screens/leaderboard_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> _openHome(WidgetTester t, {AppState? state}) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final s = state ?? AppState();
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: Scaffold(body: HomeScreen())),
  ));
  await t.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('首頁看得到本週與本月分數', (t) async {
    await _openHome(
      t,
      state: AppState()
        ..weeklyScore = 1234
        ..monthlyScore = 5678,
    );

    await t.scrollUntilVisible(find.text('排行榜'), 200);
    await t.pumpAndSettle();
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('5678'), findsOneWidget);
  });

  testWidgets('點卡片進得了排行榜 —— 這才是這項的重點', (t) async {
    await _openHome(t);
    await t.scrollUntilVisible(find.text('排行榜'), 200);
    await t.pumpAndSettle();

    await t.tap(find.text('查看名次與本期獎勵'));
    await t.pumpAndSettle();

    expect(find.byType(LeaderboardScreen), findsOneWidget);
  });

  testWidgets('分數是真的 —— 不隨排行榜是否開放而消失', (t) async {
    // 接了後端時名次視窗是空的（`[QA-02e]`：不再捏造名次），
    // 但分數照樣累積、照樣顯示。這張卡不會因此變成一片空白。
    final s = AppState(demo: false)
      ..weeklyScore = 42
      ..monthlyScore = 99;
    await _openHome(t, state: s);

    await t.scrollUntilVisible(find.text('排行榜'), 200);
    await t.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(find.text('99'), findsOneWidget);
  });
}
