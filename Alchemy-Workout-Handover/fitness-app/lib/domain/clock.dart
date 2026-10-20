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

/// 統一換日時點：使用者當地時區的 **04:00**（`00_全域規範.md`，全專案通用）。
/// 當地 00:00–03:59 的行為一律計入前一個自然日。
///
/// **住在這裡而不是 `AppState`**：假資料產生器與純函式也要用同一套換日規則，
/// 而它們構不到 `AppState`。放在那裡的後果是它們改用原始日曆日 ——
/// 兩套「今天」在當地 00:00–03:59 會差一天，而那段時間以外完全看不出來。
DateTime businessDate(DateTime now) {
  final s = now.subtract(const Duration(hours: 4));
  return DateTime(s.year, s.month, s.day);
}

/// 這一刻所屬日曆週的起點（週一，日期不含時分）。週界是週一 04:00 ——
/// 與週排行榜（`periodOf`）同一條，建立在 [businessDate] 之上。
///
/// 能力值的每週升格上限用它判斷「這一週」；以日期為鍵，同一週的任何時刻都算出同一個值。
DateTime businessWeekStart(DateTime now) {
  final d = businessDate(now);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}
