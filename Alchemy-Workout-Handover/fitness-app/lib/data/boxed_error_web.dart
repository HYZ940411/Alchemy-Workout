import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// 把一個 **JS 例外**變成看得懂的一句話。
///
/// ## 為什麼不能用通用轉換
///
/// 從 JS Promise 拒絕回來的東西是 JS 物件，`toString()` 只給出
/// 「Dart exception thrown from converted Future. Use the properties
/// 'error' to fetch the boxed error…」。照那句話取出 `error` 之後，
/// 裡面是一個 JS `Error` —— 而 `Error` 的 `message` 與 `stack`
/// **不是可列舉屬性**，所以 `dartify()` 只會給出一個空物件 `{}`。
///
/// 使用者 2026-09-30 第四輪拿到的就是 `失敗：{}` ——
/// 拆是拆開了，拆出來的東西還是沒有內容。
///
/// 所以要**點名去讀**那幾個欄位。
String? jsErrorText(Object e) {
  try {
    final obj = _asObject(e);
    if (obj == null) return null;

    // 照那句樣板話的指示，先取出被裝箱的那一層。
    final inner = obj.has('error') ? _asObject(obj['error']) : null;
    final target = inner ?? obj;

    // Firestore 的錯誤帶 `code`（例如 permission-denied、
    // resource-exhausted），JS 的 Error 帶 `name` 與 `message`。
    final parts = <String>[];
    for (final key in const ['code', 'name', 'message']) {
      final v = _readString(target, key);
      if (v != null && v.isNotEmpty) parts.add('$key=$v');
    }
    if (parts.isNotEmpty) return parts.join('　');

    // 什麼都讀不到時，至少給出它自己的字串形式 ——
    // **但不要再給那句樣板話**，那等於沒說。
    final raw = target.toString();
    if (raw.contains('converted Future')) return null;
    return raw.isEmpty ? null : raw;
  } catch (_) {
    return null;
  }
}

/// `is JSObject` 在 JS 互通型別上不保證跨平台一致，官方要求用 `isA`。
JSObject? _asObject(Object? e) {
  if (e == null) return null;
  final any = e as JSAny?;
  if (any == null || !any.isA<JSObject>()) return null;
  return any as JSObject;
}

String? _readString(JSObject o, String key) {
  if (!o.has(key)) return null;
  final v = o[key];
  if (v == null) return null;
  final s = v.toString();
  return (s == 'null' || s == 'undefined') ? null : s;
}
