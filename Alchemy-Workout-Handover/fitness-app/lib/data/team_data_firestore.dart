import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/community.dart';
import 'team_data.dart';
import 'cloud_watch.dart';
import 'guarded_transaction.dart';

/// Firestore 上的團隊（[BE-11] 批次 4）。
///
/// ```
/// teams/{teamId}
///   name, isPublic, capacity, peakSize, disbanded,
///   memberUids[]            ← 供「我在哪一隊」查詢
///   members: { uid: {name, rank, role, joinedAt} }
///   contributions: { uid: int }   ← 各成員對本隊的日常貢獻
///   timedCredited: [uid]          ← 今日限時任務記在本隊帳上的成員
///   timedDay: 'yyyy-MM-dd'        ← 上面那份名單屬於哪一天（04:00 換日）
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

  /// 現在幾點。**決定「本月」是哪個月** —— 讀的時候挑本月那一份、寫的時候寫進本月。
  /// 預設是真實時間；測試可以注入。
  final DateTime Function() _clock;

  FirestoreTeams(
      {required this.uid, FirebaseFirestore? firestore, DateTime Function()? clock})
      : _db = firestore ?? FirebaseFirestore.instance,
        _clock = clock ?? DateTime.now;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('teams');

  // ===========================================================================
  // 讀取
  // ===========================================================================

  /// 三條監聽，每一條都照抄一支既有查詢的條件 ——
  /// 那組條件已通過線上的安全規則與 `firestore.indexes.json`。
  ///
  /// 兩條 collection group 監聽刻意**不合併成只查 `uid`**：
  /// 線上那個索引是 `(uid, isInvite)` 的 COLLECTION_GROUP 複合索引，
  /// 只查 `uid` 需要另一個「集合群組範圍的單欄位索引」，
  /// 而那種索引不會自動建立 —— 查詢會直接失敗。
  ///
  /// 解散是把 `disbanded` 改成 true，那會讓隊伍**離開**這個結果集，
  /// 監聽一樣收得到（移除也是變動）。
  @override
  Stream<void> watchTeams({String? myTeamId}) => mergeWatches([
        _col
            .where('memberUids', arrayContains: uid)
            .where('disbanded', isEqualTo: false)
            .snapshots(),
        _db
            .collectionGroup('requests')
            .where('uid', isEqualTo: uid)
            .where('isInvite', isEqualTo: true)
            .snapshots(),
        _db
            .collectionGroup('requests')
            .where('uid', isEqualTo: uid)
            .where('isInvite', isEqualTo: false)
            .snapshots(),
        // 別人申請加入我的隊：掛在隊伍底下，不掛在我身上。
        if (myTeamId != null)
          _col
              .doc(myTeamId)
              .collection('requests')
              .where('isInvite', isEqualTo: false)
              .snapshots(),
      ]);

  /// 我在哪一隊。**0 人的隊伍當作沒有** —— 理由同 [openTeams]。
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
      if (t == null) continue;
      // 已滿的隊伍不列出來 —— 申請了也進不去。
      if (t.isFull) continue;
      // **0 人的隊伍當作不存在。**
      //
      // 上面那個 `removeMember` 從此不會再產生這種東西，但
      // 2026-09-27 之前留下的殘留還在雲端，而它們沒有任何人會去清 ——
      // 申請加入一支沒有隊長的隊伍，永遠不會有人核准。
      if (t.members.isEmpty) continue;
      out.add(t);
    }
    return out;
  }

  @override
  Future<List<TeamRequest>> requestsFor(
    String forUid, {
    String? myTeamId,
    List<String>? errors,
  }) async {
    // 指派給區域變數再用。`errors ??= []` 只讓這個參數在**這一層**
    // 是非空的，閉包裡不算數 —— 參數可以被重新指派，型別提升進不去
    // 閉包。下面兩個 catchError 都是閉包。
    final log = errors ??= [];
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
        log.add('邀請：$e');
        return <TeamRequest>[];
      }),
      // **我自己送出、還沒被回應的申請。**
      //
      // 在此之前沒有人讀這一段：申請寫進了 Firestore，但本機那筆只活在
      // 記憶體裡（`sentApplications` 不進存檔），於是重新載入之後
      // 「已送出申請」就消失了，看起來像是申請被自動取消 ——
      // 其實雲端那筆好端端地還在，隊長也還看得到。
      //
      // 與上面那段共用同一個複合索引（uid + isInvite），不必多建。
      _db
          .collectionGroup('requests')
          .where('uid', isEqualTo: forUid)
          .where('isInvite', isEqualTo: false)
          .get()
          .then<List<TeamRequest>>(_parse)
          .catchError((Object e) {
        log.add('我送出的申請：$e');
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
          log.add('申請：$e');
          return <TeamRequest>[];
        }),
    ]);
    // 兩段 collection group 查詢可能撈到同一筆（例如我申請加入的隊
    // 剛好就是我的隊），以「隊伍 + 對象」去重。
    final seen = <String>{};
    for (final part in results) {
      for (final r in part) {
        if (seen.add('${r.teamId}/${r.uid}')) out.add(r);
      }
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
      // 新隊從 0 起算 —— 你在上一支隊伍的貢獻留在上一支隊伍。
      // 分數按月份分開存（見 [CloudTeam.contribByMonth]）。
      'contribByMonth': <String, dynamic>{},
      'timedByMonth': <String, dynamic>{},
      'timedCredited': <String>[],
      'timedDay': '',
      'timedPeriod': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> putMember(String teamId, String memberUid, CloudMember m) async {
    final ref = _col.doc(teamId);
    // 用 transaction 而不是直接 update：人數上限與「加進去」必須是同一件事。
    // 分開做的話兩個人同時被核准，會擠出第六名成員 ——
    // 而〈團隊 Aggregate〉的人數上限是不變條件，不是建議值。
    //
    // **沒加成要說出口。** 隊伍不見了、已解散、人滿了，原本都是靜靜 `return`，
    // 呼叫端記成「成功」而名冊一個字沒動。判斷不成立時回傳原因，
    // 由 [guardedTransaction] 在交易外面丟（見該檔說明）。
    await guardedTransaction(_db, '加入團隊', (tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return '找不到這支隊伍（$teamId）';
      if (data['disbanded'] == true) return '這支隊伍已解散';

      final members = Map<String, dynamic>.from(
          (data['members'] as Map?) ?? const {});
      final capacity =
          data['capacity'] is num ? (data['capacity'] as num).round() : kTeamCapacity;

      // 已在隊上的人是「更新」（例如升為隊長），不受上限限制。
      if (!members.containsKey(memberUid) && members.length >= capacity) {
        return '隊伍已滿（$capacity 人）';
      }

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
      return null;
    });
  }

  @override
  Future<void> removeMember(String teamId, String memberUid) async {
    final ref = _col.doc(teamId);
    await guardedTransaction(_db, '離開團隊', (tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return '找不到這支隊伍（$teamId）';

      final members = Map<String, dynamic>.from(
          (data['members'] as Map?) ?? const {});
      // 本來就不在名冊上：想要的結果（不在隊上）已經成立，不是失敗。
      // 這是唯一刻意保持安靜的守衛 —— 重複離隊、或兩台裝置同時按，都該是冪等的。
      if (members.remove(memberUid) == null) return null;

      tx.update(ref, {
        // 同上：**點記法指名刪除這一個鍵**。把移除後的整份 Map 寫回去的話，
        // 在會做深層合併的實作上那個鍵會被舊資料補回來 —— 人退了隊卻還在名單上。
        'members.$memberUid': FieldValue.delete(),
        'memberUids': members.keys.toList(),
        // peakSize **不減** —— 它是「曾經達到過」，不是「現在有幾人」。

        // **最後一人離開就是解散，在這一層守住。**
        //
        // 「隊長退出即解散」原本只寫在 `AppState.leaveTeamOutcome()` 裡，
        // 而它的判斷依賴 `iAmLeader` —— 那個在 2026-09-27 之前比對的是
        // 暱稱（而畫面上甚至是寫死的「你」）。判成不是隊長，就不會解散：
        // 成員被移光、`disbanded` 仍是 false，於是一支 0 人的隊伍
        // 繼續出現在公開團隊清單裡。使用者回報「0 人的團隊沒有被移除」。
        //
        // 呼叫端算錯過一次，就不能只靠呼叫端。這裡是所有離隊路徑
        // （自己退、被踢、轉讓後退）的共同出口。
        if (members.isEmpty) 'disbanded': true,
      });
      return null;
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
        for (final d in snap.docs) ?_requestOf(d.data()),
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

    // 分數按月份分開存；上面的 contributions／timedScore 是「本月」那一份的視圖。
    final period = teamMonthKey(_clock());
    final byMonth = <String, Map<String, int>>{};
    ((j['contribByMonth'] as Map?) ?? const {}).forEach((m, v) {
      if (m is! String || v is! Map) return;
      byMonth[m] = {
        for (final e in v.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).round(),
      };
    });
    final timedByMonth = <String, int>{
      for (final e in ((j['timedByMonth'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is num)
          e.key as String: (e.value as num).round(),
    };

    return CloudTeam(
      id: id,
      name: name,
      isPublic: j['isPublic'] != false,
      capacity:
          j['capacity'] is num ? (j['capacity'] as num).round() : kTeamCapacity,
      members: members,
      peakSize: j['peakSize'] is num ? (j['peakSize'] as num).round() : 0,
      disbanded: j['disbanded'] == true,
      contributions: {...?byMonth[period]},
      contribByMonth: byMonth,
      timedByMonth: timedByMonth,
      timedCredited: {
        for (final v in (j['timedCredited'] as List? ?? const []))
          if (v is String) v,
      },
      timedDay: j['timedDay'] is String ? j['timedDay'] as String : '',
      // 本月的限時分數；不是本月的就是 0，所以 [timedPeriod] 固定寫本月。
      timedScore: timedByMonth[period] ?? 0,
      timedPeriod: period,
    );
  }

  /// **`FieldValue.increment` 而不是讀出來加一加再寫回去。**
  ///
  /// 後者是「讀—改—寫」，兩台裝置同時練完會丟掉一次；而且安全規則
  /// 只放行「自己那一格、而且往上」，整份覆寫寫不過去。
  ///
  /// **寫進本月那一格**：`contribByMonth.{yyyy-MM}.{uid}`，月份鍵同一次寫入也帶在 `dailyPeriod`
  /// （安全規則靠它知道這次動的是哪個月）。舊的 `contributions` 欄位不再寫。
  @override
  Future<void> addScore(String teamId, String memberUid, int delta) async {
    if (delta == 0) return;
    final period = teamMonthKey(_clock());
    await _col.doc(teamId).set({
      'contribByMonth': {
        period: {memberUid: FieldValue.increment(delta)},
      },
      'dailyPeriod': period,
    }, SetOptions(merge: true));
  }

  /// 換日清空由**第一個在新的一天完成的人**順手做（見 `CloudTeam.timedDay`）。
  ///
  /// 用 transaction：判斷「雲端那份是不是今天的」與「把自己加進去」
  /// 必須是同一件事，分開做的話同一秒完成的兩個人會互相蓋掉。
  @override
  Future<void> creditTimed(String teamId, String memberUid, String day) async {
    final ref = _col.doc(teamId);
    await guardedTransaction(_db, '限時任務計分', (tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return '找不到這支隊伍（$teamId）';
      final data = snap.data() ?? const <String, dynamic>{};
      final cloudDay = data['timedDay'];
      final before = cloudDay == day
          ? {
              for (final v in (data['timedCredited'] as List? ?? const []))
                if (v is String) v,
            }
          : <String>{};
      final already = before.contains(memberUid);
      // 鍵可能是 [FieldPath]（巢狀欄位的某一格），所以不能是 Map<String, dynamic>。
      final updates = <Object, Object?>{};
      if (cloudDay == day) {
        updates['timedCredited'] = FieldValue.arrayUnion([memberUid]);
      } else {
        // 新的一天：整份換掉，不是疊上去。
        updates['timedCredited'] = [memberUid];
        updates['timedDay'] = day;
      }

      // **月累計的團隊限時分數在這裡加** —— 以前完成限時任務只動上面那份今日名單，
      // 排行榜用的分數永遠是 0（2026-10-16 使用者回報）。
      //
      // 只有「這個人今天第一次被記」才加：按兩次、重新整理後再按，都不會多拿。
      // 重新分隊期（每月前兩天）兩個團隊分數皆不累加。
      // 全員完成的 +50 看這一刻隊上有誰，所以必須在同一個交易裡算。
      // `day` 可能帶重置代數（`2026-10-17#1760000000`），日期與月份只看 # 之前。
      final dateOnly = day.split('#').first;
      if (!already && !inRegroupWindow(DateTime.parse(dateOnly))) {
        final members = {
          for (final v in (data['memberUids'] as List? ?? const []))
            if (v is String) v,
        };
        final after = {...before, memberUid};
        final allDone = members.isNotEmpty && members.every(after.contains);
        final delta = kTimedTaskPerMember + (allDone ? kTimedTaskAllBonus : 0);
        final period = dateOnly.substring(0, 7);
        // 月累計寫進 `timedByMonth.{yyyy-MM}`：新的一個月只是多一個鍵，上個月的原封不動
        // （管理員按結算時要讀得到）。巢狀欄位的某一格要用 [FieldPath]，不能用 'a.b' 字串 ——
        // 月份鍵 '2026-10' 不是合法的欄位名稱片段。
        updates[FieldPath(['timedByMonth', period])] = FieldValue.increment(delta);
        updates['timedPeriod'] = period;
      }
      tx.update(ref, updates);
      return null;
    });
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
