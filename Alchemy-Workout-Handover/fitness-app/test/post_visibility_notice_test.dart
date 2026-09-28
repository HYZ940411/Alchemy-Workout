// 貼文是公開的，這件事要在發文時講出來。
//
// 2026-09-26 移除了可見範圍選擇器（公開／僅關注者／私人），理由是**它
// 從來沒有生效過** —— `firestore.rules` 的貼文讀取是
// `allow read: if request.auth != null`，任何登入者都讀得到每一篇，
// 包括標「私人」的。那個選項一直在對使用者說一件不是真的事。
//
// 2026-09-28 使用者再次確認維持全部公開（選項 A）。但移除之後畫面上
// **什麼都沒說** —— 他從一個有三個選項的畫面，變成一個沒有選項的畫面，
// 而沒有任何地方告訴他結果是哪一種。**不給選擇可以，不告知不行。**

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/social/compose_post_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: ComposePostScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('發文頁告知貼文是公開的', (t) async {
    await open(t, AppState());
    expect(find.text('這篇貼文公開，任何人都看得到。'), findsOneWidget);
  });

  testWidgets('沒有可見範圍選擇器 —— 那個開關擋不住任何人', (t) async {
    await open(t, AppState());
    expect(find.text('僅關注者'), findsNothing);
    expect(find.text('私人'), findsNothing);
  });

  testWidgets('從這一頁發出來的貼文，真的是公開的', (t) async {
    // 不直接呼叫 publishPost —— 那樣測的是我在測試裡傳了什麼，
    // 不是畫面傳了什麼。要驗的正是「畫面說公開，送出去的也是公開」。
    final s = AppState();
    final before = s.postsBy(s.displayName, uid: s.myUid).length;
    await open(t, s);
    await t.enterText(find.byType(TextField).first, '今天練完了');
    await t.pumpAndSettle();
    await t.tap(find.text('發布'));
    await t.pumpAndSettle();

    final mine = s.postsBy(s.displayName, uid: s.myUid);
    expect(mine.length, before + 1, reason: '前提：這一步要真的發出去');
    expect(mine.first.visibility, PostVisibility.public);
  });
}
