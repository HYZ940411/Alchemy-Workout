/// 展示時鐘
///
/// 這個 App 有一個可以往前推的時鐘，讓退步、到期、結算、換日這些
/// 掛在時間上的規則能當場演出來。凡是**判定或寫入狀態**的地方，
/// 取時間一律走 [appNow]，不直接呼叫 `DateTime.now()`。
///
/// 做成模組層級的函式而不是 AppState 的方法，是因為漏掉的那些點
/// 幾乎都在拿不到 AppState 的地方 —— 畫面裡算「幾天前」的靜態小工具、
/// 純函式的判定。它們構不到 AppState，就會伸手去拿系統時間，
/// 於是同一個畫面上有兩個時鐘。把時鐘放在構得到的地方，這一類漏洞才不會再長回來。
library;

Duration _offset = Duration.zero;

/// 目前的展示時間。
DateTime appNow() => DateTime.now().add(_offset);

/// 目前的偏移量。
Duration get appClockOffset => _offset;

set appClockOffset(Duration v) => _offset = v;

/// 把時鐘推回原點。測試之間必須歸零，否則偏移量會跨測試累積。
void resetAppClock() => _offset = Duration.zero;
