import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/community.dart';
import 'chat_data.dart';

/// Firestore 上的私訊（[BE-11] 批次 5）。
///
/// ```
/// conversations/{convId}          participants[], names{}, deletedBy[], lastAt
/// conversations/{convId}/messages/{msgId}
/// ```
///
/// ## 對話 ID 由兩個 uid 排序後合成
///
/// `a_b` 與 `b_a` 會算出同一個 ID，所以**同一對人永遠只有一段對話** ——
/// 由主鍵保證，不是靠「送訊息前先查有沒有既有對話」。
/// 沒有這一層的話，兩個人同時開啟對話就會產生兩段，各自看到一半的訊息。
class FirestoreChats implements ChatSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestoreChats({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('conversations');

  /// 排序後合成 —— 誰先開始對話不影響 ID。
  @override
  String conversationIdOf(String a, String b) {
    final pair = [a, b]..sort();
    return pair.join('_');
  }

  @override
  Future<List<CloudConversation>> conversations({int limit = 50}) async {
    final snap = await _col
        .where('participants', arrayContains: uid)
        .orderBy('lastAt', descending: true)
        .limit(limit)
        .get();

    final out = <CloudConversation>[];
    for (final d in snap.docs) {
      final c = _conversationOf(d.id, d.data());
      if (c == null) continue;
      // 我這一側已刪除的不列出 —— 但文件還在，對方仍看得到。
      if (c.deletedBy.contains(uid)) continue;
      out.add(c);
    }

    await Future.wait([for (final c in out) _fillMessages(c)]);
    return out;
  }

  Future<void> _fillMessages(CloudConversation c) async {
    final snap =
        await _col.doc(c.id).collection('messages').orderBy('at').get();
    for (final d in snap.docs) {
      final m = _messageOf(d.id, d.data());
      if (m != null) c.messages.add(m);
    }
  }

  @override
  Future<void> send(
    String peerUid,
    CloudMessage m, {
    required String myName,
    required String peerName,
  }) async {
    final id = conversationIdOf(uid, peerUid);
    final conv = _col.doc(id);

    final batch = _db.batch();
    // 對話本體用 merge：第一次送訊息時建立，之後只更新 lastAt。
    batch.set(
      conv,
      {
        'participants': [uid, peerUid]..sort(),
        'names': {uid: myName, peerUid: peerName},
        'lastAt': Timestamp.fromDate(m.at),
        // 對方若曾在自己那一側刪除這段對話，新訊息要讓它重新出現 ——
        // 刪除的是「這段對話的歷史」，不是「拒收未來的訊息」（那是封鎖）。
        'deletedBy': FieldValue.arrayRemove([peerUid]),
      },
      SetOptions(merge: true),
    );
    batch.set(conv.collection('messages').doc(m.id), {
      'senderUid': m.senderUid,
      'text': m.text,
      'at': Timestamp.fromDate(m.at),
      'category': m.category.name,
      'pendingReview': m.pendingReview,
      'readBy': {uid: Timestamp.fromDate(m.at)}, // 自己送的當然自己讀過
    });
    await batch.commit();
  }

  @override
  Future<void> markRead(String conversationId) async {
    final msgs =
        await _col.doc(conversationId).collection('messages').get();

    final batch = _db.batch();
    final now = Timestamp.now();
    for (final d in msgs.docs) {
      final readBy = (d.data()['readBy'] as Map?) ?? const {};
      if (readBy.containsKey(uid)) continue; // 已經讀過就不重寫
      batch.update(d.reference, {'readBy.$uid': now});
    }
    await batch.commit();
  }

  @override
  Future<void> deleteForMe(String conversationId) => _col
      .doc(conversationId)
      .update({
        'deletedBy': FieldValue.arrayUnion([uid])
      });

  // ===========================================================================
  // 形狀轉換
  // ===========================================================================

  CloudConversation? _conversationOf(String id, Map<String, dynamic> j) {
    final parts = [
      for (final p in (j['participants'] as List? ?? const []))
        if (p is String) p,
    ];
    if (parts.length < 2) return null;

    final lastAt = j['lastAt'];
    return CloudConversation(
      id: id,
      participants: parts,
      names: _strMap(j['names']),
      ranks: _intMap(j['ranks']),
      instructors: {
        for (final e in ((j['instructors'] as Map?) ?? const {}).entries)
          if (e.key is String) e.key as String: e.value == true,
      },
      deletedBy: {
        for (final d in (j['deletedBy'] as List? ?? const []))
          if (d is String) d,
      },
      lastAt: lastAt is Timestamp
          ? lastAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      messages: [],
    );
  }

  CloudMessage? _messageOf(String id, Map<String, dynamic> j) {
    final sender = j['senderUid'];
    final at = j['at'];
    if (sender is! String || at is! Timestamp) return null;

    return CloudMessage(
      id: id,
      senderUid: sender,
      text: j['text'] is String ? j['text'] as String : '',
      at: at.toDate(),
      category: MessageCategory.values.firstWhere(
        (c) => c.name == j['category'],
        orElse: () => MessageCategory.normal,
      ),
      pendingReview: j['pendingReview'] == true,
      readBy: {
        for (final e in ((j['readBy'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is Timestamp)
            e.key as String: (e.value as Timestamp).toDate(),
      },
    );
  }

  Map<String, String> _strMap(Object? raw) => {
        for (final e in ((raw as Map?) ?? const {}).entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      };

  Map<String, int> _intMap(Object? raw) => {
        for (final e in ((raw as Map?) ?? const {}).entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).round(),
      };
}
