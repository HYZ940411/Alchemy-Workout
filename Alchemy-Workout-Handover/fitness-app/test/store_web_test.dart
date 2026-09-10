@TestOn('browser')
library;

// 瀏覽器版的儲存後端。**必須在真的瀏覽器裡跑**：
//   flutter test --platform chrome test/store_web_test.dart
//
// VM 上的測試碰不到 localStorage，所以這一支不會出現在一般的
// `flutter test` 結果裡 —— 它不是被跳過，是被排除在那個平台之外。

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/data/store_web.dart';

import 'store_contract.dart';

const kKey = 'contract_test_state.json';

void clearAll() {
  final ls = web.window.localStorage;
  // 連同備份鍵一起清 —— 上一個測試留下的 `.bad.<時戳>` 會累積。
  final doomed = <String>[];
  for (var i = 0; i < ls.length; i++) {
    final k = ls.key(i);
    if (k != null && k.startsWith(kKey)) doomed.add(k);
  }
  for (final k in doomed) {
    ls.removeItem(k);
  }
}

void main() {
  setUp(clearAll);
  tearDown(clearAll);

  runStoreContract(
    'WebStore',
    make: () => WebStore(key: kKey),
    writeRaw: (t) async => web.window.localStorage.setItem(kKey, t),
    readRaw: () async => web.window.localStorage.getItem(kKey),
  );

  group('WebStore 專屬', () {
    test('壞掉的內容真的搬到備份鍵，讀得回來', () async {
      const bad = '{壞掉的 json';
      web.window.localStorage.setItem(kKey, bad);
      try {
        await WebStore(key: kKey).load();
        fail('應該要丟錯誤');
      } on StoreLoadException catch (e) {
        expect(e.backupPath, isNotNull);
        expect(web.window.localStorage.getItem(e.backupPath!), bad,
            reason: '搬走不等於丟掉 —— 使用者的資料還在');
      }
    });

    test('兩個不同的鍵互不干擾', () async {
      final a = WebStore(key: '$kKey.a');
      final b = WebStore(key: '$kKey.b');
      await a.save({'v': 2, 'coins': 1});
      expect(await b.load(), isNull);
      await b.save({'v': 2, 'coins': 2});
      expect((await a.load())!['coins'], 1);
      await a.clear();
      await b.clear();
    });
  });
}
