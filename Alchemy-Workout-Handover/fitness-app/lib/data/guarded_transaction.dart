import 'package:cloud_firestore/cloud_firestore.dart';

import 'http_error.dart';

/// 跑一筆交易，**判斷留在交易裡，例外丟在交易外面**。
///
/// ## 為什麼不直接 `runTransaction`
///
/// 兩個坑，都踩過（`PROGRESS.md` 3F／3G）：
///
/// 1. **守衛靜靜 `return`**：交易正常結束 → `Future` 正常完成 → 呼叫端記成
///    「成功」，而雲端一個字都沒變。人數已滿、隊伍不存在，都長這樣。
/// 2. **守衛在交易裡 `throw`**：在 Web 上，Dart 例外一旦穿過 JS 的 Promise 邊界，
///    訊息全失，只剩「Dart exception thrown from converted Future」。
///    連續六輪都讀不出原因。
///
/// 所以 [body] **不丟例外**：判斷不成立就回傳一句原因（成立回 `null`），
/// 交易跑完、回到 Dart 這一側之後才由這裡丟 [StateError]。
/// 交易裡只有「讀、判斷、寫」，沒有任何東西需要穿過邊界。
///
/// 競爭條件是真的（人數上限、計數器），**不要拿掉交易** ——
/// 要改的只有「失敗怎麼說出口」。
///
/// 要帶出交易裡算的值，用 closure 變數，不要靠 `runTransaction` 的回傳值。
/// 交易的讀取壞掉、改走「一般讀取＋批次寫入」的次數與最近一次的說明。
/// 設定頁的開發者模式看得到 —— 這條路沒有交易的併發保證，不能悄悄地用。
int fallbackCount = 0;
String? lastFallbackNote;

Future<void> guardedTransaction(
  FirebaseFirestore db,
  String what,
  Future<String?> Function(Transaction tx) body,
) async {
  String? refused;
  // 失敗發生在哪一段：交易根本沒開始、body 裡（讀或寫）、還是 body 做完等提交時。
  // 2026-10-17 所有交易都失敗，錯誤只有一個沒有內容的物件，連是哪一段壞的都看不出來。
  var phase = '交易還沒開始（還沒進到 body）';
  String? readingPath;
  try {
    await db.runTransaction<void>((tx) async {
      // 交易可能重跑；每一輪都重新決定，以最後一輪為準。
      phase = '正在跑 body（還沒碰到 tx）';
      refused = await body(
        _TrackedTransaction(tx, (p, {String? reading}) {
          phase = p;
          if (reading != null) readingPath = reading;
        }),
      );
      phase = 'body 已做完，等伺服器提交';
    });
  } catch (e) {
    // 交易自己的讀取壞了（2026-10-17：網頁上 `tx.get` 丟出一個沒有內容的物件，
    // 而一般讀取同一份文件是好的）：改用「一般讀取 ＋ 一次批次寫入」把同一個 body 跑一遍。
    // 判斷邏輯一字不改，只是少了「讀到提交之間沒人動過」的保證 ——
    // 這只在交易的讀取壞掉時才走，平常照舊用交易。
    if (readingPath != null && phase.startsWith('tx.get 讀取')) {
      final first = '階段：$phase；錯誤類型：${e.runtimeType}${_detail(e)}';
      try {
        final batchTx = _BatchTransaction(db);
        final why = await body(batchTx);
        if (why == null) await batchTx.commit();
        fallbackCount++;
        lastFallbackNote = '$what：交易的讀取壞了（$first），已改用一般讀取＋批次寫入完成';
        if (why != null) throw StateError('$what：$why');
        return;
      } on StateError {
        rethrow; // 守衛不成立的正常拒絕，照原樣說出口
      } catch (e2) {
        throw StateError(
          '$what：交易失敗（$first）；改用一般讀取也失敗'
          '（${e2.runtimeType}）${_detail(e2)}',
        );
      }
    }
    throw StateError(
      '$what：交易失敗（階段：$phase；錯誤類型：${e.runtimeType}）'
      '${_detail(e)}',
    );
  }
  final why = refused;
  if (why != null) throw StateError('$what：$why');
}

String _detail(Object e) {
  final d = describeError(e);
  return d.isEmpty ? '' : '　$d';
}

/// 把 [Transaction] 包一層，**只記錄現在做到哪**，行為完全照轉。
///
/// body 裡的失敗原本只能說「正在跑 body」，分不出是讀文件、轉換讀到的資料、還是寫入
/// （2026-10-17：所有交易都在 body 裡失敗，錯誤是一個空物件）。
class _TrackedTransaction implements Transaction {
  final Transaction _tx;
  final void Function(String, {String? reading}) _mark;
  _TrackedTransaction(this._tx, this._mark);

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    _mark(
      'tx.get 讀取 ${documentReference.path}',
      reading: documentReference.path,
    );
    final snap = await _tx.get(documentReference);
    _mark('tx.get 已讀回 ${documentReference.path}，之後是轉換資料與判斷');
    return snap;
  }

  @override
  Transaction update(
    DocumentReference documentReference,
    Map<Object, Object?> data,
  ) {
    final what = '${documentReference.path}（欄位：${data.keys.join('、')}）';
    _mark('tx.update 正在寫入 $what');
    _tx.update(documentReference, data);
    _mark('tx.update 已交給交易，還沒提交：$what');
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    _mark('tx.set 寫入 ${documentReference.path}');
    _tx.set(documentReference, data, options);
    _mark('tx.set 已交給交易（還沒提交）');
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    _mark('tx.delete 刪除 ${documentReference.path}');
    _tx.delete(documentReference);
    _mark('tx.delete 已交給交易（還沒提交）');
    return this;
  }
}

/// 「一般讀取＋批次寫入」版的 [Transaction]：讀直接問伺服器，寫先收集、最後一次送出。
/// 只在交易自己的讀取壞掉時當退路用（見 [guardedTransaction]）。
class _BatchTransaction implements Transaction {
  final WriteBatch _batch;
  _BatchTransaction(FirebaseFirestore db) : _batch = db.batch();

  Future<void> commit() => _batch.commit();

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) => documentReference.get(const GetOptions(source: Source.server));

  @override
  Transaction update(
    DocumentReference documentReference,
    Map<Object, Object?> data,
  ) {
    _batch.update(documentReference, data);
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    _batch.set(documentReference, data, options);
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    _batch.delete(documentReference);
    return this;
  }
}
