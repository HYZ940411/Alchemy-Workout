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
      // **上一輪的恢復提議要一起清掉。**
      //
      // 沒清的話，一段關係解除 → 對方提出恢復 → 沒被同意 → 又解除，
      // 第二次解除的當下畫面就跳出「對方提出了恢復，等你回應」——
      // 那是上一輪留下來的。使用者 2026-09-30 實測踩到。
      //
      // 一次解除開啟的是一個新的 3 天窗口，上一個窗口裡的提議
      // 不該跨過來。
      //
      // 與 `recover()` 一致寫 `null` 而不是 `FieldValue.delete()`。
      'restoreProposedBy': null,
    });
    for (final d in open.docs) {
      batch.update(d.reference, {'state': MentorTaskState.voided.name});
    }
    await batch.commit();
  }

  @override
  Future<void> recover(String bondId, DateTime now) async {
    final ref = _col.doc(bondId);

    // ## 為什麼這裡不用交易
    //
    // 原本用 `runTransaction`，理由是避免「讀的時候還在期限內，
    // 寫的時候已經過期」。那個顧慮對一個**三天**的窗口而言微乎其微，
    // 而代價很大：**在 Web 上，任何從交易裡冒出來的錯誤都會穿過
    // JS 的 Promise 邊界**，變成一句沒有內容的
    // 「Dart exception thrown from converted Future」。
    //
    // 2026-09-30 為了讀出那句話底下的原因，連續改了五輪儀器
    // （拆 `error` 屬性、點名讀 `code`／`name`／`message`、
    // 把值交回 Dart 那一側）—— 每一輪拿到的都是 `{}` 或
    // `[object Object]`，一次都沒有讀到真正的原因。
    //
    // 換成單純的讀＋寫之後，錯誤就是正常的 `FirebaseException`
    // （帶 `code`，例如 `permission-denied`、`resource-exhausted`），
    // 而我們自己的守衛丟的就是看得懂的 `StateError`。
    //
    // **看不見的正確，不如看得見的近似。**
    final snap = await ref.get();
    final b = _bondOf(bondId, snap.data() ?? const {});

    if (b == null) {
      throw StateError('recover: 關係文件不存在或缺 bondedAt（$bondId）');
    }
    if (b.state != MentorBondState.released) {
      throw StateError('recover: 這段關係不是已解除（state=${b.state.name}）');
    }
    final rel = b.releasedAt;
    if (rel == null) {
      throw StateError('recover: 已解除卻沒有 releasedAt');
    }
    if (!b.recoverableAt(now)) {
      throw StateError('recover: 已超過 3 天（解除於 $rel，現在 $now）');
    }

    // 寫 `null` 而不是 `FieldValue.delete()` —— 讀那一側本來就把
    // 「不是 Timestamp／不是 String」當成空值，兩者等價。
    await ref.update({
      'state': MentorBondState.active.name,
      'releasedAt': null,
      'releasedReason': null,
      // 提議已經被接受了 —— 留著下次解除時會看到上一輪的殘留。
      'restoreProposedBy': null,
    });
  }

  @override
  Future<void> proposeRestore(String bondId, String byUid) async {
    await _col.doc(bondId).update({
      'restoreProposedBy': byUid,
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> dropRestore(String bondId) async {
    await _col.doc(bondId).update({
      'restoreProposedBy': null,
      'lastActivityAt': FieldValue.serverTimestamp(),
    });
  }

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

  /// 動一下 bond 文件，讓對方的即時訂閱收得到訊號。
  ///
  /// ## 為什麼非做不可
  ///
  /// 任務與問答都寫在 `mentor_bonds/{id}` 的**子集合**裡，而
  /// [watchMentor] 監看的是 bond **文件本身** ——
  /// **子集合的寫入不會改動父文件，所以那個訂閱一次都不會觸發。**
  ///
  /// 使用者 2026-09-29 實測 T3：A 提問、B 要重新整理才看得到。
  /// 而 T1（接受拜師）是好的，因為接受會真的改到 bond 文件。
  ///
  /// ## 為什麼不改成監看子集合
  ///
  /// collection group 查詢要一個**不會自動建立**的索引，
  /// 而那是「畫面成功、雲端無聲拒絕」那一類的錯（`bond()` 那次）。
  /// 動一下父文件是同一個效果、零新索引，而且沿用已經驗過的那條訂閱。
  ///
  /// 失敗不擋主要動作 —— 問題本身已經寫進去了，少一次訊號的代價是
  /// 對方要下拉重新整理，而不是問題不見了。
  Future<void> _touchBond(String bondId) async {
    try {
      await _col.doc(bondId).update({
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // 見上：訊號送不出去不該讓提問本身失敗。
    }
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
    await _touchBond(bondId);
  }

  /// 學徒已評分該週互動 —— 寫在**關係文件本身**上。
  ///
  /// 用 `'weeklyRatings.$week'` 這種帶點的欄位路徑做部分更新，不整份
  /// 覆寫 —— 否則兩位學徒（或同一位跨週）的評分會互相蓋掉。
  ///
  /// 這是少數不必 `_touchBond` 的寫入：它動的就是關係文件，
  /// 教官那一側的 `watchMentor()` 本來就會被叫醒。
  @override
  Future<void> rateWeek(String bondId, String week, int stars) async {
    await _col.doc(bondId).update({
      'weeklyRatings.$week': stars,
      'lastActivityAt': FieldValue.serverTimestamp(),
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
    await _touchBond(bondId);
  }

  @override
  Future<void> answer(
      String bondId, String questionId, String text, DateTime at) async {
    await _col.doc(bondId).collection('questions').doc(questionId).update({
      'answer': text,
      'answeredAt': Timestamp.fromDate(at),
    });
    await _touchBond(bondId);
  }

  // ===========================================================================
  // 申請
  // ===========================================================================

  @override
  Future<List<MentorRequest>> sentRequests() async {
    // **`fromUid` 這個方向從來沒有被查過。** `requestsFor` 查的是
    // 「別人送給我的」，於是我自己送出去的申請永遠回不來 ——
    // 重新整理之後按鈕退回「申請師徒關係」，而雲端那筆還在。
    //
    // 安全規則允許 `toUid == uid || fromUid == uid`，所以這條查得動；
    // 但**不能與 `requestsFor` 合成一條** —— Firestore 不會過濾結果、
    // 只會整個拒絕查詢，而 or 條件證明不了自己（`bond()` 那次的教訓）。
    final snap = await _reqCol.where('fromUid', isEqualTo: uid).get();
    final out = <MentorRequest>[];
    for (final d in snap.docs) {
      final r = _requestOf(d.id, d.data());
      if (r != null) out.add(r);
    }
    return out;
  }

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

  /// 申請的文件 ID ＝「誰送給誰」。
  ///
  /// **在此之前用的是 `newId('mr')`（帶時間戳的流水號）**，
  /// 於是同一個人對同一位教官按幾次就寫幾筆 —— 使用者 2026-09-29
  /// 實測按了四次，雲端就有四筆。本機的「已送出」守衛擋不住，
  /// 因為那份清單重新整理之後是空的（見 `sentRequests`）。
  ///
  /// 用主鍵保證比先查再寫可靠：後者在連按兩下時仍會寫出兩筆。
  /// 同檢舉（`targetKey__reporterUid`）與教官申請（uid）的取捨。
  static String reqDocId(String fromUid, String toUid) =>
      '${fromUid}__$toUid';

  @override
  Future<void> sendRequest(MentorRequest r) async {
    await _reqCol.doc(reqDocId(r.fromUid, r.toUid)).set({
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
      restoreProposedBy: j['restoreProposedBy'] is String
          ? j['restoreProposedBy'] as String
          : null,
      weeklyRatings: {
        for (final e in (j['weeklyRatings'] as Map? ?? const {}).entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
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
