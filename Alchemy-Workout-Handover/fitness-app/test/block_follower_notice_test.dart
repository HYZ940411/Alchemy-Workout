// 封鎖粉絲時要說清楚「解不掉的那一半」（使用者裁決 2026-09-28）。
//
// 規格：`Postcondition：封鎖自動解除雙方的關注關係`。
//
// **「他關注我」那一半刪不掉。** 關係文件是 `follows/{他的uid}_{我的uid}`，
// 而 `firestore.rules` 只讓 `followerId` 本人刪除 —— 我不是 followerId。
// 本機擋著（`applyFollows` 跳過封鎖清單裡的人，見 `follow_by_uid_test`），
// 但雲端那筆還在：**別人看我的檔案時，粉絲數仍會把他算進去。**
//
// 三個選項（改安全規則／升 Blaze 後端代刪／講清楚）裡使用者選了講清楚。
// 這個檔案釘的就是「有講」—— 而且只在真的會發生時才講。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/screens/social/feed_screen.dart';
import 'package:fitness_app/state/app_state.dart';

const _caveat = '仍會把他算進粉絲數';

Future<void> _pump(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(AppScope(
      state: s, child: const MaterialApp(home: Scaffold(body: FeedScreen()))));
  await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.more_horiz).first);
  await t.pumpAndSettle();
  await t.tap(find.textContaining('封鎖'));
  await t.pumpAndSettle();
}

/// 阿甲發了一篇文，而我關注他 —— 動態牆第一個分頁畫的就是關注的人。
///
/// **兩條測試唯一的差別是「他有沒有關注我」**，其餘一模一樣。
AppState _feedWithPeer() {
  final s = AppState(demo: false)..myUid = 'u-me';
  s.applyPublicProfiles(
      [PublicProfile(uid: 'u-甲', displayName: '阿甲', rank: 10)]);
  s.toggleFollow('阿甲', uid: 'u-甲');
  s.posts.add(Post(
    id: 'p1',
    author: '阿甲',
    authorUid: 'u-甲',
    authorRank: 10,
    text: '今天練腿',
    at: DateTime(2026, 9, 20),
  ));
  return s;
}

void main() {
  testWidgets('他是我的粉絲 → 確認視窗要說「別人仍會把他算進去」', (t) async {
    final s = _feedWithPeer();
    s.gainFollower('阿甲', uid: 'u-甲');
    expect(s.isFollower('阿甲', uid: 'u-甲'), isTrue, reason: '前提：他關注我');

    await _pump(t, s);

    expect(find.textContaining(_caveat), findsOneWidget);
  });

  testWidgets('他不是我的粉絲 → 不要講一件不會發生的事', (t) async {
    final s = _feedWithPeer();
    expect(s.isFollower('阿甲', uid: 'u-甲'), isFalse);

    await _pump(t, s);

    expect(find.textContaining('封鎖'), findsWidgets, reason: '前提：視窗有開');
    expect(find.textContaining(_caveat), findsNothing);
  });
}
