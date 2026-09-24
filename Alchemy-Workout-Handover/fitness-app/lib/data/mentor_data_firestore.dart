import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/community.dart';
import 'mentor_data.dart';
import 'cloud_watch.dart';

/// Firestore 上的師徒關係（[BE-11] 批次 6）。
///
/// ```
/// mentor_bonds/{mentorUid}_{apprenticeUid}
/// mentor_bonds/{bondId}/tasks/{taskId}
/// mentor_bonds/{bondId}/questions/{questionId}
/// mentor_requests/{requestId}
/// ```
///
/// ## 文件 ID 由兩人的 uid 合成
///
/// 「已解除三天內可恢復」在規格上是**同一筆轉回生效中**，不是新建一筆。
/// 合成 ID 讓這件事自然成立：恢復就是同一份文件的狀態轉換，
/// 那段關係的任務與問答也就還掛在原處。
class FirestoreMentor implements MentorSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestoreMentor({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('mentor_bonds');
  CollectionReference<Map<String, dynamic>> get _reqCol =>
      _db.collection('mentor_requests');

  String bondIdOf(String mentorUid, String apprenticeUid) =>
      '${mentorUid}_$apprenticeUid';

  // ===========================================================================
  // 關係
  // ===========================================================================

  /// 三條監聽，條件與 [bonds]、[requestsFor] 逐字相同。
  ///
  /// 關係要查兩個方向：我可能是教官，也可能是學徒。安全規則允許
  /// 「mentorUid 是我 **或** apprenticeUid 是我」，而 Firestore
  /// 不會過濾結果、只會整個拒絕查詢 —— 所以必須拆成兩條各自
  /// 證明得了自己的查詢，不能合成一條。`bond()` 那次就是栽在這裡。
  @override
  Stream<void> watchMentor() => mergeWatches([
        _col.where('mentorUid', isEqualTo: uid).snapshots(),
        _col.where('apprenticeUid', isEqualTo: uid).snapshots(),
        _reqCol.where('toUid', isEqualTo: uid).snapshots(),
      ]);

  @override
  Future<List<CloudBond>> bonds() async {
    // 我可能是教官，也可能是學徒 —— 兩個方向都要查。
    final results = await Future.wait([
      _col.where('mentorUid', isEqualTo: uid).get(),
      _col.where('apprenticeUid', isEqualTo: uid).get(),
    ]);

    final out = <CloudBond>[];
    for (final snap in results) {
      for (final d in snap.docs) {
        final b = _bondOf(d.id, d.data());
        if (b != null) out.add(b);
      }
    }
    return out;
  }

  @override
  Future<void> bond(CloudBond b) async {
    // 不變條件：**同一學徒同時至多一筆生效中。**
    //
    // **只有「我就是那位學徒」時查得動。** 安全規則要求每筆關係的
    // mentorUid 或 apprenticeUid 等於我，而 Firestore 不會過濾查詢結果 ——
    // 它整個拒絕查詢，除非查詢條件本身保證所有結果都通得過。
    //
    // 我是教官時查的是 `apprenticeUid == 對方`，保證不了 → permission-denied，
    // 而呼叫端是即發即忘吞掉錯誤，所以**接受拜師申請會畫面成功、
    // 雲端什麼都沒發生**。2026-09-24 上線後對照規則查出來的。
    //
    // 已知殘留：教官這一側驗不了對方是不是剛拜了別人為師。學徒那一側
    // 的 `mentorApplyBlockedReason()` 本來就擋著（有教官就不能再申請），
    // 而「一位學徒只能有一位教官」本來也是學徒的不變條件 ——
    // 由他那一側把關比較合理。
    if (b.apprenticeUid == uid) {
      final existing = await _col
          .where('apprenticeUid', isEqualTo: uid)
          .where('state', isEqualTo: MentorBondState.active.name)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return;
    }

    await _col.doc(b.id).set({
      'mentorUid': b.mentorUid,
      'apprenticeUid': b.apprenticeUid,
      'mentorName': b.mentorName,
      'apprenticeName': b.apprenticeName,
      'state': MentorBondState.active.name,
      'bondedAt': Timestamp.fromDate(b.bondedAt),
    });
  }

  @override
  Future<void> release(
      String bondId, MentorReleaseReason reason, DateTime at) async {
    final bond = _col.doc(bondId);

    // **未完成的任務一律轉為已作廢**（規格明訂：已作廢是終止狀態）。
    // 與解除放在同一批寫入 —— 分開做的話中途失敗會留下
    // 「關係已解除，但任務還在指派中」這種學徒點得下去卻沒有教官的狀態。
    final open = await bond
        .collection('tasks')
        .where('state', isEqualTo: MentorTaskState.assigned.name)
        .get();

    final batch = _db.batch();
    batch.update(bond, {
      'state': MentorBondState.released.name,
      'releasedAt': Timestamp.fromDate(at),
      'releasedReason': reason.name,
    });
    for (final d in open.docs) {
      batch.update(d.reference, {'state': MentorTaskState.voided.name});
    }
    await batch.commit();
  }

  @override
  Future<void> recover(String bondId, DateTime now) async {
    final ref = _col.doc(bondId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final b = _bondOf(bondId, snap.data() ?? const {});
      // 過了三天就不能恢復了 —— 判斷放在 transaction 裡，
      // 避免「讀的時候還在期限內，寫的時候已經過期」。
      if (b == null || !b.recoverableAt(now)) return;

      tx.update(ref, {
        'state': MentorBondState.active.name,
        'releasedAt': FieldValue.delete(),
        'releasedReason': FieldValue.delete(),
      });
    });
  }

  // ===========================================================================
  // 任務與問答
  // ===========================================================================

  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async {
    final snap = await _col.doc(bondId).collection('tasks').get();
    final out = <CloudMentorTask>[];
    for (final d in snap.docs) {
      final t = _taskOf(d.id, d.data());
      if (t != null) out.add(t);
    }
    return out;
  }

  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async {
    await _col.doc(bondId).collection('tasks').doc(t.id).set({
      'title': t.title,
      'detail': t.detail,
      'state': t.state.name,
      'rewardCoins': t.rewardCoins,
      if (t.rating != null) 'rating': t.rating,
    });
  }

  @override
  Future<List<CloudQuestion>> questions(String bondId) async {
    final snap =
        await _col.doc(bondId).collection('questions').orderBy('at').get();
    final out = <CloudQuestion>[];
    for (final d in snap.docs) {
      final q = _questionOf(d.id, d.data());
      if (q != null) out.add(q);
    }
    return out;
  }

  @override
  Future<void> ask(String bondId, CloudQuestion q) async {
    await _col.doc(bondId).collection('questions').doc(q.id).set({
      'fromUid': q.fromUid,
      'text': q.text,
      'at': Timestamp.fromDate(q.at),
    });
  }

  @override
  Future<void> answer(
      String bondId, String questionId, String text, DateTime at) async {
    await _col.doc(bondId).collection('questions').doc(questionId).update({
      'answer': text,
      'answeredAt': Timestamp.fromDate(at),
    });
  }

  // ===========================================================================
  // 申請
  // ===========================================================================

  @override
  Future<List<MentorRequest>> requestsFor(String forUid) async {
    final snap = await _reqCol.where('toUid', isEqualTo: forUid).get();
    final out = <MentorRequest>[];
    for (final d in snap.docs) {
      final r = _requestOf(d.id, d.data());
      if (r != null) out.add(r);
    }
    return out;
  }

  @override
  Future<void> sendRequest(MentorRequest r) async {
    await _reqCol.doc(r.id).set({
      'fromUid': r.fromUid,
      'toUid': r.toUid,
      'fromName': r.fromName,
      'fromRank': r.fromRank,
      'fromMentor': r.fromMentor,
      'at': Timestamp.fromDate(r.at),
      'expiresAt': Timestamp.fromDate(r.expiresAt),
    });
  }

  @override
  Future<void> dropRequest(String requestId) => _reqCol.doc(requestId).delete();

  // ===========================================================================
  // 形狀轉換
  // ===========================================================================

  CloudBond? _bondOf(String id, Map<String, dynamic> j) {
    final mentor = j['mentorUid'];
    final apprentice = j['apprenticeUid'];
    final at = j['bondedAt'];
    if (mentor is! String || apprentice is! String || at is! Timestamp) {
      return null;
    }

    return CloudBond(
      id: id,
      mentorUid: mentor,
      apprenticeUid: apprentice,
      mentorName: j['mentorName'] is String ? j['mentorName'] as String : '',
      apprenticeName:
          j['apprenticeName'] is String ? j['apprenticeName'] as String : '',
      state: j['state'] == MentorBondState.released.name
          ? MentorBondState.released
          : MentorBondState.active,
      bondedAt: at.toDate(),
      releasedAt: j['releasedAt'] is Timestamp
          ? (j['releasedAt'] as Timestamp).toDate()
          : null,
      releasedReason: _reasonOf(j['releasedReason']),
    );
  }

  MentorReleaseReason? _reasonOf(Object? raw) {
    for (final r in MentorReleaseReason.values) {
      if (r.name == raw) return r;
    }
    return null;
  }

  CloudMentorTask? _taskOf(String id, Map<String, dynamic> j) {
    final title = j['title'];
    if (title is! String) return null;
    return CloudMentorTask(
      id: id,
      title: title,
      detail: j['detail'] is String ? j['detail'] as String : '',
      state: MentorTaskState.values.firstWhere(
        (s) => s.name == j['state'],
        orElse: () => MentorTaskState.assigned,
      ),
      rewardCoins: j['rewardCoins'] is num
          ? (j['rewardCoins'] as num).round()
          : kMentorTaskCoin,
      rating: j['rating'] is num ? (j['rating'] as num).round() : null,
    );
  }

  CloudQuestion? _questionOf(String id, Map<String, dynamic> j) {
    final from = j['fromUid'];
    final at = j['at'];
    if (from is! String || at is! Timestamp) return null;
    return CloudQuestion(
      id: id,
      fromUid: from,
      text: j['text'] is String ? j['text'] as String : '',
      at: at.toDate(),
      answer: j['answer'] is String ? j['answer'] as String : null,
      answeredAt: j['answeredAt'] is Timestamp
          ? (j['answeredAt'] as Timestamp).toDate()
          : null,
    );
  }

  MentorRequest? _requestOf(String id, Map<String, dynamic> j) {
    final from = j['fromUid'];
    final to = j['toUid'];
    final at = j['at'];
    final exp = j['expiresAt'];
    if (from is! String || to is! String || at is! Timestamp ||
        exp is! Timestamp) {
      return null;
    }
    return MentorRequest(
      id: id,
      fromUid: from,
      toUid: to,
      fromName: j['fromName'] is String ? j['fromName'] as String : '',
      fromRank: j['fromRank'] is num ? (j['fromRank'] as num).round() : 1,
      fromMentor: j['fromMentor'] == true,
      at: at.toDate(),
      expiresAt: exp.toDate(),
    );
  }
}
