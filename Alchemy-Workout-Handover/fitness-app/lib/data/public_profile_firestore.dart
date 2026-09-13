import 'package:cloud_firestore/cloud_firestore.dart';

import 'public_profile.dart';

/// Firestore 上的公開檔案（[BE-11] 批次 1）。
///
/// ```
/// public_profiles/{uid}   一位使用者對外可見的部分
/// ```
///
/// 安全規則：**登入者皆可讀、只有本人可寫**（見 `firestore.rules`）。
/// 這是整個模型裡第一個「別人讀得到我的資料」的集合 ——
/// 在它之前，Firestore 上的每一份文件都只有擁有者自己看得到。
class FirestorePublicProfile implements PublicProfileSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestorePublicProfile({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('public_profiles');

  @override
  Future<void> publish(PublicProfile me) async {
    // 用 set 整份覆寫、**不用 merge** —— 可見度是可以關掉的。
    // merge 只會疊上新欄位，關掉六維之後那份舊的 ability 會留在雲端，
    // 使用者以為自己關了，別人其實還讀得到。
    await _col.doc(uid).set(me.toJson());
  }

  @override
  Future<List<PublicProfile>> others({int limit = 50}) async {
    // 依階級排序取前 N 位。階級高的通常是活躍使用者，
    // 而「教官清單」「動態牆」這些畫面本來就是從高階往下看。
    final snap = await _col.orderBy('rank', descending: true).limit(limit).get();

    final out = <PublicProfile>[];
    for (final d in snap.docs) {
      if (d.id == uid) continue; // 自己不算「別人」
      final p = PublicProfile.fromJson(d.id, d.data());
      // 認不出來的文件直接略過，不讓一筆壞資料把整份清單弄掉。
      if (p != null) out.add(p);
    }
    return out;
  }
}
