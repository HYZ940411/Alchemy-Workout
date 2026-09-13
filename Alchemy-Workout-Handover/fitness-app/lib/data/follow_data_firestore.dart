import 'package:cloud_firestore/cloud_firestore.dart';

import 'follow_data.dart';

/// Firestore 上的關注關係（[BE-11] 批次 2）。
///
/// ```
/// follows/{followerUid}_{followeeUid}
///   followerId, followeeId, at
/// ```
///
/// **文件 ID 是兩個 uid 合成的**，不是自動 ID。這樣「同一組關係只能有一筆」
/// 由 Firestore 的主鍵直接保證，不必額外查一次有沒有重複 ——
/// 重複關注在這個結構下是寫不出來的，不是「靠程式碼記得檢查」。
/// 見 `Firestore-Schema設計.md` 第 2.9 節。
///
/// 兩個方向都是單欄位查詢（`followerId ==` 與 `followeeId ==`），
/// Firestore 自動建索引，不需要複合索引。
class FirestoreFollows implements FollowSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestoreFollows({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('follows');

  /// 關係的文件 ID。順序有意義：前者關注後者。
  String _edgeId(String follower, String followee) => '${follower}_$followee';

  @override
  Future<void> follow(String targetUid) async {
    // 自己關注自己在模型上沒有意義，擋在這裡而不是靠呼叫端記得檢查。
    if (targetUid == uid) return;
    await _col.doc(_edgeId(uid, targetUid)).set({
      'followerId': uid,
      'followeeId': targetUid,
      'at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unfollow(String targetUid) async {
    await _col.doc(_edgeId(uid, targetUid)).delete();
  }

  @override
  Future<Set<String>> following() async {
    final snap = await _col.where('followerId', isEqualTo: uid).get();
    return {
      for (final d in snap.docs)
        if (d.data()['followeeId'] is String) d.data()['followeeId'] as String,
    };
  }

  @override
  Future<Set<String>> followers() async {
    final snap = await _col.where('followeeId', isEqualTo: uid).get();
    return {
      for (final d in snap.docs)
        if (d.data()['followerId'] is String) d.data()['followerId'] as String,
    };
  }
}
