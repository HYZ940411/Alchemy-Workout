// 2026-09-28 使用者兩則要求：
//
// ① 「設定內的儲存可以拿掉，不用給使用者看到。」
//    接了帳號的人看到的是「進度會自動存到你的帳號…已存 41 次」——
//    前半是預期不是新聞，後半是**給我看的除錯數字**。
//    示範模式留著：那時候資料真的存在這台裝置上，清瀏覽器資料就會不見。
//
// ② 「師徒頁的『我要成為教官』按鈕希望跟團隊的『建立團隊』按鈕跟標題
//    方式長得一樣。」兩處是同一件事 —— 這一頁對還沒加入的人是空的，
//    空的時候要講得出「你可以做什麼」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  Future<void> open(WidgetTester t, AppState s, Widget page) async {
    await t.pumpWidget(AppScope(state: s, child: MaterialApp(home: page)));
    await t.pumpAndSettle();
  }

  /// 設定頁很長，`ListView` **沒畫到的不在樹上** —— 不捲就等於沒驗到。
  Future<void> scrollTo(WidgetTester t, Finder f) => t.scrollUntilVisible(
        f,
        300,
        scrollable: find.byType(Scrollable).first,
      );

  group('設定頁不再把「儲存」擺給使用者看', () {
    testWidgets('接了帳號時看不到', (t) async {
      final s = AppState(demo: false);
      expect(s.developerMode, isFalse, reason: '前提：不是開發者模式');
      await open(t, s, const SettingsScreen());
      // **捲到底再看。** 不捲的話「找不到」可能只是因為它在畫面外，
      // 那樣這條測試永遠會過，連功能被改回去都抓不到。
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await t.drag(list, const Offset(0, -400));
        await t.pumpAndSettle();
      }
      expect(find.text('儲存'), findsNothing);
      expect(find.textContaining('已存'), findsNothing);
    });

    testWidgets('示範模式仍要說 —— 那時候資料真的會不見', (t) async {
      final s = AppState();
      await open(t, s, const SettingsScreen());
      await scrollTo(t, find.text('儲存'));
      expect(find.text('儲存'), findsOneWidget);
      expect(find.textContaining('存到本機'), findsOneWidget);
    });

    testWidgets('開發者模式看得到', (t) async {
      final s = AppState(demo: false)..toggleDeveloperMode();
      await open(t, s, const SettingsScreen());
      await scrollTo(t, find.text('儲存'));
      expect(find.text('儲存'), findsOneWidget);
    });
  });

  // 使用者要驗「同一天練兩場，天數只加一」，而累積訓練天數畫面上原本
  // 根本沒有 —— 只有次數看得到，那一條就測不了。
  testWidgets('開發者模式的對帳區三個數字並排', (t) async {
    final s = AppState(demo: false)..toggleDeveloperMode();
    await open(t, s, const SettingsScreen());
    for (final label in ['累積訓練次數', '訓練歷史筆數', '累積訓練天數', '連續訓練天數']) {
      await scrollTo(t, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  group('師徒頁的入口與團隊頁同一張卡', () {
    testWidgets('有標題、說明與全寬按鈕', (t) async {
      final s = AppState();
      expect(s.isInstructor, isFalse, reason: '前提：還不是教官');
      await open(t, s, const MentorScreen());

      expect(find.text('你還不是教官'), findsOneWidget);
      expect(find.text('我要成為教官'), findsOneWidget);
      // 說明要講得出門檻與我現在的位置，不是一句空話。
      expect(
        find.textContaining('${s.instructorGate.requiredWorkouts} 次'),
        findsOneWidget,
      );
      expect(find.textContaining('你目前是階級 ${s.rank}'), findsOneWidget);
      // 與團隊頁一樣：卡片（Panel）包起來，不是光禿禿一顆鍵。
      expect(
        find.ancestor(of: find.text('你還不是教官'), matching: find.byType(Panel)),
        findsOneWidget,
      );
    });
  });
}
