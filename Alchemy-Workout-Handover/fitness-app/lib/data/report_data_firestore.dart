import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/admin.dart';
import 'report_data.dart';

/// Firestore 上的檢舉（`Firestore-Schema設計.md` §2.16）。
///
/// ```
/// reports/{targetKey}__{reporterUid}
/// ```
///
/// ## 文件 ID 為什麼是「標的＋檢舉者」
///
/// 同一個人對同一則貼文重複按檢舉，應該是同一筆，不是三筆。
/// 用主鍵保證比先查再寫可靠 —— 後者在連按兩下時仍會寫出兩筆。
///
/// 併案（多人檢舉同一標的合併為一個案件）發生在**管理端**：
/// 這裡每位檢舉者各留一筆，管理端依 `targetKey` 分組。
/// 在客戶端併案的話，第二位檢舉者必須先讀得到第一位的那筆 ——
/// 而檢舉佇列正是一般使用者不該讀得到的東西。
class FirestoreReports implements ReportSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestoreReports({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Firestore 的文件 ID 不可含 `/`，而 targetKey 裡有 `:` 沒有 `/`，
  /// 仍以底線轉寫一次求穩。
  String _docId(String targetKey) =>
      '${targetKey.replaceAll('/', '_')}__$uid';

  @override
  Future<void> file(CloudReport r) async {
    await _db.collection('reports').doc(_docId(r.targetKey)).set({
      'targetKey': r.targetKey,
      'target': r.target.name,
      'origin': r.origin.name,
      'content': r.content,
      'reason': r.reason,
      if (r.note != null) 'note': r.note,
      'accused': r.accused,
      'reporterUid': r.reporterUid,
      'reporterName': r.reporterName,
      'at': Timestamp.fromDate(r.at),
      // 管理端掃「還沒處理的」用這個欄位，不必讀進整個佇列。
      'state': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<CloudReport>> queue({int limit = 100}) async {
    // 只撈還沒裁決的。**條件只有 `state`** —— 規則那一側是
    // `allow read: if isAdmin()`，不限欄位，所以不需要為了滿足規則
    // 而多加條件（`bond()` 那次的教訓反過來用：那裡是條件不夠，
    // 這裡是不必多加）。
    final snap = await _db
        .collection('reports')
        .where('state', isEqualTo: 'pending')
        .limit(limit)
        .get();

    final out = <CloudReport>[];
    for (final d in snap.docs) {
      final r = _reportOf(d.id, d.data());
      if (r != null) out.add(r);
    }
    // 由舊到新 —— 佇列要先處理等最久的那一筆。
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  @override
  Future<void> judge(List<String> ids,
      {required bool upheld, required String handlerName}) async {
    if (ids.isEmpty) return;
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(_db.collection('reports').doc(id), {
        'state': upheld ? 'upheld' : 'dismissed',
        'handlerName': handlerName,
        'judgedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  CloudReport? _reportOf(String id, Map<String, dynamic> j) {
    final targetKey = j['targetKey'];
    final at = j['at'];
    // 認不出標的或時間的文件略過 —— 一筆壞資料不該讓整個佇列開不起來。
    if (targetKey is! String || at is! Timestamp) return null;

    T? byName<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;

    final target = byName(ReportTarget.values, j['target']);
    final origin = byName(CaseOrigin.values, j['origin']);
    if (target == null || origin == null) return null;

    return CloudReport(
      id: id,
      targetKey: targetKey,
      target: target,
      origin: origin,
      content: j['content'] as String? ?? '',
      reason: j['reason'] as String? ?? '',
      note: j['note'] as String?,
      accused: j['accused'] as String? ?? '',
      reporterUid: j['reporterUid'] as String? ?? '',
      reporterName: j['reporterName'] as String? ?? '',
      at: at.toDate(),
    );
  }
}
