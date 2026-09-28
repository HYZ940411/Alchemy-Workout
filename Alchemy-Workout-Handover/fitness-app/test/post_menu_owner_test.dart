// 自己的貼文不該看到「檢舉」（2026-09-23）。
//
// 使用者回報：「點擊自己發出的貼文右邊三個點 icon 時，不應該看到檢舉，
// 而是編輯或刪除。」
//
// 根因是同一個判斷寫在兩個地方，只有一處做對：貼文詳情頁分支正確
// （`mine ? _mineMenu : _more`），**動態牆那張卡片根本沒有分支** ——
// `IconButton` 直接開 `showReportSheet`。漏掉的那一處不會報錯，
// 只會安靜地做錯事。
//
// 所以修法不是「在動態牆補一個 if」，那只是把同一個決定寫成第二份、
// 等下一個畫面再漏一次。判斷與兩組選單都收斂到 `showPostMenu`，
// 這個檔案釘的是「兩個入口的行為一致」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/screens/social/post_detail_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

Future<void> _pump(WidgetTester t, AppState s, Widget home) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(state: s, child: MaterialApp(home: home)));
  await t.pumpAndSettle();
}

/// 動態牆上那顆「⋯」。詳情頁那顆是 `more_vert`，兩顆刻意不同圖示。
Future<void> _tapFeedMenu(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.more_horiz).first);
  await t.pumpAndSettle();
}

Future<void> _tapDetailMenu(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.more_vert).first);
  await t.pumpAndSettle();
}

Post _post({required String author, String? uid}) => Post(
      id: 'p1',
      author: author,
      authorUid: uid,
      authorRank: 20,
      text: '今天練腿',
      at: DateTime(2026, 9, 20),
    );

/// 一個接好雲端身分的狀態：我是 `u-me`。
AppState _me() => AppState(demo: false)..myUid = 'u-me';

