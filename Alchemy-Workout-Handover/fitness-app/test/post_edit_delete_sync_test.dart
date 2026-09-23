// 編輯與刪除要真的寫到雲端（2026-09-24）。
//
// 使用者問：「確定編輯跟刪除會成功讓別人看到對應的事件嗎？」——不會。
//
// `editPost` / `deletePost` / `editComment` / `deleteComment` 四支
// **只改記憶體然後 notifyListeners**，一行雲端寫入都沒有。於是：
// 編輯完重新整理變回舊內容、刪除完重新整理又跑回來、別人從頭到尾
// 看到的是原版。
//
// 最要命的是 `PostSource.updatePostText` 與 `markPostDeleted`
// **早就寫好了**，Firestore 實作完整、連測試都有 —— 就是沒有人呼叫。
// 介面備好了、實作備好了、接線漏了。留言那兩支則是連介面都沒有。
//
// 刪除與編輯的失敗處理刻意不同，見 `AppState.deletePost` 的註解。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/post_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 假的雲端：記下每一次寫入，可以被切成「寫不進去」。
class _FakePosts implements PostSource {
  final List<String> writes = [];
  bool offline = false;

  Future<void> _record(String what) async {
    writes.add(what);
    if (offline) throw StateError('離線');
  }

  @override
  Future<void> updatePostText(String postId, Post p) =>
      _record('updatePostText:$postId:${p.text}');

  @override
  Future<void> markPostDeleted(String postId) =>
      _record('markPostDeleted:$postId');

  @override
  Future<void> updateCommentText(String postId, Comment c) =>
      _record('updateCommentText:$postId:${c.id}:${c.text}');

  @override
  Future<void> markCommentDeleted(String postId, String commentId) =>
      _record('markCommentDeleted:$postId:$commentId');

  @override
  Future<void> publish(Post p, {required String authorUid}) =>
      _record('publish:${p.id}');
  @override
  Future<void> setLike(String postId, {required bool liked}) =>
      _record('setLike:$postId');
  @override
  Future<void> addComment(String postId, Comment c,
          {required String authorUid}) =>
      _record('addComment:$postId');
  @override
  Future<List<Post>> recent({int limit = 30}) async => const [];
}

/// 一個接好雲端的狀態，外加一篇我自己的貼文。
({AppState s, _FakePosts src, Post post}) _wired() {
  final src = _FakePosts();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..postSource = src;
  final post = Post(
    id: 'p1',
    author: s.displayName,
    authorUid: 'u-me',
    authorRank: 20,
    text: '原本的內容',
    at: DateTime(2026, 9, 20),
  );
  s.posts.add(post);
  return (s: s, src: src, post: post);
}

void main() {
  group('編輯貼文', () {
    test('會寫上雲端', () {
      final w = _wired();
      expect(w.s.editPost(w.post, '改過的內容'), isTrue);
      expect(w.src.writes, ['updatePostText:p1:改過的內容']);
    });

    test('沿用即發即忘：寫不進去也不把本機改回去', () async {
      final w = _wired();
      w.src.offline = true;
      expect(w.s.editPost(w.post, '改過的內容'), isTrue);
      await Future<void>.delayed(Duration.zero);
      // 內容還在，使用者可以再改一次 —— 與刪除的取捨不同。
      expect(w.post.text, '改過的內容');
    });

    test('沒接後端不會炸', () {
      final s = AppState(demo: false);
      final p = s.posts.isEmpty
          ? (Post(
              id: 'x',
              author: s.displayName,
              authorRank: 1,
              text: 'hi',
              at: DateTime(2026, 9, 20))
            ..text = 'hi')
          : s.posts.first;
      s.posts.add(p);
      expect(s.editPost(p, '改過'), isTrue);
    });
  });

  group('刪除貼文', () {
    test('會寫上雲端，回傳空值代表成功', () async {
      final w = _wired();
      expect(await w.s.deletePost(w.post), isNull);
      expect(w.src.writes, ['markPostDeleted:p1']);
      expect(w.post.deleted, isTrue);
    });

    test('寫不進去就把本機的刪除收回，並講出原因', () async {
      final w = _wired();
      w.src.offline = true;

      final msg = await w.s.deletePost(w.post);

      // **這是刪除與編輯的差別。** 靜靜地失敗的話，使用者以為刪掉了，
      // 實際上還在別人眼前 —— 那正是這次要修的困惑換個地方發生。
      expect(msg, isNotNull);
      expect(w.post.deleted, isFalse, reason: '貼文要重新出現');
      expect(w.s.visiblePosts.map((p) => p.id), contains('p1'));
    });

    test('沒接後端時算成功 —— 示範模式與既有測試走這條', () async {
      final s = AppState(demo: false);
      final p = Post(
          id: 'p9',
          author: s.displayName,
          authorRank: 1,
          text: 'hi',
          at: DateTime(2026, 9, 20));
      s.posts.add(p);
      expect(await s.deletePost(p), isNull);
      expect(p.deleted, isTrue);
    });

    test('別人的貼文刪不動', () async {
      final w = _wired();
      final his = Post(
          id: 'p2',
          author: '阿甲',
          authorUid: 'u-阿甲',
          authorRank: 5,
          text: '他的',
          at: DateTime(2026, 9, 20));
      w.s.posts.add(his);
      await w.s.deletePost(his);
      expect(his.deleted, isFalse);
      expect(w.src.writes, isEmpty);
    });
  });

  group('留言', () {
    test('編輯會寫上雲端，而且掛在正確的貼文底下', () {
      final w = _wired();
      final c = Comment(w.s.displayName, '原留言', DateTime(2026, 9, 21), id: 'c1');
      w.post.comments.add(c);

      expect(w.s.editComment(c, '改過的留言'), isTrue);
      // 留言不帶貼文 ID（雲端是子集合），父文件靠反查 —— 查錯就寫到別篇去。
      expect(w.src.writes, ['updateCommentText:p1:c1:改過的留言']);
    });

    test('刪除會寫上雲端', () async {
      final w = _wired();
      final c = Comment(w.s.displayName, '留言', DateTime(2026, 9, 21), id: 'c1');
      w.post.comments.add(c);

      expect(await w.s.deleteComment(c), isNull);
      expect(w.src.writes, ['markCommentDeleted:p1:c1']);
      expect(c.deleted, isTrue);
    });

    test('刪除寫不進去就收回', () async {
      final w = _wired();
      final c = Comment(w.s.displayName, '留言', DateTime(2026, 9, 21), id: 'c1');
      w.post.comments.add(c);
      w.src.offline = true;

      expect(await w.s.deleteComment(c), isNotNull);
      expect(c.deleted, isFalse);
      expect(w.post.visibleComments, contains(c));
    });
  });
}
