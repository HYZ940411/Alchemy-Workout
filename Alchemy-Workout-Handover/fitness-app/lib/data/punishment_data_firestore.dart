import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/commerce.dart';
import 'punishment_data.dart';

/// Firestore 上的處罰狀態。
///
/// ```
/// punishments/{uid}
/// ```
///
/// **文件 ID 就是當事人的 uid** —— 一人同時至多一個生效中的處罰
/// （規格：新處罰覆蓋舊的，級距由累計違規次數決定），由主鍵保證。
class FirestorePunishments implements PunishmentSource {
  final FirebaseFirestore _db;

  FirestorePunishments({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('punishments').doc(uid);

  @override
  Future<Punishment?> of(String uid) async {
    final d = await _doc(uid).get();
    final j = d.data();
    if (j == null) return null;

    final kind = PunishmentKind.values
        .where((v) => v.name == j['kind'])
        .firstOrNull;
    final issuedAt = j['issuedAt'];
    // 認不出種類或時戳的文件當作沒有處罰。**往「沒罰」的方向錯** ——
    // 一筆讀不懂的資料不該讓人被鎖在門外。
    if (kind == null || issuedAt is! Timestamp) return null;

    return Punishment(
      kind: kind,
      reason: j['reason'] as String? ?? '',
      evidence: j['evidence'] as String? ?? '',
      issuedAt: issuedAt.toDate(),
      violationCount: (j['violationCount'] as num?)?.toInt() ?? 0,
      nextConsequence: j['nextConsequence'] as String? ?? '',
      expiresAt: (j['expiresAt'] as Timestamp?)?.toDate(),
      appealed: j['appealed'] == true,
      appealState: AppealState.values
          .where((v) => v.name == j['appealState'])
          .firstOrNull,
    );
  }

  @override
  Future<void> issue(String uid, Punishment p,
      {required String name}) async {
    await _doc(uid).set({
      'kind': p.kind.name,
      'reason': p.reason,
      'evidence': p.evidence,
      'issuedAt': Timestamp.fromDate(p.issuedAt),
      'violationCount': p.violationCount,
      'nextConsequence': p.nextConsequence,
      'expiresAt':
          p.expiresAt == null ? null : Timestamp.fromDate(p.expiresAt!),
      // 新處罰把申訴狀態重置 —— 這是另一次處罰，申訴權限重新起算。
      'appealed': false,
      'appealState': null,
      'name': name, // 給管理端看的，判定不靠它
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> markAppealed(String uid, AppealState state) async {
    // **只動這兩個欄位。** 安全規則用 affectedKeys 限住，
    // 多寫一個就整份被拒 —— 那正是要的：當事人不能改自己的處罰種類。
    await _doc(uid).update({
      'appealed': true,
      'appealState': state.name,
    });
  }
}
