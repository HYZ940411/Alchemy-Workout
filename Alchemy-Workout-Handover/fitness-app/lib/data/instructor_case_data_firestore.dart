import 'package:cloud_firestore/cloud_firestore.dart';

import 'instructor_case_data.dart';

/// Firestore 上的教官申請案（`[BE-20]`）。
///
/// ```
/// instructor_cases/{applicantUid}
/// ```
///
/// ## 文件 ID 為什麼就是 uid
///
/// **一個人同時只會有一筆待審案件。** 重考送出就覆蓋掉上一次，
/// 佇列裡不會出現兩筆同一個人的申請 —— 由主鍵保證，
/// 比「先查有沒有再寫」可靠，後者在連按兩下時仍會寫出兩筆。
///
/// 這與檢舉（`reports/{targetKey}__{reporterUid}`）的取捨不同：
/// 檢舉是「同一個人對同一個標的只有一筆」，而這裡的唯一性是
/// 「同一個人只有一筆」，因為申請的標的就是他自己。
class FirestoreInstructorCases implements InstructorCaseSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestoreInstructorCases({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('instructor_cases');

  @override
  Future<void> file(CloudInstructorCase c) async {
    await _col.doc(uid).set({
      'applicant': c.applicant,
      'applicantUid': c.applicantUid,
      'aiScores': c.aiScores,
      'weighted': c.weighted,
      'concerns': c.concerns,
      // 攤成兩個鍵的物件陣列，而不是巢狀陣列 —— Firestore 不支援
      // 陣列裡再放陣列（存檔那一側 2026-09-29 才踩過同一件事）。
      'answers': [
        for (final (q, a) in c.answers) {'q': q, 'a': a},
      ],
      'at': Timestamp.fromDate(c.at),
      // 管理端掃「還沒處理的」用這個欄位，不必讀進整個佇列。
      'state': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<CloudInstructorCase>> queue({int limit = 100}) async {
    final snap =
        await _col.where('state', isEqualTo: 'pending').limit(limit).get();
    final out = <CloudInstructorCase>[];
    for (final d in snap.docs) {
      final c = _caseOf(d.id, d.data());
      if (c != null) out.add(c);
    }
    // 由舊到新 —— 佇列要先處理等最久的那一筆。
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  @override
  Future<void> decide(String applicantUid,
      {required bool passed, required String handlerName}) async {
    await _col.doc(applicantUid).update({
      'state': passed ? 'passed' : 'rejected',
      'handlerName': handlerName,
      'judgedAt': FieldValue.serverTimestamp(),
    });
  }

  CloudInstructorCase? _caseOf(String id, Map<String, dynamic> j) {
    final at = j['at'];
    // 認不出時間的文件略過 —— 一筆壞資料不該讓整個佇列開不起來。
    if (at is! Timestamp) return null;

    return CloudInstructorCase(
      applicantUid: j['applicantUid'] as String? ?? id,
      applicant: j['applicant'] as String? ?? '',
      aiScores: {
        for (final e in (j['aiScores'] as Map? ?? const {}).entries)
          '${e.key}': (e.value as num).toDouble(),
      },
      weighted: (j['weighted'] as num?)?.toDouble() ?? 0,
      concerns: [
        for (final x in (j['concerns'] as List? ?? const [])) '$x',
      ],
      answers: [
        for (final x in (j['answers'] as List? ?? const []))
          if (x is Map) ('${x['q'] ?? ''}', '${x['a'] ?? ''}'),
      ],
      at: at.toDate(),
    );
  }
}
