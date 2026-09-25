import 'package:cloud_firestore/cloud_firestore.dart';

import 'violation_data.dart';

/// Firestore 上的累計違規次數。
///
/// ```
/// violations/{uid}    count, name, updatedAt
/// ```
///
/// **文件 ID 就是當事人的 uid** —— 一個人一筆由主鍵保證，
/// 不必先查再寫。用暱稱當鍵的話，改名就斷了、撞名就混了。
class FirestoreViolations implements ViolationSource {
  final FirebaseFirestore _db;

  FirestoreViolations({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('violations').doc(uid);

  @override
  Future<int> countOf(String uid) async {
    final d = await _doc(uid).get();
    // 沒有紀錄＝沒有違規過。這與「讀不到」不同，後者會往上拋。
    return (d.data()?['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<int> decrement(String uid) async {
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(_doc(uid));
      final now = (snap.data()?['count'] as num?)?.toInt() ?? 0;
      // **不會低於 0。** 退一次而不是歸零 —— 他之前可能還有別的違規。
      final next = now > 0 ? now - 1 : 0;
      tx.set(
        _doc(uid),
        {'count': next, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      return next;
    });
  }

  @override
  Future<int> increment(String uid, {required String name}) async {
    // **交易，不是先讀再寫。** 兩位管理員同時裁決同一個人的兩個案件時，
    // 先讀再寫會讓其中一次消失 —— 而這個數字決定處罰級距。
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(_doc(uid));
      final next = ((snap.data()?['count'] as num?)?.toInt() ?? 0) + 1;
      tx.set(
        _doc(uid),
        {
          'count': next,
          'name': name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return next;
    });
  }
}
