import 'package:cloud_firestore/cloud_firestore.dart';

import 'store.dart';

/// Firestore 版的儲存後端。
///
/// 與 [FileStore]／[WebStore] 的差別只在「東西放在哪」——
/// 對 [AppState] 而言三者完全一樣，都是整份快照的 `load`／`save`／`clear`。
/// 這是 `store.dart` 那個抽象介面存在的理由，也是 [BE-04] 不用動
/// [AppState] 一行的原因。
///
/// ## 文件切法
///
/// 依 `Firestore-Schema設計.md` 的規劃，一份快照落地成多份文件：
///
/// ```
/// users/{uid}                      根文件：所有純量與小集合
/// users/{uid}/ability/state        六維點數現況
/// users/{uid}/streaks/training     連續訓練
/// users/{uid}/streaks/checkin      連續簽到（四欄位，見 _checkinDoc）
/// users/{uid}/wallet/coins         金幣
/// users/{uid}/wallet/tickets       補簽券
/// users/{uid}/wallet/ai_credits    AI 點數
/// users/{uid}/membership/current   會員權益（文件不存在＝從未訂閱過）
/// users/{uid}/history/{index}      訓練歷史，一場一份
/// ```
///
/// **為什麼訓練歷史要獨立成子集合**：Firestore 單一文件上限 1 MiB。
/// 訓練歷史是快照裡唯一會無上限成長的東西（一場訓練約 1.5 KB，
/// 一年練 150 場就是 225 KB），全部塞進根文件的話，重度使用者練個幾年
/// 就會踩到上限 —— 而 [AppState.saveNow] 對寫入失敗是靜默吞掉的，
/// 使用者會在毫無徵兆的情況下停止存檔。其餘欄位皆有天然上限，留在根文件。
class FirestoreStore implements Store {
  /// 這份 Store 服務哪一個帳號。等同 [FileStore] 的 `fileName` ——
  /// 是「要讀寫哪裡」的座標，不是使用者的一項資料。
  final String uid;

  final FirebaseFirestore _db;

