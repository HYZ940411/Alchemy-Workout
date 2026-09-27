import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 使用者回報：「我的貼文數量不正確，如果我有刪除文章，該數量不會減少。
/// 目前未刪除 2 篇、刪除了 5 篇，貼文顯示 7 篇。」
///
/// 貼文是**軟刪除**（已刪除的仍留在清單裡，供獎勵回收與成就計數判定），
/// 而「我的」那個數字是自己數的：
/// `posts.where((p) => p.author == displayName).length` —— 漏了 `!p.deleted`。
///
/// 旁邊的 `postsBy()` 一直都有排除已刪除的 ——
/// **同一個決定寫在兩個地方，只有一處做對。**
void main() {
  Post post(String author, {String? uid, bool deleted = false}) => Post(
        id: 'p${DateTime.now().microsecondsSinceEpoch}${author.hashCode}$deleted',
        author: author,
        authorUid: uid,
        authorRank: 10,
        text: '內容',
        at: DateTime(2026, 9, 27),
        deleted: deleted,
      );

  test('已刪除的不算 —— 使用者回報的那個 2 : 5 : 7', () {
    final s = AppState()..displayName = '我';
    s.posts
      ..clear()
      ..addAll([
        for (var i = 0; i < 2; i++) post('我'),
        for (var i = 0; i < 5; i++) post('我', deleted: true),
      ]);
    expect(s.myPostCount, 2);
  });

  test('數字與清單長度一定相等 —— 兩者走同一支', () {
    final s = AppState()..displayName = '我';
    s.posts
      ..clear()
      ..addAll([
        post('我'),
        post('我', deleted: true),
        post('別人'),
      ]);
    expect(s.myPostCount, s.postsBy('我', uid: s.myUid).length);
  });

  test('別人的貼文不算進我的', () {
    final s = AppState()..displayName = '我';
    s.posts
      ..clear()
      ..addAll([post('我'), post('別人'), post('別人')]);
    expect(s.myPostCount, 1);
  });

  test('一篇都沒有就是 0', () {
    final s = AppState()..displayName = '我';
    s.posts.clear();
    expect(s.myPostCount, 0);
  });

  group('以 uid 為準，暱稱只是退路', () {
    test('改名之後舊貼文還算我的', () {
      final s = AppState()
        ..myUid = 'u1'
        ..displayName = '新暱稱';
      s.posts
        ..clear()
        ..addAll([post('舊暱稱', uid: 'u1'), post('舊暱稱', uid: 'u1')]);
      expect(s.myPostCount, 2);
    });

    test('撞名的人不算進我的', () {
      final s = AppState()
        ..myUid = 'u1'
        ..displayName = '阿昶';
      s.posts
        ..clear()
        ..addAll([post('阿昶', uid: 'u1'), post('阿昶', uid: 'u2')]);
      expect(s.myPostCount, 1);
    });

    test('沒有 uid 的示範資料退回比暱稱', () {
      final s = AppState()..displayName = '我';
      s.posts
        ..clear()
        ..addAll([post('我'), post('我')]);
      expect(s.myPostCount, 2);
    });
  });
}
