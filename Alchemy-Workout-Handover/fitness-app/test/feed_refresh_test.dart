// 別人發的貼文要看得到（`[QA-01]` 第 6 項的前半）。
//
// 使用者回報「社群動態：A 發文了 B 好像沒看到，假文章尚未移除」。
// 假文章那一半 2026-09-16 隨 `[QA-02a]` 修掉了，**前半漏到 9-18 才補**。
//
// 根因：`applyCloudPosts` 只在登入那一刻被呼叫一次（`AuthGate._syncProfile`），
// 而 `lib/data/` 底下沒有任何 `.snapshots()` 即時訂閱。所以 B 已經登入著、
// A 這時發文，B 要把 App 完全重新載入才看得到。
//
// 這裡補的是**下拉重新整理**，不是即時訂閱 —— 真正的即時要動整個讀取層，
// 留給 `[BE-07]` 那批（見 PROGRESS.md 第 5 節）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/post_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 假的雲端：內容可以在測試中途被換掉，模擬「A 在這期間發了文」。
class _FakePosts implements PostSource {
  List<Post> cloud;
  int reads = 0;
  bool throwOnRead = false;
  _FakePosts(this.cloud);

  @override
  Future<List<Post>> recent({int limit = 30}) async {
    reads++;
    if (throwOnRead) throw StateError('離線');
    return cloud.take(limit).toList();
  }

  @override
  Future<void> publish(Post p, {required String authorUid}) async {}
  @override
  Future<void> setLike(String postId, {required bool liked}) async {}
  @override
  Future<void> addComment(String postId, Comment c,
      {required String authorUid}) async {}
  @override
  Future<void> updatePostText(String postId, Post p) async {}
  @override
  Future<void> markPostDeleted(String postId) async {}
}

Post _post(String id, String author) => Post(
      id: id,
      author: author,
      authorRank: 30,
      text: '$author 的第 $id 篇',
      at: DateTime(2026, 9, 18, int.parse(id)),
    );

void main() {
  group('refreshCloudPosts', () {
    test('沒接後端就什麼都不做，回傳 false', () async {
      // 既有測試全部走這條 —— 行為與加這個方法之前完全一樣。
      expect(await AppState().refreshCloudPosts(), isFalse);
    });

    test('重新讀得到 A 在這期間發的文', () async {
      final src = _FakePosts([_post('1', '阿昶')]);
      final s = AppState(demo: false)..postSource = src;

      await s.refreshCloudPosts();
      expect(s.posts.map((p) => p.id), ['1']);

      // A 這時發了一篇。
      src.cloud = [_post('1', '阿昶'), _post('2', '小美')];
      await s.refreshCloudPosts();
      expect(s.posts.map((p) => p.id).toSet(), {'1', '2'});
    });

    test('重複下拉不會把同一篇疊成兩篇', () async {
      final src = _FakePosts([_post('1', '阿昶')]);
      final s = AppState(demo: false)..postSource = src;
      await s.refreshCloudPosts();
      await s.refreshCloudPosts();
      await s.refreshCloudPosts();
      expect(s.posts, hasLength(1));
      expect(src.reads, 3);
    });

    test('讀失敗不把動態牆清空', () async {
      // 下拉失敗最糟的結果是「畫面上原本有的貼文消失了」——
      // 使用者會以為資料壞了。維持現狀比清空安全。
      final src = _FakePosts([_post('1', '阿昶')]);
      final s = AppState(demo: false)..postSource = src;
      await s.refreshCloudPosts();

      src.throwOnRead = true;
      expect(await s.refreshCloudPosts(), isFalse);
      expect(s.posts, hasLength(1));
    });
  });

  group('動態牆的下拉手勢', () {
    Future<void> open(WidgetTester t, AppState s) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: FeedScreen())),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('沒接後端時不掛下拉 —— 下拉了什麼都不會變的手勢更糟', (t) async {
      await open(t, AppState());
      expect(find.byType(RefreshIndicator), findsNothing);
    });

    testWidgets('接了後端就掛上', (t) async {
      final s = AppState(demo: false)..postSource = _FakePosts([]);
      await open(t, s);
      expect(find.byType(RefreshIndicator), findsWidgets);
    });

    testWidgets('空的時候也下拉得動 —— 「還沒有貼文」與「還沒讀到」長得一樣', (t) async {
      final src = _FakePosts([_post('1', '小美')]);
      final s = AppState(demo: false)..postSource = src;
      await open(t, s);
      expect(find.text('這裡還沒有貼文'), findsWidgets);

      await t.fling(find.text('這裡還沒有貼文').first, const Offset(0, 320), 1000);
      await t.pumpAndSettle();

      expect(src.reads, greaterThan(0), reason: '下拉要真的去讀雲端');
      expect(s.posts.map((p) => p.id), contains('1'));
    });
  });

  group('自訂訓練也不再留別人的假課表（[QA-02e] 補漏）', () {
    test('接了後端就是空的', () {
      expect(AppState(demo: false).customPlans, isEmpty);
    });

    test('示範模式照樣有', () {
      expect(AppState().customPlans, isNotEmpty);
    });

    test('課表選擇頁不再出現別人的示範課表', () {
      // resetToNewAccount 刻意只清「我的」，所以 3 份 isMine: false 的
      // 假課表原本會經「全平台已公開」那一類出現在課表選擇頁。
      final s = AppState(demo: false);
      expect(s.selectableCustomPlans, isEmpty);
    });
  });
}
