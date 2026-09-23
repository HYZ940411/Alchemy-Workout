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
    await _col.doc(uid).set({
      ...me.toJson(),
      // **伺服器時間，不是裝置時間。** 這個欄位決定誰排在「找人」前面，
      // 用客戶端的時間等於讓人把自己排到第一位。
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove() => _col.doc(uid).delete();

  @override
  Future<List<PublicProfile>> others({int limit = kProfileFetchLimit}) async {
    // **依最近活躍排序，不是依階級。**
    //
    // 原本是 `orderBy('rank', descending: true)` —— 而新註冊的人階級最低，
    // 所以永遠排在名單外。這份清單不只是「推薦誰給你看」：暱稱→uid 的
    // 對照表、找人、別人的六維與階級，全都只認得它裡面的人。
    // 於是使用者一多，**新來的人在整個 App 裡是隱形的** ——
    // 找不到、私訊不了，他的貼文還會顯示錯的階級（讀不到就取預設）。
    //
    // 活躍排序至少讓「現在在用的人」彼此看得到。真正的解法是按 uid
    // 隨用隨取，那要動到每一個呼叫端，不在這次的範圍。
    final out = <PublicProfile>[];
    final seen = <String>{};

    void take(QuerySnapshot<Map<String, dynamic>> snap) {
      for (final d in snap.docs) {
        if (d.id == uid) continue; // 自己不算「別人」
        if (!seen.add(d.id)) continue;
        final p = PublicProfile.fromJson(d.id, d.data());
        // 認不出來的文件直接略過，不讓一筆壞資料把整份清單弄掉。
        if (p != null) out.add(p);
      }
    }

    take(await _col
        .orderBy('lastActiveAt', descending: true)
        .limit(limit)
        .get());

    // **沒有 lastActiveAt 的文件不會出現在上面那個查詢裡** ——
    // Firestore 的排序會直接排除缺少該欄位的文件。這個欄位是後來才加的，
    // 所以還沒重新登入過的舊帳號一個都撈不到。用階級補滿，
    // 等所有人都登入過一次之後這一段就不會再跑到實質結果。
    if (out.length < limit) {
      take(await _col
          .orderBy('rank', descending: true)
          .limit(limit - out.length)
          .get());
    }
    return out;
  }
}
