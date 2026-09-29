// 被裝箱的錯誤要拆出來看。
//
// 在 Web 上，Dart 的例外一旦穿過 JS 的 Promise 邊界（Firestore 的
// `runTransaction` 內部就是這樣做的），`toString()` 會變成一句樣板話：
//
//   Error: Dart exception thrown from converted Future. Use the
//   properties 'error' to fetch the boxed error and 'stack' to
//   recover the stack trace.
//
// **真正的錯誤裝在 `error` 這個屬性裡** —— 那句話自己就寫著怎麼拿，
// 而我沒去拿。使用者 2026-09-30 連續兩輪拿到的都是這句：
// 儀器有在報，報的內容卻等於沒報。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/http_error.dart';

/// 模擬 JS interop 那一層的包裝：`toString()` 沒有內容，
/// 真正的錯誤在 `error` 屬性上。
class _Boxed {
  final Object error;
  _Boxed(this.error);

  @override
  String toString() =>
      'Error: Dart exception thrown from converted Future. '
      "Use the properties 'error' to fetch the boxed error.";
}

void main() {
  test('沒有裝箱的照原樣', () {
    expect(describeError(StateError('recover: 這段關係不是已解除')),
        contains('不是已解除'));
    expect(describeError('純字串'), '純字串');
  });

  test('拆得開一層', () {
    final e = _Boxed(StateError('recover: 已超過 3 天'));
    expect(e.toString(), contains('converted Future'), reason: '前提：原本看不到內容');
    expect(describeError(e), contains('已超過 3 天'));
    expect(describeError(e), isNot(contains('converted Future')));
  });

  test('拆得開兩層', () {
    final e = _Boxed(_Boxed(StateError('最裡面那一句')));
    expect(describeError(e), contains('最裡面那一句'));
  });

  test('自己指向自己不會無窮遞迴', () {
    expect(describeError(_SelfRef()), contains('自己'));
  });

  test('兩個互指的環也停得下來 —— 身分比對擋不住這種', () {
    final a = _Cycle('甲');
    final b = _Cycle('乙');
    a.other = b;
    b.other = a;
    // 停得下來就好；停在哪一層不是重點。
    expect(describeError(a), anyOf(contains('甲'), contains('乙')));
  });

  test('拆箱層數有上限，不是拆到停不下來為止', () {
    // 疊七層，上限是五層 —— 拆不到最底下那一句。
    Object e = StateError('最底下');
    for (var i = 0; i < 7; i++) {
      e = _Boxed(e);
    }
    expect(describeError(e), isNot(contains('最底下')));
    expect(describeError(e, depth: 99), contains('最底下'));
  });

  test('取屬性會炸的東西不會把報告一起弄壞', () {
    expect(describeError(_Throws()), contains('取不到'));
  });
}

class _SelfRef {
  Object get error => this;
  @override
  String toString() => '指向自己';
}

class _Throws {
  Object get error => throw UnimplementedError();
  @override
  String toString() => '這個東西的 error 取不到';
}

/// 兩個互相指向對方 —— `boxed != e` 擋不住這種。
class _Cycle {
  final String name;
  Object? other;
  _Cycle(this.name);
  Object? get error => other;
  @override
  String toString() => name;
}
