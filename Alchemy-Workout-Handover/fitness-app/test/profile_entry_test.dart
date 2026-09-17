// 看得到的人要點得進去（`[QA-02i]`）。
//
// 使用者回報「不能關注社群中看到的人」。查下去發現 ProfileScreen 一直
// 支援看別人 —— `viewing` 參數、關注按鈕、拜師按鈕全都寫好了 ——
// 但**整個 App 沒有任何一處導航到它**：`ProfileScreen(viewing: ...)`
// 在 lib/ 底下零個呼叫端。畫面做好了，路沒接上。
//
// 這種缺陷測試最容易漏掉：每一頁單獨看都是對的，壞的是頁與頁之間那條線。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/me/profile_screen.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 動態牆上有一篇別人的貼文。
///
/// 作者刻意用示範資料裡沒有的名字 —— 用「深蹲王」那種既有作者的話，
/// 畫面上會有好幾篇同一個人的貼文，`.first` 找到的是哪一篇就說不準了。
AppState _withPost(String author) {
  final s = AppState();
  s.posts.insert(
    0,
    Post(
      id: 'p-test',
      author: author,
      authorRank: 30,
      text: '今天練完了。',
      at: DateTime.now(),
    ),
  );
  s.following.remove(author);
  return s;
}

Future<void> _openFeed(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(
    state: s,
    child: const MaterialApp(home: Scaffold(body: FeedScreen())),
  ));
  await t.pumpAndSettle();
  // 動態牆預設在「關注」分頁，別人的貼文在「探索」。
  await t.tap(find.text('探索'));
  await t.pumpAndSettle();
}

void main() {
  group('從動態牆點進作者的檔案', () {
    testWidgets('點作者名字會開啟他的公開檔案', (t) async {
      final s = _withPost('測試對象');
      await _openFeed(t, s);

      await t.tap(find.text('測試對象').first);
      await t.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('進去之後關注得了 —— 這是整件事的重點', (t) async {
      final s = _withPost('測試對象');
      await _openFeed(t, s);
      await t.tap(find.text('測試對象').first);
      await t.pumpAndSettle();

      expect(s.following.contains('測試對象'), isFalse, reason: '前提：還沒關注');
      await t.tap(find.text('關注'));
      await t.pumpAndSettle();

      expect(s.following.contains('測試對象'), isTrue);
    });

    testWidgets('點到自己開的是自己那一頁，不給「關注自己」', (t) async {
      final s = AppState();
      s.posts.insert(
        0,
        Post(
          id: 'p-mine',
          author: s.displayName,
          authorRank: 45,
          text: '我自己發的。',
          at: DateTime.now(),
        ),
      );
      await _openFeed(t, s);

      await t.tap(find.text(s.displayName).first);
      await t.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('關注'), findsNothing);
    });
  });
}
