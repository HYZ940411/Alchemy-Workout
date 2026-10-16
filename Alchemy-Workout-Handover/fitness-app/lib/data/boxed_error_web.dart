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

    // code／name／message 都沒有：把這個物件**整個倒出來**看有什麼。
    // 2026-10-17 隊長核准入隊，寫入報告只有「失敗：[object Object]」，
    // 前面那三個欄位一個都讀不到，連是什麼東西都看不出來。
    final dump = _dumpObject(target);
    if (dump != null) return '物件 $dump';

    // 什麼都讀不到時回空值，讓 [describeError] 去走 Dart 那一側 ——
    // **不要回那句樣板話，也不要回 `[object Object]`**，
    // 那兩種都等於沒說。使用者 2026-09-30 第五輪拿到的就是後者。
    final raw = target.toString();
    if (raw.contains('converted Future')) return null;
    if (raw == '[object Object]' || raw == '{}') return null;
    return raw.isEmpty ? null : raw;
  } catch (_) {
    return null;
  }
}

/// 把一個 JS 物件的內容倒成一句字：建構子名稱 ＋ JSON ＋ 全部自有屬性名。
/// 全部讀不到才回空值。整段包在 try 裡，倒不出來不能讓診斷本身炸掉。
String? _dumpObject(JSObject o) {
  final parts = <String>[];
  try {
    final ctor = o['constructor'];
    if (ctor != null) {
      final name = (ctor as JSObject)['name'];
      if (name != null) parts.add('類型=$name');
    }
  } catch (_) {}
  try {
    final json = globalContext['JSON'] as JSObject;
    final s = json.callMethod<JSAny?>('stringify'.toJS, o);
    final str = s?.toString();
    if (str != null && str.isNotEmpty && str != 'undefined' && str != '{}') {
      parts.add('JSON=$str');
    }
  } catch (_) {}
  try {
    final objectCtor = globalContext['Object'] as JSObject;
    final names =
        objectCtor.callMethod<JSArray<JSString>>('getOwnPropertyNames'.toJS, o);
    final list = [for (final n in names.toDart) n.toDart];
    if (list.isNotEmpty) parts.add('欄位=${list.join(',')}');
  } catch (_) {}
  return parts.isEmpty ? null : parts.join('　');
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

/// 取出被裝箱的那個值，**原樣交回 Dart 這一側**。
///
/// 裝在裡面的很可能就是一個 Dart 物件（例如 `FirebaseException` 或我們
/// 自己丟的 `StateError`）。從 JS 那一側看它是個沒有屬性的物件，
/// `toString()` 給出 `[object Object]` —— 但只要交回 Dart，
/// 字串插值就會呼叫到它真正的 `toString()`。
///
/// 使用者 2026-09-30 第四、五輪分別拿到 `{}` 與 `[object Object]`，
/// 兩次都是因為我一直用 JS 的方式去讀一個 Dart 物件。
Object? jsBoxedValue(Object e) {
  try {
    final obj = _asObject(e);
    if (obj == null || !obj.has('error')) return null;
    final v = obj['error'];
    if (v == null) return null;
    return v as Object;
  } catch (_) {
    return null;
  }
}
