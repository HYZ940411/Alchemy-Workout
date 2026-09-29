import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// 從一個 **JS 物件**上取出 `error` 屬性。
///
/// Dart 的動態存取（`(e as dynamic).error`）只對 Dart 物件有效；
/// 從 JS Promise 拒絕回來的那個東西是 JS 物件，動態存取會直接
/// `NoSuchMethodError`，於是 [describeError] 永遠退回那句樣板話。
///
/// 使用者 2026-09-30 連三輪拿到的都是
/// 「Dart exception thrown from converted Future. Use the properties
/// 'error' to fetch the boxed error…」—— 那句話寫著怎麼拿，
/// 而 Dart 這一側拿不到，因為用錯了取值方式。
Object? jsBoxedError(Object e) {
  try {
    // `is JSObject` 在 JS 互通型別上不保證跨平台一致，官方要求用 `isA`。
    final any = e as JSAny?;
    if (any == null || !any.isA<JSObject>()) return null;
    final obj = any as JSObject;
    if (!obj.has('error')) return null;
    final boxed = obj['error'];
    if (boxed == null) return null;
    // 裡面可能是 Dart 物件（被裝箱的原始例外），也可能還是 JS 物件。
    return boxed.dartify() ?? boxed;
  } catch (_) {
    return null;
  }
}
