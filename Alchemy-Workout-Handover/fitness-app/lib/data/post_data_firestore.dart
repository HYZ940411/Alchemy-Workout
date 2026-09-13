import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/community.dart';
import 'post_data.dart';

/// Firestore 上的貼文（[BE-11] 批次 3）。
///
/// ```
/// posts/{postId}                 貼文本體，likeCount 為顯示用計數
/// posts/{postId}/comments/{id}   留言
/// posts/{postId}/likes/{uid}     誰按過讚（存在即已按），一人一次由主鍵保證
/// ```
class FirestorePosts implements PostSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestorePosts({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('posts');

  // ===========================================================================
  // 寫入
  // ===========================================================================

  @override
  Future<void> publish(Post p, {required String authorUid}) async {
    await _col.doc(p.id).set({
      'authorUid': authorUid,
      // 暱稱一併存一份：動態牆每篇都去查一次作者的公開檔案的話，
      // 一頁 20 篇就是 20 次額外查詢。作者事後改暱稱時舊貼文仍顯示當時的
      // 名字 —— 那與〈訓練紀錄〉凍結歷史值是同一個取捨。
      'authorName': p.author,
      'authorRank': p.authorRank,
      if (p.authorReputation != null) 'authorReputation': p.authorReputation,
      'text': p.text,
      'images': p.images,
      'at': Timestamp.fromDate(p.at),
      if (p.attachedWorkout != null) 'attachedWorkout': p.attachedWorkout,
      'visibility': p.visibility.name,
      'pendingReview': p.pendingReview,
      'deleted': false,
      'likeCount': 0,
      'edits': const [],
    });
  }

  @override
  Future<void> setLike(String postId, {required bool liked}) async {
    final post = _col.doc(postId);
    final like = post.collection('likes').doc(uid);

    // 同一批寫入：按讚紀錄與計數要嘛一起成立、要嘛一起不成立。
    // 分開寫的話中途失敗會留下「有紀錄但沒計數」或反之。
    final batch = _db.batch();
    if (liked) {
      batch.set(like, {'at': FieldValue.serverTimestamp()});
    } else {
      batch.delete(like);
    }
    batch.update(post, {'likeCount': FieldValue.increment(liked ? 1 : -1)});
    await batch.commit();
  }

  @override
  Future<void> addComment(String postId, Comment c,
      {required String authorUid}) async {
    await _col.doc(postId).collection('comments').doc(c.id).set({
      'authorUid': authorUid,
      'authorName': c.author,
      'text': c.text,
      'at': Timestamp.fromDate(c.at),
      'deleted': false,
      'edits': const [],
    });
  }

  @override
  Future<void> updatePostText(String postId, Post p) async {
    await _col.doc(postId).update({
      'text': p.text,
      'edits': [
        for (final e in p.edits)
          {'before': e.$1, 'at': Timestamp.fromDate(e.$2)},
      ],
    });
  }

  @override
  Future<void> markPostDeleted(String postId) async {
    await _col.doc(postId).update({'deleted': true});
  }

  // ===========================================================================
  // 讀取
  // ===========================================================================

  @override
  Future<List<Post>> recent({int limit = 30}) async {
    final snap = await _col.orderBy('at', descending: true).limit(limit).get();

    final posts = <Post>[];
    for (final d in snap.docs) {
      final p = _postOf(d.id, d.data());
      if (p != null) posts.add(p);
    }

    // 留言與「我按過讚沒有」各自平行查，不要一篇一篇等。
    await Future.wait([
      for (final p in posts) _fillComments(p),
      for (final p in posts) _fillLiked(p),
    ]);
    return posts;
  }

  Future<void> _fillComments(Post p) async {
    final snap =
        await _col.doc(p.id).collection('comments').orderBy('at').get();
    for (final d in snap.docs) {
      final c = _commentOf(d.id, d.data());
      if (c != null) p.comments.add(c);
    }
  }

  /// 「我按過讚沒有」是**每位讀者各自不同**的狀態，不能存在貼文上。
  ///
  /// 一篇一次查詢。30 篇就是 30 次讀取 —— 在免費額度（每日 5 萬次）裡
  /// 綽綽有餘。要再省的話得改用 collection group 查詢一次撈完自己的所有讚，
  /// 但那需要額外建索引，等真的有量再說。
  Future<void> _fillLiked(Post p) async {
    final d = await _col.doc(p.id).collection('likes').doc(uid).get();
    p.likedByMe = d.exists;
  }

  Post? _postOf(String id, Map<String, dynamic> j) {
    final author = j['authorName'];
    final at = j['at'];
    // 認不出作者或時間的文件直接略過，不讓一筆壞資料把整個動態牆弄掉。
    if (author is! String || at is! Timestamp) return null;

    return Post(
      id: id,
      author: author,
      authorRank: j['authorRank'] is num ? (j['authorRank'] as num).round() : 1,
      authorReputation: j['authorReputation'] is num
          ? (j['authorReputation'] as num).round()
          : null,
      text: j['text'] is String ? j['text'] as String : '',
      at: at.toDate(),
      images: [
        for (final i in (j['images'] as List? ?? const []))
          if (i is String) i,
      ],
      attachedWorkout:
          j['attachedWorkout'] is String ? j['attachedWorkout'] as String : null,
      visibility: PostVisibility.values.firstWhere(
        (v) => v.name == j['visibility'],
        orElse: () => PostVisibility.public,
      ),
      pendingReview: j['pendingReview'] == true,
      likes: j['likeCount'] is num ? (j['likeCount'] as num).round() : 0,
      deleted: j['deleted'] == true,
      edits: _editsOf(j['edits']),
    );
  }

  Comment? _commentOf(String id, Map<String, dynamic> j) {
    final author = j['authorName'];
    final at = j['at'];
    if (author is! String || at is! Timestamp) return null;

    return Comment(
      author,
      j['text'] is String ? j['text'] as String : '',
      at.toDate(),
      id: id,
      deleted: j['deleted'] == true,
      edits: _editsOf(j['edits']),
    );
  }

  List<(String, DateTime)> _editsOf(Object? raw) => [
        for (final e in (raw as List? ?? const []))
          if (e is Map && e['before'] is String && e['at'] is Timestamp)
            (e['before'] as String, (e['at'] as Timestamp).toDate()),
      ];
}
