import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 「這是不是我的」一律以 **uid** 為準，暱稱只是沒有 uid 時的退路。
///
/// 使用者裁決：暱稱要能改（2026-09-26，選項 B ＝ 身分改用 uid）。
/// 這是第一階段 —— 把身分判斷收束成一個定義。
///
/// 在此之前 `isMyPost` 已經用 uid，而編輯貼文、編輯／刪除留言、
/// 以及「對自己的貼文互動不發獎勵」那五處還在只比暱稱。
/// **同一個問題兩種答案**：「⋯」選單開得出「編輯」，按下去卻沒反應。
void main() {
  Post post(String author, {String? uid}) => Post(
        id: 'p1',
        author: author,
        authorUid: uid,
        authorRank: 10,
        text: '內容',
        at: DateTime(2026, 9, 26),
      );

  group('貼文', () {
    test('uid 相同即是我的，即使暱稱不同（改名之後）', () {
      final s = AppState()
        ..myUid = 'u1'
        ..displayName = '新暱稱';
      final p = post('舊暱稱', uid: 'u1');
      expect(s.isMyPost(p), isTrue);
      expect(s.editPost(p, '改過了'), isTrue,
          reason: '選單開得出編輯，editPost 就必須答應 —— 兩者同一套判準');
    });

    test('uid 不同就不是我的，即使暱稱一樣（撞名）', () {
      final s = AppState()
        ..myUid = 'u1'
        ..displayName = '阿昶';
      final p = post('阿昶', uid: 'u2');
      expect(s.isMyPost(p), isFalse);
      expect(s.editPost(p, '改過了'), isFalse);
    });

    test('沒有 uid 時退回比暱稱 —— 示範資料的假作者沒有 uid', () {
      final s = AppState()..displayName = '阿昶';
      expect(s.isMyPost(post('阿昶')), isTrue);
      expect(s.isMyPost(post('別人')), isFalse);
    });

    test('對自己的貼文按讚不發經驗值 —— 判準也要看 uid', () {
      final s = AppState()
        ..myUid = 'u1'
        ..displayName = '新暱稱';
      final p = post('舊暱稱', uid: 'u1');
      s.posts.insert(0, p);
      final before = s.totalExp;
      s.toggleLike(p);
      expect(s.totalExp, before, reason: '改名之後自己的舊貼文仍是自己的，不該發獎勵');
    });
  });

  group('留言', () {
    test('留言帶著 uid —— 在此之前這個欄位根本不存在', () {
      final s = AppState()..myUid = 'u1';
      final p = post('別人', uid: 'u2');
      s.posts.insert(0, p);
      s.addComment(p, '推');
      expect(p.comments.last.authorUid, 'u1');
    });

    test('uid 相同即是我的留言，即使暱稱不同', () {
      final s = AppState()
        ..myUid = 'u1'
        ..displayName = '新暱稱';
      final p = post('別人', uid: 'u2');
      s.posts.insert(0, p);
      final c = Comment('舊暱稱', '推', DateTime(2026, 9, 26), authorUid: 'u1');
      p.comments.add(c);
      expect(s.isMyComment(c), isTrue);
      expect(s.editComment(c, '改過了'), isTrue);
    });

    test('別人的留言改不動，即使暱稱撞名', () {
      final s = AppState()
        ..myUid = 'u1'
        ..displayName = '阿昶';
      final p = post('別人', uid: 'u2');
      s.posts.insert(0, p);
      final c = Comment('阿昶', '推', DateTime(2026, 9, 26), authorUid: 'u2');
      p.comments.add(c);
      expect(s.isMyComment(c), isFalse);
      expect(s.editComment(c, '改過了'), isFalse);
    });
  });
}
