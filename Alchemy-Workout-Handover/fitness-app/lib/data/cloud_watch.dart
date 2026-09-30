import 'dart:async';

/// 把幾條雲端監聽併成一條「有東西變了」的訊號（`[BE-16]`）。
///
/// ## 為什麼訊號不帶內容
///
/// 收到訊號的人去跑**既有的重讀路徑**（`AppState.refreshInbound()`），
/// 而不是各自再解析一次文件。解析與併入那一層
/// （`applyCloudConversations`／`applyCloudTeam`／`applyCloudBonds`…）
/// 已經被測過了，複製一份只會讓兩份慢慢長不一樣 —— 而這個專案的
/// bug 有一整排就是「同一個決定寫在兩個地方，只有一處做對」。
///
/// 代價是每次變動多一趟查詢。以目前的規模這是划算的交換：
/// 讀取層只有一份，而那一份已經在線上跑過了。
///
/// ## 每條來源都丟掉第一筆
///
/// Firestore 的訂閱一掛上就會先送出當下的快照。那份資料登入時剛讀過，
/// 不丟掉的話每次開始訂閱都會白跑一趟重讀 —— 而重讀又會 `notifyListeners`，
/// 整個畫面重建一次。丟掉第一筆之後，訊號真的只代表「**變了**」。
///
/// ## 錯誤不往外傳
///
/// 某一條被安全規則擋下或斷線，不該讓其他幾條跟著結束。
/// 這裡吞掉個別來源的錯誤，但**不吞掉「完全沒有訊號」這件事** ——
/// 那由 `AppState.cloudWatchReport` 記給開發者模式看。
Stream<void> mergeWatches(List<Stream<void>> sources) {
  late final StreamController<void> out;
  final subs = <StreamSubscription<void>>[];

  void start() {
    for (final s in sources) {
      // skip(1)：丟掉掛上訂閱時的那份現況快照。
      subs.add(s.skip(1).listen(
            (_) => out.add(null),
            onError: (Object _) {/* 一條壞掉不影響其他條 */},
            cancelOnError: false,
          ));
    }
  }

  Future<void> stop() async {
    for (final s in subs) {
      await s.cancel();
    }
    subs.clear();
  }

  out = StreamController<void>(onListen: start, onCancel: stop);
  return out.stream;
}
