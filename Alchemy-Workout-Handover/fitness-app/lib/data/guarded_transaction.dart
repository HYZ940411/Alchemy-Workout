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
    // 失敗在交易自己的讀取：再用「一般讀取」讀同一份文件，看是不是只有交易的讀取壞了。
    // 交易的讀取走一條獨立的單次請求；一般讀取走長連線。兩者結果不同，
    // 就知道問題在那條單次請求的路上，而不是文件、規則或我們的程式。
    final probe = (readingPath != null && phase.startsWith('tx.get 讀取'))
        ? '　［對照：${await _probe(db, readingPath!)}］'
        : '';
    throw StateError(
      '$what：交易失敗（階段：$phase；錯誤類型：${e.runtimeType}）'
      '${_detail(e)}$probe',
    );
  }
  final why = refused;
  if (why != null) throw StateError('$what：$why');
}

/// 用一般讀取讀同一份文件，各限 8 秒，回報成敗。診斷用，只在交易自己的讀取失敗時才跑。
Future<String> _probe(FirebaseFirestore db, String path) async {
  final out = <String>[];
  Future<void> one(String label, Future<void> Function() f) async {
    try {
      await f().timeout(const Duration(seconds: 8));
      out.add('$label：成功');
    } catch (e) {
      out.add('$label：失敗（${e.runtimeType}）${describeError(e)}');
    }
  }

  await one(
    '一般讀取・伺服器',
    () => db.doc(path).get(const GetOptions(source: Source.server)),
  );
  await one('一般讀取・預設', () => db.doc(path).get());
  return out.join('；');
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
