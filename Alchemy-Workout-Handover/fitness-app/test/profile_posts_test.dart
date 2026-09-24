// 個人檔案頁的公開貼文（2026-09-24）。
//
// 使用者回報：「使用者頁面的公開貼文顯示不完整，少了更早發布的文章，
// 只有最新的兩篇。文章可否改為像是動態那樣。有按讚留言檢舉等功能。」
//
// 在此之前這一段是檔案頁自己畫的：兩行純文字、`take(2)`、沒有按讚留言
// 檢舉，也點不進貼文詳情。
//
// **修法不是把 `take(2)` 拿掉再補幾顆按鈕上去。** 那會做出第二張慢慢
// 長歪的卡片，而這個專案的 bug 有一整排正是「同一個決定寫在兩個地方，
// 只有一處做對」—— 貼文選單漏了分支（自己的貼文看到檢舉）、條款閘門
// 只加在兩條進入路徑的其中一條。
//
// 所以動態牆那張 `_PostCard` 被抽成共用的 `PostCard`，兩邊用同一張。
// 這個檔案釘的就是「兩邊真的是同一張」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/me/profile_screen.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/screens/social/post_card.dart';
import 'package:fitness_app/state/app_state.dart';

Post _post(String text, {required String author, required int daysAgo}) => Post(
      id: 'p-$text',
      author: author,
      authorRank: 1,
      text: text,
      at: DateTime(2026, 9, 24).subtract(Duration(days: daysAgo)),
      visibility: PostVisibility.public,
    );

/// 一位有五篇公開貼文的人。
AppState _withPosts({String author = '小明'}) {
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..displayName = '我';
  s.posts.addAll([
    for (var i = 0; i < 5; i++)
      _post('第 ${i + 1} 篇', author: author, daysAgo: i),
  ]);
  return s;
}

Future<void> _pump(WidgetTester t, AppState s, Widget home) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 6);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(state: s, child: MaterialApp(home: home)));
  await t.pumpAndSettle();
}

void main() {
  group('postsBy', () {
    test('由新到舊 —— 順序不對的話「最新兩篇」拿到的是別的兩篇', () {
      final s = _withPosts();
      final got = s.postsBy('小明').map((p) => p.text).toList();
      expect(got, ['第 1 篇', '第 2 篇', '第 3 篇', '第 4 篇', '第 5 篇']);
    });

    test('不倚賴 posts 本身的順序 —— 本機新發的是直接插進去的', () {
      final s = _withPosts();
      s.posts.add(_post('最新的', author: '小明', daysAgo: -1));
      expect(s.postsBy('小明').first.text, '最新的');
    });

    test('別人的不公開貼文不列', () {
      final s = _withPosts();
      s.posts.add(Post(
        id: 'secret',
        author: '小明',
        authorRank: 1,
        text: '只給自己看',
        at: DateTime(2026, 9, 24),
        visibility: PostVisibility.private,
      ));
      expect(s.postsBy('小明').map((p) => p.text), isNot(contains('只給自己看')));
    });
  });

  group('檔案頁列出全部，不截斷', () {
    testWidgets('五篇就列五篇 —— 不是只有最新的兩篇', (t) async {
      final s = _withPosts();
      await _pump(t, s, const ProfileScreen(viewing: '小明'));

      // 在此之前是 `myPosts.take(2)`：第 3–5 篇從來沒被畫出來，
      // 而畫面上沒有任何跡象顯示「還有更多」。
      for (var i = 1; i <= 5; i++) {
        expect(find.text('第 $i 篇'), findsOneWidget, reason: '第 $i 篇不見了');
      }
    });

    testWidgets('標題寫出總篇數 —— 截不截斷都說得清楚', (t) async {
      final s = _withPosts();
      await _pump(t, s, const ProfileScreen(viewing: '小明'));
      expect(find.text('5 篇'), findsOneWidget);
    });

    testWidgets('沒有貼文時不說篇數，只說沒有', (t) async {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..displayName = '我';
      await _pump(t, s, const ProfileScreen(viewing: '小明'));
      expect(find.text('小明 沒有公開的貼文。'), findsOneWidget);
    });
  });

  group('檔案頁與動態牆用同一張卡', () {
    testWidgets('檔案頁畫的是 PostCard', (t) async {
      final s = _withPosts();
      await _pump(t, s, const ProfileScreen(viewing: '小明'));
      expect(find.byType(PostCard), findsNWidgets(5));
    });

    testWidgets('動態牆畫的也是 PostCard —— 兩邊同一個型別才不會長歪', (t) async {
      final s = _withPosts();
      s.following.add('小明');
      await _pump(t, s, const FeedScreen());
      expect(find.byType(PostCard), findsWidgets);
    });

    testWidgets('檔案頁上按得到讚', (t) async {
      final s = _withPosts();
      await _pump(t, s, const ProfileScreen(viewing: '小明'));
      final p = s.postsBy('小明').first;
      expect(p.likedByMe, isFalse, reason: '前提：還沒按過');

      await t.tap(find.byIcon(Icons.favorite_border).first);
      await t.pumpAndSettle();

      expect(p.likedByMe, isTrue);
    });

    testWidgets('檔案頁上留得了言', (t) async {
      final s = _withPosts();
      await _pump(t, s, const ProfileScreen(viewing: '小明'));
      final p = s.postsBy('小明').first;

      await t.enterText(find.byType(TextField).first, '練得不錯');
      await t.tap(find.byIcon(Icons.send_rounded).first);
      await t.pumpAndSettle();

      expect(p.comments.where((c) => !c.deleted).map((c) => c.text),
          contains('練得不錯'));
    });

    testWidgets('檔案頁上開得了那顆「⋯」—— 別人的貼文是檢舉', (t) async {
      final s = _withPosts();
      await _pump(t, s, const ProfileScreen(viewing: '小明'));

      await t.tap(find.byIcon(Icons.more_horiz).first);
      await t.pumpAndSettle();

      expect(find.text('檢舉這篇貼文'), findsOneWidget);
      expect(find.text('封鎖這個人'), findsOneWidget);
      expect(find.text('刪除貼文'), findsNothing);
    });

    testWidgets('自己的檔案頁上那顆「⋯」是編輯與刪除，不是檢舉', (t) async {
      final s = _withPosts(author: '我');
      await _pump(t, s, const ProfileScreen());

      await t.tap(find.byIcon(Icons.more_horiz).first);
      await t.pumpAndSettle();

      // 這正是 2026-09-23 修過的那個分支。共用同一張卡，
      // 它在檔案頁上也必須是對的 —— 這就是不另寫一張的理由。
      expect(find.text('編輯貼文'), findsOneWidget);
      expect(find.text('刪除貼文'), findsOneWidget);
      expect(find.text('檢舉這篇貼文'), findsNothing);
    });
  });
}
