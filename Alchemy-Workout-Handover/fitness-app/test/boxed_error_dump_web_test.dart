@TestOn('browser')
library;

// 讀不到 code／name／message 的 JS 錯誤物件，要把內容整個倒出來。
//
// 2026-10-17 隊長核准入隊，寫入報告只有「失敗：[object Object]」—— 原本的拆箱只認那三個欄位，
// 都沒有就回空值，最後退回 `toString()` 的 `[object Object]`，等於沒說。
//
//   flutter test --platform chrome test/boxed_error_dump_web_test.dart

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/http_error.dart';

void main() {
  test('沒有 code／name／message 的物件：倒出欄位，不是 [object Object]', () {
    final o = JSObject();
    o['reason'] = 'quota'.toJS;
    o['detail'] = 42.toJS;
    final text = describeError(o);
    expect(text, isNot('[object Object]'));
    expect(text, contains('reason'));
    expect(text, contains('quota'));
    expect(text, contains('42'));
  });

  test('有 code 的照舊（Firestore 的錯誤）', () {
    final o = JSObject();
    o['code'] = 'permission-denied'.toJS;
    o['message'] = 'Missing or insufficient permissions.'.toJS;
    final text = describeError(o);
    expect(text, contains('permission-denied'));
    expect(text, isNot(contains('物件')), reason: '有欄位可讀就不必倒整個物件');
  });

  test('空物件也不會炸', () {
    expect(() => describeError(JSObject()), returnsNormally);
  });
}
