/// 非 Web 平台上沒有「JS 物件」這回事 —— 一律回空值，
/// 由 [describeError] 退回 Dart 那一套。
String? jsErrorText(Object e) => null;
