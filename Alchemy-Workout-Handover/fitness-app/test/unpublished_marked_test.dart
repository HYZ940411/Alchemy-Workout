// 未公開的資料在自己的畫面上：**顯示 ＋ 標示**，不是藏起來
//（2026-09-28 使用者裁決 A）。
//
// 在此之前兩個畫面做法不一樣：
//   「我的」分頁  —— 把「綜合 X」整顆藏起來（註解：免得誤以為別人看得到）
//   「我的檔案」  —— 完整顯示，卻沒有任何標示
// 同一件事兩種處理，而且都不對。
//
// 藏起來是錯的方向：那是我自己的檔案，我當然該看得到我自己的能力值。
// **用「資訊消失」來表達「未公開」，使用者只會以為壞了** ——
// 使用者實測時就是這樣，他關掉開關後找不到那顆標籤，問「我要去哪裡找」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/me/profile_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  Future<void> open(WidgetTester t, AppState s, Widget page) async {
    // 這兩頁在真的 App 裡是掛在分頁殼底下的，外面有 Scaffold 與
    // 一個有界的寬度。直接 pump 進 MaterialApp 會讓 Row 拿到無限寬。
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(AppScope(
      state: s,
      child: MaterialApp(home: Scaffold(body: page)),
    ));
    await t.pumpAndSettle();
  }

  group('「我的」分頁頁首', () {
    testWidgets('公開時只有等級，沒有多餘的標示', (t) async {
      final s = AppState()..setFlag(overall: true);
      await open(t, s, const MoreScreen());
      expect(find.textContaining('綜合 '), findsOneWidget);
      expect(find.text('未公開'), findsNothing);
    });

    testWidgets('不公開時**仍然看得到**，旁邊標「未公開」', (t) async {
      final s = AppState()..setFlag(overall: false);
      await open(t, s, const MoreScreen());
      expect(find.textContaining('綜合 '), findsOneWidget,
          reason: '那是我自己的資料，藏起來只會讓人以為壞了');
      expect(find.text('未公開'), findsOneWidget);
    });
  });

  group('「我的檔案」', () {
    testWidgets('兩個都公開時不掛任何提示', (t) async {
      final s = AppState()
        ..setFlag(ability: true)
        ..setFlag(overall: true);
      await open(t, s, const ProfileScreen());
      expect(find.text('部分未公開'), findsNothing);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    });

    testWidgets('關掉六維：照常顯示，並說明只有自己看得到', (t) async {
      final s = AppState()
        ..setFlag(ability: false)
        ..setFlag(overall: true);
      await open(t, s, const ProfileScreen());
      expect(find.text('部分未公開'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.textContaining('別人只看得到綜合能力等級'), findsOneWidget);
    });

    testWidgets('兩個都關：說清楚整區別人都看不到', (t) async {
      final s = AppState()
        ..setFlag(ability: false)
        ..setFlag(overall: false);
      await open(t, s, const ProfileScreen());
      expect(find.textContaining('不呈現這一區'), findsOneWidget);
    });

    testWidgets('只關綜合：也要說', (t) async {
      final s = AppState()
        ..setFlag(ability: true)
        ..setFlag(overall: false);
      await open(t, s, const ProfileScreen());
      expect(find.textContaining('綜合能力等級只有你看得到'), findsOneWidget);
    });
  });
}
