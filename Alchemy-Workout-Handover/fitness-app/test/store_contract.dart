// 每一個 [Store] 實作都要通過的同一份契約。
//
// 檔案版與瀏覽器版是同一份契約的兩個實作。行為只要有一處不一致，
// 「Web 版跟手機版表現不一樣」就會變成一類永遠查不完的 bug ——
// 而且會出現在存讀這種最不該有意外的地方。
//
// 這支不是測試檔（沒有 main），是給兩邊的測試共用的一組斷言：
//   - test/persistence_test.dart      在 VM 上跑 FileStore
//   - test/store_web_test.dart        在 Chrome 上跑 WebStore
//
// 兩邊呼叫同一個 [runStoreContract]。少了共用，兩份斷言遲早會分岔，
// 而分岔的那一刻沒有人會知道。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';

/// 直接把一段原始文字寫進底層儲存，繞過 [Store.save]。
/// 「存檔壞掉」這條路徑只能這樣驗 —— 正常路徑寫不出壞資料。
typedef WriteRaw = Future<void> Function(String text);

/// 讀回底層實際存著的原始文字。回傳 null 代表那個位置是空的。
typedef ReadRaw = Future<String?> Function();

void runStoreContract(
  String name, {
  required Store Function() make,
  required WriteRaw writeRaw,
  required ReadRaw readRaw,
}) {
  group('$name：儲存契約', () {
    test('沒存過回傳 null，不是錯誤', () async {
      expect(await make().load(), isNull);
    });

    test('存了讀得回來', () async {
      final s = make();
      await s.save({'v': 2, 'coins': 99});
      expect((await s.load())!['coins'], 99);
    });

    test('後存的蓋掉先存的', () async {
      final s = make();
      await s.save({'v': 2, 'coins': 1});
      await s.save({'v': 2, 'coins': 2});
      expect((await s.load())!['coins'], 2);
    });

    test('空內容等同沒存過', () async {
      await writeRaw('   ');
      expect(await make().load(), isNull);
    });

    test('內容壞掉：丟錯誤，不當成沒存過', () async {
      await writeRaw('{壞掉的 json');
      await expectLater(make().load(), throwsA(isA<StoreLoadException>()));
    });

    test('JSON 合法但不是一份存檔，同樣視為壞掉', () async {
      await writeRaw('[1, 2, 3]');
      // 訊息要說得出是**哪一種**壞法。
      //
      // 只斷言「丟了 StoreLoadException」不夠：把型別檢查拿掉之後，
      // 回傳 List 給宣告為 Map 的函式會丟型別錯誤，剛好被同一個 catch
      // 接住、包成同一種例外 —— 測試分不出差別，而使用者拿到的是一句
      // 看不懂的 TypeError。
      await expectLater(
        make().load(),
        throwsA(isA<StoreLoadException>()
            .having((e) => e.reason, 'reason', contains('不是一份存檔'))),
      );
    });

    test('壞掉的原檔改名保留，不直接刪掉', () async {
      const bad = '{壞掉的 json';
      await writeRaw(bad);
      try {
        await make().load();
        fail('應該要丟錯誤');
      } on StoreLoadException catch (e) {
        expect(e.backupPath, isNotNull,
            reason: '使用者有權知道他的東西被搬到哪去了');
        expect(await readRaw(), isNull,
            reason: '原位置要清空，否則下次開啟又壞一次');
      }
    });

    test('壞掉之後照常重新開始', () async {
      await writeRaw('{壞掉的 json');
      final s = make();
      // **要等它跑完**：載入失敗會把壞掉的原檔搬走，沒等就存下去的話，
      // 那次搬移會把剛存好的檔一起搬掉 —— 這是測試自己的競態，不是實作的。
      await expectLater(s.load(), throwsA(isA<StoreLoadException>()));
      await s.save({'v': 2, 'coins': 7});
      expect((await s.load())!['coins'], 7);
    });

    test('clear 之後回到沒存過', () async {
      final s = make();
      await s.save({'v': 2});
      await s.clear();
      expect(await s.load(), isNull);
    });

    test('沒存過也 clear 得動，不丟錯', () async {
      await make().clear();
      expect(await make().load(), isNull);
    });

    test('中文與巢狀結構原樣存讀', () async {
      final s = make();
      final data = {
        'v': 2,
        'displayName': '你',
        'points': {'chest': 486, 'core': 190},
        'history': [
          {'planName': '推日：胸肩三頭', 'volume': 3240.5}
        ],
      };
      await s.save(data);
      final back = (await s.load())!;
      expect(back['displayName'], '你');
      expect((back['points'] as Map)['chest'], 486);
      expect((back['history'] as List).first['volume'], 3240.5);
    });
  });
}