void main() {
  group('動態牆的「⋯」', () {
    testWidgets('自己的貼文：編輯與刪除，沒有檢舉', (t) async {
      final s = _me();
      s.posts.add(_post(author: s.displayName, uid: 'u-me'));
      await _pump(t, s, const Scaffold(body: FeedScreen()));

      await _tapFeedMenu(t);

      expect(find.text('編輯貼文'), findsOneWidget);
      expect(find.text('刪除貼文'), findsOneWidget);
      // 這就是使用者回報的那一幕 —— 在此之前這裡是「檢舉這篇貼文」。
      expect(find.text('檢舉這篇貼文'), findsNothing);
      expect(find.textContaining('封鎖'), findsNothing,
          reason: '沒有「封鎖自己」這種東西');
    });

    testWidgets('別人的貼文：檢舉與封鎖，沒有編輯', (t) async {
      final s = _me();
      s.following.add(s.personKeyOf('阿甲', 'u-阿甲'));
      s.posts.add(_post(author: '阿甲', uid: 'u-阿甲'));
      await _pump(t, s, const Scaffold(body: FeedScreen()));

      await _tapFeedMenu(t);

      expect(find.text('檢舉這篇貼文'), findsOneWidget);
      expect(find.text('封鎖這個人'), findsOneWidget);
      expect(find.text('編輯貼文'), findsNothing);
      expect(find.text('刪除貼文'), findsNothing);
    });
  });

  group('貼文詳情頁的「⋯」', () {
    testWidgets('自己的貼文：編輯與刪除', (t) async {
      final s = _me();
      final p = _post(author: s.displayName, uid: 'u-me');
      s.posts.add(p);
      await _pump(t, s, PostDetailScreen(post: p));

      await _tapDetailMenu(t);

      expect(find.text('編輯貼文'), findsOneWidget);
      expect(find.text('檢舉這篇貼文'), findsNothing);
    });

    testWidgets('別人的貼文：檢舉與封鎖', (t) async {
      final s = _me();
      final p = _post(author: '阿甲', uid: 'u-阿甲');
      s.posts.add(p);
      await _pump(t, s, PostDetailScreen(post: p));

      await _tapDetailMenu(t);

      expect(find.text('檢舉這篇貼文'), findsOneWidget);
      expect(find.text('編輯貼文'), findsNothing);
    });
  });

  group('選單只列動作，不寫補充說明', () {
    testWidgets('自己的貼文', (t) async {
      final s = _me();
      s.posts.add(_post(author: s.displayName, uid: 'u-me'));
      await _pump(t, s, const Scaffold(body: FeedScreen()));
      await _tapFeedMenu(t);

      expect(find.text('編輯貼文'), findsOneWidget);
      // 使用者要求移除 —— 那幾句在按鈕底下反而讓人猶豫。
      expect(find.textContaining('編輯前的內容會留在編輯歷史'), findsNothing);
      expect(find.textContaining('按讚與留言一併隱藏'), findsNothing);
    });

    testWidgets('別人的貼文', (t) async {
      final s = _me();
      s.following.add(s.personKeyOf('阿甲', 'u-阿甲'));
      s.posts.add(_post(author: '阿甲', uid: 'u-阿甲'));
      await _pump(t, s, const Scaffold(body: FeedScreen()));
      await _tapFeedMenu(t);

      expect(find.text('檢舉這篇貼文'), findsOneWidget);
      expect(find.textContaining('檢舉不會觸發任何自動處置'), findsNothing);
      expect(find.textContaining('封鎖後對方看不到你的貼文'), findsNothing);
    });
  });

  group('封鎖要先確認，不是點一下就生效', () {
    testWidgets('跳出確認對話框，取消就不封鎖', (t) async {
      final s = _me();
      s.following.add(s.personKeyOf('阿甲', 'u-阿甲'));
      s.posts.add(_post(author: '阿甲', uid: 'u-阿甲'));
      await _pump(t, s, const Scaffold(body: FeedScreen()));
      await _tapFeedMenu(t);

      await t.tap(find.text('封鎖這個人'));
      await t.pumpAndSettle();

      // 封鎖是破壞性的，而且會連帶解除雙方關注與師徒關係，
      // **解除封鎖不會恢復** —— 按錯一次就回不去了。
      expect(find.textContaining('封鎖 阿甲？'), findsOneWidget);
      expect(find.textContaining('雙方的關注會一併解除'), findsOneWidget);
      expect(find.textContaining('解除封鎖不會把這些恢復'), findsOneWidget);
      // 對話框不渲染 markdown —— 星號會直接印出來。
      expect(find.textContaining('**'), findsNothing);
      expect(s.isBlocked('阿甲'), isFalse, reason: '還沒確認就不該生效');

      // **按「取消」之後也不該封鎖。** 只驗「對話框跳出來了」是不夠的 ——
      // 把 `if (ok != true) return;` 那行拔掉，對話框照樣會跳，
      // 封鎖也照樣會發生，而測試不會紅。
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(s.isBlocked('阿甲'), isFalse, reason: '取消了就不該封鎖');
      expect(s.isFollowing('阿甲', uid: 'u-阿甲'), isTrue,
          reason: '關注也不該被解除');
    });

    testWidgets('確認之後才真的封鎖', (t) async {
      final s = _me();
      s.following.add(s.personKeyOf('阿甲', 'u-阿甲'));
      s.posts.add(_post(author: '阿甲', uid: 'u-阿甲'));
      await _pump(t, s, const Scaffold(body: FeedScreen()));
      await _tapFeedMenu(t);

      await t.tap(find.text('封鎖這個人'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(AppButton, '封鎖').last);
      await t.pumpAndSettle();

      expect(s.isBlocked('阿甲'), isTrue);
      expect(s.following.contains('阿甲'), isFalse, reason: '關注一併解除');
    });
  });

  group('是不是我的貼文，以 uid 為準', () {
    test('uid 相同就是我的，不管暱稱寫什麼', () {
      final s = _me();
      // 日後開放改暱稱時，我的舊貼文帶的是舊名字。
      expect(s.isMyPost(_post(author: '我的舊名字', uid: 'u-me')), isTrue);
    });

    test('uid 不同就不是我的，就算暱稱撞名', () {
      final s = _me();
      expect(s.isMyPost(_post(author: s.displayName, uid: 'u-別人')), isFalse);
    });

    test('沒有 uid 時退回比暱稱（示範資料走這條）', () {
      final s = AppState(demo: false);
      expect(s.isMyPost(_post(author: s.displayName)), isTrue);
      expect(s.isMyPost(_post(author: '阿甲')), isFalse);
    });
  });

  group('從動態牆刪貼文不該把動態牆關掉', () {
    testWidgets('刪完停在原地，貼文消失', (t) async {
      final s = _me();
      s.posts.add(_post(author: s.displayName, uid: 'u-me'));
      await _pump(t, s, const Scaffold(body: FeedScreen()));

      await _tapFeedMenu(t);
      await t.tap(find.text('刪除貼文'));
      await t.pumpAndSettle();
      await t.tap(find.text('刪除'));
      await t.pumpAndSettle();

      // 詳情頁刪完要把自己關掉（貼文都沒了），動態牆不必 ——
      // 把那個 pop 寫死在選單裡的話，這裡會整頁被關掉。
      expect(find.byType(FeedScreen), findsOneWidget);
      expect(s.visiblePosts.where((p) => p.id == 'p1'), isEmpty);
    });
  });
}
