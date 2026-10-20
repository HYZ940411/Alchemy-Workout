import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/admin.dart';
import 'appeal_data.dart';

/// Firestore 上的申訴。
///
/// ```
/// appeals/{appellantUid}__{issuedAtMillis}
/// ```
class FirestoreAppeals implements AppealSource {
  final FirebaseFirestore _db;

  FirestoreAppeals({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('appeals');

  @override
  Future<void> file(CloudAppeal a) async {
    await _col.doc(a.id).set({
      'appellantUid': a.appellantUid,
      'appellantName': a.appellantName,
      'target': a.target.name,
      'subject': a.subject,
      'reason': a.reason,
      'filedAt': Timestamp.fromDate(a.filedAt),
      'daysSinceIncident': a.daysSinceIncident,
      if (a.content != null) 'content': a.content,
      // 管理端掃「還沒處理的」用這個欄位。
      'state': CaseState.pending.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<CloudAppeal>> queue({int limit = 100}) async {
    final snap = await _col
        .where('state', isEqualTo: CaseState.pending.name)
        .limit(limit)
        .get();

    final out = <CloudAppeal>[];
    for (final d in snap.docs) {
      final a = _appealOf(d.id, d.data());
      if (a != null) out.add(a);
    }
    // 由舊到新 —— 佇列要先處理等最久的那一筆。
    out.sort((a, b) => a.filedAt.compareTo(b.filedAt));
    return out;
  }

  @override
  Future<void> judge(String id,
      {required bool upheld, required String handlerName}) async {
    await _col.doc(id).update({
      'state': (upheld ? CaseState.upheld : CaseState.dismissed).name,
      'handlerName': handlerName,
      'judgedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<String>> approvedBlockedTexts(String uid) async {
    // 只查申訴人一個條件，其餘在這裡濾：不新增複合查詢（不必宣告索引），
    // 安全規則那一側看的是 `appellantUid == auth.uid`，查詢本身已限定、讀得動。
    // 一個人的申訴不會多，濾掉的量可以忽略。
    final snap = await _col.where('appellantUid', isEqualTo: uid).get();
    return [
      for (final d in snap.docs)
        if (d.data()['target'] == AppealTarget.blockedContent.name &&
            d.data()['state'] == CaseState.upheld.name)
          if (d.data()['content'] case final String t when t.isNotEmpty) t,
    ];
  }

  CloudAppeal? _appealOf(String id, Map<String, dynamic> j) {
    final uid = j['appellantUid'];
    final filedAt = j['filedAt'];
    // 認不出申訴人或時間的文件略過 —— 一筆壞資料不該讓整個佇列開不起來。
    if (uid is! String || filedAt is! Timestamp) return null;

    final target =
        AppealTarget.values.where((v) => v.name == j['target']).firstOrNull;
    if (target == null) return null;

    return CloudAppeal(
      id: id,
      appellantUid: uid,
      appellantName: j['appellantName'] as String? ?? '',
      target: target,
      subject: j['subject'] as String? ?? '',
      reason: j['reason'] as String? ?? '',
      filedAt: filedAt.toDate(),
      daysSinceIncident: (j['daysSinceIncident'] as num?)?.toInt() ?? 0,
      content: j['content'] as String?,
      state: CaseState.values.where((v) => v.name == j['state']).firstOrNull ??
          CaseState.pending,
      handlerName: j['handlerName'] as String?,
    );
  }
}
