import 'package:cloud_firestore/cloud_firestore.dart';

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
}
