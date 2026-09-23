import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/community.dart';
import 'team_data.dart';

/// Firestore 上的團隊（[BE-11] 批次 4）。
///
/// ```
/// teams/{teamId}
///   name, isPublic, capacity, peakSize, disbanded,
///   memberUids[]            ← 供「我在哪一隊」查詢
///   members: { uid: {name, rank, role, joinedAt} }
/// teams/{teamId}/requests/{uid}
///   邀請與申請共用，isInvite 區分方向
/// ```
///
/// ## 成員為什麼內嵌而不是子集合
///
/// `Firestore-Schema設計.md` §2.10 原本畫的是 `members/{uid}` 子集合，
/// 但同一份文件第 0 節原則 3 說「小且有界的集合用內嵌陣列」——
/// **團隊上限 5 人**，是這條原則的標準案例。內嵌的好處是讀一支隊伍
/// 只要一次讀取，而且成員異動與人數上限的檢查落在同一份文件上，
/// 用 transaction 就能保證不會擠進第六個人。
///
/// `memberUids` 是同一份資料的查詢用投影 —— Firestore 無法對 Map 的鍵做查詢，
/// 而「我在哪一隊」每次登入都要問一次。
class FirestoreTeams implements TeamSource {
  final String uid;
  final FirebaseFirestore _db;

