import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/novice_wrapup.dart';
import 'rating_data.dart';

/// Firestore 上的訓練體驗評分（`[BE-18]`）。
///
/// ```
/// experience_ratings/{raterUid}_{target}_{targetId}
///   raterUid, target, targetId, stars, feedback, at
/// ```
///
/// 安全規則：**本人可寫自己那一筆、本人與管理員可讀**
/// （見 `firestore.rules`）。管理員的讀取靠 custom claim，
/// 與待審佇列同一個判準。
class FirestoreRatings implements RatingSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestoreRatings({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('experience_ratings');

  @override
  Future<void> put(ExperienceRating r) async {
    final rater = r.raterUid;
    // 沒有 uid 就沒有文件 ID 可用（示範資料、還沒登入）——
    // 靜靜跳過，本機那一筆照常留著。
    if (rater == null) return;
    await _col.doc(ratingDocId(rater, r.target, r.targetId)).set({
      'raterUid': rater,
      'target': r.target.name,
      'targetId': r.targetId,
      'stars': r.stars,
      // 空的回饋不寫鍵，與公開檔案的可見度同一個慣例。
      if (r.feedback != null && r.feedback!.isNotEmpty) 'feedback': r.feedback,
      'at': Timestamp.fromDate(r.at),
    });
  }

  @override
  Future<List<ExperienceRating>> mine() async {
    final snap = await _col.where('raterUid', isEqualTo: uid).get();
    return _rowsOf(snap);
  }

  @override
  Future<List<ExperienceRating>> all({int limit = 500}) async {
    final snap = await _col.limit(limit).get();
    return _rowsOf(snap);
  }

  List<ExperienceRating> _rowsOf(QuerySnapshot<Map<String, dynamic>> snap) => [
        for (final d in snap.docs) ?_ratingOf(d.data()),
      ];

  /// 認不出來的就跳過，不拖垮整批 —— 同平台資料那一套。
  ExperienceRating? _ratingOf(Map<String, dynamic> j) {
    final rater = j['raterUid'];
    final targetId = j['targetId'];
    final stars = j['stars'];
    if (rater is! String || targetId is! String || stars is! num) return null;
    final target = RatingTarget.values
        .where((t) => t.name == j['target'])
        .firstOrNull;
    if (target == null) return null;
    return ExperienceRating(
      target: target,
      targetId: targetId,
      // **評分者的暱稱不存在雲端。** 彙總表不呈現「誰評的」
      // （規格的下鑽欄位只有星等、時戳、文字回饋），
      // 而存了就等於把「這個人給了 2 星」交給管理員看。
      rater: '',
      raterUid: rater,
      stars: stars.round(),
      feedback: j['feedback'] is String ? j['feedback'] as String : null,
      at: j['at'] is Timestamp
          ? (j['at'] as Timestamp).toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
