// 顯示名稱一律由 uid 查公開檔案（暱稱重構階段四，2026-09-28）。
//
// ## 為什麼
//
// 規格：「暱稱**為顯示名稱，不是識別碼**」（〈註冊流程〉），
// 且「暱稱可於設定頁事後更新」。
//
// 貼文、留言、對話、團隊名冊、收件匣、案件在雲端都各自存了一份
// **發生當下的名字**。那些值一旦對方改名就過期了 —— 而階級、教官聲望、
// 綜合等級早在 2026-09-23 就改成「一律顯示現值，存的那份只當墊底」。
// 這一階段把**名字本身**併進同一套（`AppState.nameOf`）。
//
// 做完之後改名會**回溯地**反映在舊貼文上 —— 那是 0s 階段表寫明的預期，
// 不是副作用：同一個人在全 App 只有一個名字，才不會出現「這是誰」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/chat_screen.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/screens/social/post_card.dart';
import 'package:fitness_app/state/app_state.dart';

PublicProfile _p(String uid, String name) =>
    PublicProfile(uid: uid, displayName: name, rank: 10);

Post _post({String author = '舊名字', String? uid = 'u-a'}) => Post(
      id: 'p1',
      author: author,
      authorUid: uid,
      authorRank: 10,
      text: '今天練腿',
      at: DateTime(2026, 9, 20),
      visibility: PostVisibility.public,
    );

Future<void> _pump(WidgetTester t, AppState s, Widget home) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
      AppScope(state: s, child: MaterialApp(home: Scaffold(body: home))));
  await t.pumpAndSettle();
}

void main() {
  group('nameOf：現在的名字優先', () {
    test('查得到公開檔案就用現值', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-a', '新名字')]);
      expect(s.nameOf('舊名字', uid: 'u-a'), '新名字');
    });

    test('查不到就用呼叫端手上那份 —— 不是空白也不是 uid', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      expect(s.nameOf('舊名字', uid: 'u-還沒讀到'), '舊名字');
    });

    test('沒有 uid 就原封不動 —— 那不是查詢失敗，是沒有東西可查', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-a', '新名字')]);
      expect(s.nameOf('示範使用者'), '示範使用者');
    });

    test('自己一律用自己現在的暱稱', () {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..displayName = '我改過名了';
      expect(s.nameOf('我的舊名字', uid: 'u-me'), '我改過名了');
    });
  });

  group('畫面上跟著改', () {
    testWidgets('貼文卡上的作者名字', (t) async {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-a', '新名字')]);

      await _pump(t, s, PostCard(post: _post()));

      expect(find.text('新名字'), findsOneWidget);
      expect(find.text('舊名字'), findsNothing,
          reason: '三個月前的貼文寫著他三個月前的名字 —— 那是「這是誰」');
    });

    testWidgets('貼文卡上的留言作者', (t) async {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-c', '留言者新名字')]);
      final p = _post()
        ..comments.add(Comment('留言者舊名字', '讚', DateTime(2026, 9, 21),
            authorUid: 'u-c'));

      await _pump(t, s, PostCard(post: p));

      // 留言那一行是 RichText（名字粗體、內文淡色），不是 Text。
      expect(find.textContaining('留言者新名字', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('留言者舊名字', findRichText: true), findsNothing);
    });

    testWidgets('對話清單上的對象名字', (t) async {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-b', '對方新名字')]);
      s.conversations.add(Conversation(
        id: 'c1',
        peer: '對方舊名字',
        peerUid: 'u-b',
        peerRank: 5,
        messages: [ChatMessage(false, '嗨', DateTime(2026, 9, 20))],
      ));

      await _pump(t, s, const ConversationsScreen());

      expect(find.text('對方新名字'), findsWidgets);
      expect(find.text('對方舊名字'), findsNothing);
    });

    testWidgets('動態牆「關注」分頁認得改名後的自己', (t) async {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..displayName = '我改過名了';
      s.posts.add(_post(author: '我的舊名字', uid: 'u-me'));

      await _pump(t, s, const FeedScreen());

      // 在此之前這裡是 `p.author == s.displayName` —— 改名之後
      // 自己的舊貼文不再被認成自己的，從關注分頁消失。
      expect(find.text('我改過名了'), findsWidgets);
    });
  });

  group('「這則是不是我的」不比暱稱', () {
    test('改名之後自己的舊留言還是自己的', () {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..displayName = '我改過名了';
      final c = Comment('我的舊名字', '讚', DateTime(2026, 9, 21),
          authorUid: 'u-me');
      expect(s.isMyComment(c), isTrue);
    });

    test('跟我撞名的人的留言不是我的', () {
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..displayName = '小明';
      final c =
          Comment('小明', '讚', DateTime(2026, 9, 21), authorUid: 'u-another');
      expect(s.isMyComment(c), isFalse,
          reason: '同名的兩個人 —— 「⋯」選單不該出現在別人的留言上');
    });
  });
}
