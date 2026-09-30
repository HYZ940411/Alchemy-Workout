/// 非 Web 平台上沒有「JS 物件」這回事 —— 兩支一律回空值，
/// 由 [describeError] 走 Dart 那一套。
String? jsErrorText(Object e) => null;

Object? jsBoxedValue(Object e) => null;