  FirestoreStore({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _root =>
      _db.collection('users').doc(uid);

  // 上一次已寫進 Firestore 的內容，供 [save] 做分組比對。
  // 沒變的分組就不發那一份寫入 —— 300ms 防抖一次動輒觸發全部欄位，
  // 不比對的話等於每次改一個開關都重寫整棵樹。
  Map<String, dynamic>? _lastRoot;
  final Map<String, Map<String, dynamic>> _lastDocs = {};

  /// 已寫進雲端的訓練歷史，key 是**時間順序**的場次序號（見 [save]）。
  ///
  /// 原本這裡只記一個筆數 `_lastHistoryCount`，然後寫「比上次多出來的那幾筆」。
  /// 那假設了歷史是往後追加的，而快照裡的歷史是**新的在前** ——
  /// 於是每一場新訓練都寫錯格，寫進去的是被插隊擠下去的舊那場。
  /// 記內容而不是記筆數，順序怎麼變都不會寫錯。
  final Map<int, Map<String, dynamic>> _lastHistory = {};
  int _lastHistoryLength = -1;

  // ===========================================================================
  // 讀取
  // ===========================================================================

  @override
  Future<Map<String, dynamic>?> load() async {
    final DocumentSnapshot<Map<String, dynamic>> root;
    final List<DocumentSnapshot<Map<String, dynamic>>> docs;
    final QuerySnapshot<Map<String, dynamic>> history;

    try {
      root = await _root.get();
      if (!root.exists) return null; // 沒存過

      final fetched = await Future.wait([
        _sub('ability', 'state').get(),
        _sub('streaks', 'training').get(),
        _sub('streaks', 'checkin').get(),
        _sub('wallet', 'coins').get(),
        _sub('wallet', 'tickets').get(),
        _sub('wallet', 'ai_credits').get(),
        _sub('membership', 'current').get(),
      ]);
      docs = fetched;
      history = await _root.collection('history').orderBy('seq').get();
    } on FirebaseException catch (e) {
      // 「讀不出來」在 Firestore 的樣子是連線失敗、權限被拒、逾時 ——
      // 不是本機檔案那種「JSON 壞掉」。但對使用者的意義一樣：
      // 他的資料還在雲端，只是這次拿不到，不可以當成「沒存過」而給他
      // 一份空白帳號，那會讓下一次自動存檔把空白寫回去、真的清掉資料。
      throw StoreLoadException('Firestore 讀取失敗（${e.code}）：${e.message}');
    }

    // 根文件含 `v`（存檔格式版本）——**它必須原樣存、原樣還**，
    // 比照 [FileStore]：那邊是整份 JSON 進出，版本號自然就在裡面。
    // 這裡若自作聰明把它拿掉再補上「現在這版」的號碼，就等於宣稱
    // 任何一份舊存檔都是新版的 —— applySnapshot 的版本檢查會整個失效，
    // 而那個檢查正是 v1→v2 信箱獎勵被靜默清空之後才補上的防線。
    final out = <String, dynamic>{...?root.data()};

    _merge(out, docs[0]); // ability/state
    _merge(out, docs[1]); // streaks/training
    _mergeCheckin(out, docs[2]); // streaks/checkin
    _merge(out, docs[3]); // wallet/coins
    _merge(out, docs[4]); // wallet/tickets
    _merge(out, docs[5]); // wallet/ai_credits
    _mergeMembership(out, docs[6]);

    // 落地是舊的在前（`seq` 即時間順序），快照要的是新的在前。
    out['history'] = _dedupeHistory([
      for (final d in history.docs.reversed) _historyFromDoc(d.data()),
    ]);

    // **記下雲端現在有幾份歷史文件**，[save] 才知道要刪掉多出來的幾份。
    //
    // 少了這一行，`_lastHistoryLength` 留在 -1，於是 [save] 裡那個
    // 「把多出來的舊文件刪掉」的迴圈跑的是 `for (i = 現在筆數; i < -1)`
    // —— 一次都不跑。剛剛被 [_dedupeHistory] 剔掉的重複文件會留在雲端，
    // 而它們的 `seq` 比之後的新場次大，反轉之後就排到新場次前面：
    // 使用者看到的是「訓練歷史變成舊到新排序」，而且課表卡上的
    // 「上次訓練」讀到的是那筆舊的。
    //
    // 取**文件數**而不是剔重後的筆數 —— 要刪的正是兩者的差。
    _lastHistoryLength = history.docs.length;

    return out;
  }

  DocumentReference<Map<String, dynamic>> _sub(String col, String id) =>
      _root.collection(col).doc(id);

  void _merge(
      Map<String, dynamic> out, DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    if (data != null) out.addAll(data);
  }

  /// 連續簽到：規格要求四個欄位皆為儲存值，但 [AppState] 只認其中兩個
  /// （另外兩個是它從每日簽到紀錄推算出來的衍生值）。
  /// 多出來的那兩個讀回來就丟掉，不塞進快照 —— 塞了 applySnapshot 也不認，
  /// 只會讓「快照裡有哪些鍵」變得不可預測。
  void _mergeCheckin(
      Map<String, dynamic> out, DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    if (data == null) return;
    if (data.containsKey('checkInTotal')) {
      out['checkInTotal'] = data['checkInTotal'];
    }
    if (data.containsKey('checkInLongest')) {
      out['checkInLongest'] = data['checkInLongest'];
    }
  }

  /// 會員權益：規格明訂生效狀態只有三值，「從未訂閱過」不是其中之一 ——
  /// 它的樣子是這份文件根本不存在。
  void _mergeMembership(
      Map<String, dynamic> out, DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    if (data == null) {
      out['membership'] = 'none';
      return;
    }
    out.addAll(data);
  }

  // ===========================================================================
  // 寫入
  // ===========================================================================

  @override
  Future<void> save(Map<String, dynamic> data) async {
    // `v` 留在根文件裡照原樣存 —— 見 [load] 的說明。
    final rest = Map<String, dynamic>.from(data);
    final history = rest.remove('history');

    // `savedAt` 每次 toSnapshot() 都是當下時間，**一定**與上次不同。
    // 把它留在比對範圍內，「沒變就不寫」這條最佳化會完全失效 ——
    // 每一次 300ms 防抖都會重寫整份根文件。拿掉它比對，真的要寫的時候再補回去。
    final savedAt = rest.remove('savedAt');
    final groups = <String, Map<String, dynamic>>{
      'ability/state': _take(rest, const [
        'points',
        'pending',
        'trainedDims',
        'snapshots',
        'decayTimers',
      ]),
      'streaks/training': _take(rest, const [
        'trainingStreakDays',
        'lastTrainedDate',
        'totalWorkouts',
        'totalWorkoutDays',
        'trainNoticeStage',
      ]),
      'streaks/checkin': _checkinDoc(rest, data),
      'wallet/coins': _take(rest, const ['coins']),
      'wallet/tickets': _take(rest, const ['makeupTickets']),
      'wallet/ai_credits': _take(rest, const [
        'aiMonthly',
        'aiPermanent',
        'aiResetMonth',
      ]),
      'membership/current': _take(rest, const [
        'membership',
        'membershipExpiry',
        'membershipLockedPlanIds',
      ]),
    };

    // 這一批要送出去的寫入。先收集再分批送 —— 見 [_batchLimit]。
    final ops = <void Function(WriteBatch)>[];

    if (!_same(rest, _lastRoot)) {
      ops.add((b) =>
          b.set(_root, {...rest, 'savedAt': savedAt}, SetOptions(merge: true)));
    }

    for (final entry in groups.entries) {
      final path = entry.key.split('/');
      final doc = entry.value;

      // 會員權益「從未訂閱過」＝不建立這份文件（規格：無「未生效」這個值）。
      if (entry.key == 'membership/current' && doc['membership'] == 'none') {
        continue;
      }
      if (_same(doc, _lastDocs[entry.key])) continue;

      ops.add((b) => b.set(_sub(path[0], path[1]), doc, SetOptions(merge: true)));
    }

    // --- 訓練歷史 ---
    //
    // **快照裡是新的在前，落地是舊的在前。**
    //
    // 文件 ID 必須綁**時間順序**才穩定：新的一場拿到新的號碼，既有場次的
    // 號碼不動。若照快照的索引給號（新的在前），每加一場全部號碼都往後挪，
    // 「只寫多出來的那幾筆」就會把新的那場寫到舊的格子裡 ——
    // 使用者回報的「練了 7 次，7 筆全是第一場」正是這樣來的。
    final entries = history is List ? history : const [];
    final chrono = entries.reversed.toList();
    final nextHistory = <int, Map<String, dynamic>>{};
    for (var i = 0; i < chrono.length; i++) {
      final doc = _historyToDoc(chrono[i] as Map<String, dynamic>, i);
      nextHistory[i] = doc;
      if (_same(doc, _lastHistory[i])) continue;
      ops.add((b) => b.set(_root.collection('history').doc(_seqId(i)), doc));
    }
    // 歷史變短會發生在重設帳號，也發生在讀回來時剔掉重複的壞資料。
    // 不刪的話，下次讀回來會混進已經不該存在的場次。
    for (var i = chrono.length; i < _lastHistoryLength; i++) {
      ops.add((b) => b.delete(_root.collection('history').doc(_seqId(i))));
    }

    if (ops.isEmpty) return;
    for (var i = 0; i < ops.length; i += _batchLimit) {
      final batch = _db.batch();
      for (final op in ops.skip(i).take(_batchLimit)) {
        op(batch);
      }
      await batch.commit();
    }

    _lastRoot = rest;
    for (final e in groups.entries) {
      _lastDocs[e.key] = e.value;
    }
    _lastHistory
      ..clear()
      ..addAll(nextHistory);
    _lastHistoryLength = chrono.length;
  }

  /// 一個 Firestore 批次最多 500 個操作。第一次存檔會重寫整份訓練歷史
  /// （記憶體裡還不知道雲端有什麼），練滿 500 場的人就會撞到上限 ——
  /// 而 `AppState.saveNow()` 對失敗是靜默的，他會毫無徵兆地停止存檔。
  static const _batchLimit = 450;

  /// 把 [keys] 從 [from] 搬出來成為一份子文件的內容。
  /// 搬走而不是複製 —— 同一個欄位同時存在根文件與子文件，
  /// 就是「一件事有兩個來源」，遲早對不起來。
  Map<String, dynamic> _take(Map<String, dynamic> from, List<String> keys) {
    final out = <String, dynamic>{};
    for (final k in keys) {
      if (from.containsKey(k)) out[k] = from.remove(k);
    }
    return out;
  }

  /// 連續簽到的四個欄位。
  ///
  /// [AppState] 只給得出累計與歷史最長兩個；規格要求的另外兩個
  /// （連續天數、上次簽到日期）本來就是由每日簽到紀錄推算的衍生值，
  /// 這裡就地算出來一起寫進去 —— 讓 Firestore 上的文件符合規格，
  /// 而 [AppState] 不必為了後端而多存兩個它自己不需要的欄位。
  Map<String, dynamic> _checkinDoc(
      Map<String, dynamic> rest, Map<String, dynamic> full) {
    final out = _take(rest, const ['checkInTotal', 'checkInLongest']);
    final records = full['checkInRecords'];
    if (records is! List || records.isEmpty) return out;

    final days = <DateTime>[];
    for (final r in records) {
      if (r is Map && r['date'] is String) {
        final d = DateTime.tryParse(r['date'] as String);
        if (d != null) days.add(DateTime(d.year, d.month, d.day));
      }
    }
    if (days.isEmpty) return out;
    days.sort();

    out['lastCheckInDate'] = days.last.toIso8601String();

    // 自最後一天往回逐日檢視，遇到斷點即停 —— 這正是規格 2026-08-23
    // 改用的逐日推算法，不是「中斷前天數 + 補回天數」那個加法公式。
    final set = {for (final d in days) d.toIso8601String()};
    var streak = 0;
    var cursor = days.last;
    while (set.contains(cursor.toIso8601String())) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    out['streakDays'] = streak;
    return out;
  }

  // ===========================================================================
  // 訓練歷史的形狀轉換
  // ===========================================================================

  /// Firestore **不接受巢狀陣列**，而快照裡一組成績是 `[重量, 次數]`，
  /// 放在 `sets` 陣列裡就成了陣列包陣列，直接寫會被整份拒絕。
  /// 落地時轉成 `{w, r}` 的物件陣列，讀回來再轉回去。
  Map<String, dynamic> _historyToDoc(Map<String, dynamic> h, int seq) => {
        ...h,
        'seq': seq, // 讀回來要照原順序，不能靠文件 ID 的字典序
        'exercises': [
          for (final e in (h['exercises'] as List? ?? const []))
            {
              ...(e as Map<String, dynamic>),
              'sets': [
                for (final s in (e['sets'] as List? ?? const []))
                  {'w': (s as List)[0], 'r': s[1]},
              ],
            },
        ],
      };

  /// 剔除**內容完全相同**的場次。
  ///
  /// 這是替上面那個「寫錯格」缺陷善後的。它在使用者的帳號上留下了 7 份
  /// 一模一樣的文件（全是第一場），修好寫入不會讓它們消失 —— 讀回來得
  /// 認得出那是壞資料，才能在下一次存檔時把多出來的文件刪掉、自己痊癒。
  ///
  /// **只認「完全一樣」。** 同一天早晚各練一場是正常的，同一個時間戳的
  /// 兩場才不可能 —— 結算時間精確到毫秒，真的撞在一起就是同一場被寫了兩次。
  /// 用整份內容比而不是只比時間戳，是因為前者只會漏掉壞資料，
  /// 後者可能誤刪真資料。
  ///
  /// **無法挽回的部分**：被覆蓋掉的那幾場訓練從來沒有寫進雲端，
  /// 這裡救不回來，任何地方都救不回來。
  List<Map<String, dynamic>> _dedupeHistory(List<Map<String, dynamic>> all) {
    final out = <Map<String, dynamic>>[];
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final h in all) {
      final key = '${h['date']}';
      final same = byDate.putIfAbsent(key, () => []);
      if (same.any((k) => _deepEquals(k, h))) continue;
      same.add(h);
      out.add(h);
    }
    return out;
  }

  Map<String, dynamic> _historyFromDoc(Map<String, dynamic> d) {
    final out = Map<String, dynamic>.from(d)..remove('seq');
    out['exercises'] = [
      for (final e in (d['exercises'] as List? ?? const []))
        {
          ...(e as Map<String, dynamic>),
          'sets': [
            for (final s in (e['sets'] as List? ?? const []))
              [(s as Map)['w'], s['r']],
          ],
        },
    ];
    return out;
  }

  /// 文件 ID 補零到六位，讓 `orderBy` 之外的任何列表也能照場次排序。
  String _seqId(int i) => i.toString().padLeft(6, '0');

  bool _same(Map<String, dynamic> a, Map<String, dynamic>? b) {
    if (b == null) return false;
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!_deepEquals(a[k], b[k])) return false;
    }
    return true;
  }

  bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k)) return false;
        if (!_deepEquals(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  // ===========================================================================
  // 清除
  // ===========================================================================

  /// **這是開發與測試用的清除，不是規格要求的「帳號已刪除」。**
  ///
  /// 規格要求的硬刪除涵蓋數十個 collection，還要排除排行榜歷史紀錄
  /// （那份不隨帳號刪除），並且中途失敗不可以留下半殘的資料 ——
  /// 那必須由伺服器端用 Admin SDK 執行，而且要與「使用者已申請刪除帳號」
  /// 這條 Command 共用同一套實作，否則兩邊遲早會跑掉
  /// （新增一個 Aggregate 卻忘了在其中一邊加上）。
  ///
  /// 見 `Firestore-Schema設計.md` 第 6 節。這裡只清本實作寫過的路徑。
  @override
  Future<void> clear() async {
    final batch = _db.batch();

    for (final path in const [
      ['ability', 'state'],
      ['streaks', 'training'],
      ['streaks', 'checkin'],
      ['wallet', 'coins'],
      ['wallet', 'tickets'],
      ['wallet', 'ai_credits'],
      ['membership', 'current'],
    ]) {
      batch.delete(_sub(path[0], path[1]));
    }

    final history = await _root.collection('history').get();
    for (final d in history.docs) {
      batch.delete(d.reference);
    }

    batch.delete(_root);
    await batch.commit();

    _lastRoot = null;
    _lastDocs.clear();
    _lastHistory.clear();
    _lastHistoryLength = -1;
  }
}