  FirestoreTeams({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('teams');

  // ===========================================================================
  // 讀取
  // ===========================================================================

  @override
  Future<CloudTeam?> myTeam() async {
    final snap = await _col
        .where('memberUids', arrayContains: uid)
        .where('disbanded', isEqualTo: false)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return _teamOf(snap.docs.first.id, snap.docs.first.data());
  }

  @override
  Future<List<CloudTeam>> openTeams({int limit = 30}) async {
    final snap = await _col
        .where('isPublic', isEqualTo: true)
        .where('disbanded', isEqualTo: false)
        .limit(limit)
        .get();

    final out = <CloudTeam>[];
    for (final d in snap.docs) {
      final t = _teamOf(d.id, d.data());
      // 已滿的隊伍不列出來 —— 申請了也進不去。
      if (t != null && !t.isFull) out.add(t);
    }
    return out;
  }

  @override
  Future<List<TeamRequest>> requestsFor(
    String forUid, {
    String? myTeamId,
    List<String>? errors,
  }) async {
    errors ??= [];
    final out = <TeamRequest>[];

    // **兩段各自成敗，不互相牽連。**
    //
    // 原本是接連兩個 await：邀請那段丟例外，申請那段就整個沒跑到。
    // 而邀請走的是 collection group 查詢 —— 少一條規則、少一個索引
    // 都會讓它失敗，卻是「隊長看不到別人的申請」的表象。
    // 兩件事本來就無關，一邊壞掉不該讓另一邊跟著消失。
    final results = await Future.wait([
      // 別人邀我入隊：散落在各隊底下，要用 collection group 一次撈。
      _db
          .collectionGroup('requests')
          .where('uid', isEqualTo: forUid)
          .where('isInvite', isEqualTo: true)
          .get()
          .then<List<TeamRequest>>(_parse)
          .catchError((Object e) {
        errors.add('邀請：$e');
        return <TeamRequest>[];
      }),
      // 別人申請加入我的隊：只有隊長看得到，範圍就在自己那一隊底下。
      if (myTeamId != null)
        _col
            .doc(myTeamId)
            .collection('requests')
            .where('isInvite', isEqualTo: false)
            .get()
            .then<List<TeamRequest>>(_parse)
            .catchError((Object e) {
          errors.add('申請：$e');
          return <TeamRequest>[];
        }),
    ]);
    for (final part in results) {
      out.addAll(part);
    }
    return out;
  }

  // ===========================================================================
  // 寫入
  // ===========================================================================

  @override
  Future<void> create(CloudTeam t) async {
    await _col.doc(t.id).set({
      'name': t.name,
      'isPublic': t.isPublic,
      'capacity': t.capacity,
      'peakSize': t.members.length,
      'disbanded': false,
      'memberUids': t.members.keys.toList(),
      'members': {
        for (final e in t.members.entries) e.key: _memberJson(e.value),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> putMember(String teamId, String memberUid, CloudMember m) async {
    final ref = _col.doc(teamId);
    // 用 transaction 而不是直接 update：人數上限與「加進去」必須是同一件事。
    // 分開做的話兩個人同時被核准，會擠出第六名成員 ——
    // 而〈團隊 Aggregate〉的人數上限是不變條件，不是建議值。
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null || data['disbanded'] == true) return;

      final members = Map<String, dynamic>.from(
          (data['members'] as Map?) ?? const {});
      final capacity =
          data['capacity'] is num ? (data['capacity'] as num).round() : kTeamCapacity;

      // 已在隊上的人是「更新」（例如升為隊長），不受上限限制。
      if (!members.containsKey(memberUid) && members.length >= capacity) return;

      members[memberUid] = _memberJson(m);
      final peak = data['peakSize'] is num ? (data['peakSize'] as num).round() : 0;

      tx.update(ref, {
        // **點記法指名單一成員**，不是把整個 members 覆寫回去。
        // 覆寫整份 Map 在真的 Firestore 上是取代、在部分測試替身上卻是
        // 深層合併 —— 兩邊行為不同的寫法本身就是個坑。指名一個鍵則
        // 兩邊一致，寫入量也小得多。
        'members.$memberUid': _memberJson(m),
        'memberUids': members.keys.toList(),
        // 本週期曾達到過的最高人數，單調遞增 —— 排行榜分組依它判定。
        'peakSize': members.length > peak ? members.length : peak,
      });
    });
  }

  @override
  Future<void> removeMember(String teamId, String memberUid) async {
    final ref = _col.doc(teamId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;

      final members = Map<String, dynamic>.from(
          (data['members'] as Map?) ?? const {});
      if (members.remove(memberUid) == null) return;

      tx.update(ref, {
        // 同上：**點記法指名刪除這一個鍵**。把移除後的整份 Map 寫回去的話，
        // 在會做深層合併的實作上那個鍵會被舊資料補回來 —— 人退了隊卻還在名單上。
        'members.$memberUid': FieldValue.delete(),
        'memberUids': members.keys.toList(),
        // peakSize **不減** —— 它是「曾經達到過」，不是「現在有幾人」。
      });
    });
  }

  @override
  Future<void> setVisibility(String teamId, bool isPublic) =>
      _col.doc(teamId).update({'isPublic': isPublic});

  @override
  Future<void> disband(String teamId) =>
      _col.doc(teamId).update({'disbanded': true});

  @override
  Future<void> sendRequest(TeamRequest r) async {
    // 文件 ID 是對象的 uid —— 同一個人對同一支隊伍只會有一筆待回應請求，
    // 由主鍵保證，不必先查一次有沒有重複。
    await _col.doc(r.teamId).collection('requests').doc(r.uid).set({
      'teamId': r.teamId,
      'teamName': r.teamName,
      'uid': r.uid,
      'name': r.name,
      'rank': r.rank,
      'isInvite': r.isInvite,
      'expiresAt': Timestamp.fromDate(r.expiresAt),
    });
  }

  @override
  Future<void> dropRequest(String teamId, String targetUid) =>
      _col.doc(teamId).collection('requests').doc(targetUid).delete();

  // ===========================================================================
  // 形狀轉換
  // ===========================================================================

  List<TeamRequest> _parse(QuerySnapshot<Map<String, dynamic>> snap) => [
        for (final d in snap.docs)
          if (_requestOf(d.data()) case final r?) r,
      ];

  Map<String, dynamic> _memberJson(CloudMember m) => {
        'name': m.name,
        'rank': m.rank,
        'role': m.role.name,
        'joinedAt': Timestamp.fromDate(m.joinedAt),
      };

  CloudTeam? _teamOf(String id, Map<String, dynamic> j) {
    final name = j['name'];
    if (name is! String) return null; // 認不出是哪一隊就當它不存在

    final raw = (j['members'] as Map?) ?? const {};
    final members = <String, CloudMember>{};
    raw.forEach((k, v) {
      if (k is! String || v is! Map) return;
      final n = v['name'];
      if (n is! String) return;
      members[k] = CloudMember(
        name: n,
        rank: v['rank'] is num ? (v['rank'] as num).round() : 1,
        role: v['role'] == TeamRole.leader.name
            ? TeamRole.leader
            : TeamRole.member,
        joinedAt: v['joinedAt'] is Timestamp
            ? (v['joinedAt'] as Timestamp).toDate()
            : DateTime.fromMillisecondsSinceEpoch(0),
      );
    });

    return CloudTeam(
      id: id,
      name: name,
      isPublic: j['isPublic'] != false,
      capacity:
          j['capacity'] is num ? (j['capacity'] as num).round() : kTeamCapacity,
      members: members,
      peakSize: j['peakSize'] is num ? (j['peakSize'] as num).round() : 0,
      disbanded: j['disbanded'] == true,
    );
  }

  TeamRequest? _requestOf(Map<String, dynamic> j) {
    final teamId = j['teamId'];
    final who = j['uid'];
    final exp = j['expiresAt'];
    if (teamId is! String || who is! String || exp is! Timestamp) return null;

    return TeamRequest(
      teamId: teamId,
      teamName: j['teamName'] is String ? j['teamName'] as String : '',
      uid: who,
      name: j['name'] is String ? j['name'] as String : '',
      rank: j['rank'] is num ? (j['rank'] as num).round() : 1,
      isInvite: j['isInvite'] == true,
      expiresAt: exp.toDate(),
    );
  }
}
