@TestOn('browser')
library;

// Web 版真的開得起來嗎。
//
// 這支在**真的瀏覽器**裡把整個 App 跑起來，走過五個分頁。
// 一般的 `flutter test` 跑在 VM 上，證明不了 Web ——
// dart:io、檔案路徑、平台專屬 API 這些差異只有在瀏覽器裡才會現形。
//
//   flutter test --platform chrome test/web_smoke_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/data/store_web.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

/// 等畫面靜下來。
///
/// **骨架屏的閃爍是永不停止的動畫**，`pumpAndSettle` 對它必然逾時 ——
/// 那是動畫的性質，不是 App 的毛病。逾時就改推固定幾幀。
/// （這條在 VM 的畫面爬蟲上已經踩過一次，Web 上同樣成立。）
Future<void> settle(WidgetTester t) async {
  try {
    await t.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  } catch (_) {
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> boot(WidgetTester t, {Store? store}) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(FitnessApp(store: store));
  await settle(t);
}

void main() {
  testWidgets('App 在瀏覽器裡開得起來', (t) async {
    await boot(t);
    expect(t.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('五個分頁都切得過去，不丟例外', (t) async {
    // 攔下框架回報的錯誤。瀏覽器平台的測試輸出會把
    //「See exception logs above」的那個 above 整段吞掉，
    // 不自己攔，失敗時看不到任何線索。
    final caught = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => caught.add('${d.exception}');

    await boot(t);
    // 例外訊息自己撈出來塞進 reason —— 瀏覽器平台的測試輸出
    // 會把「See exception logs above」的那個 above 吞掉，
    // 只斷言 isNull 的話，失敗時看不到任何線索。
    final problems = <String>[];
    for (final tab in ['社群', '訓練', '商店', '我的', '首頁']) {
      try {
        // 「訓練」在分頁列上沒有文字，是中央那顆圖示按鈕。
        final target = tab == '訓練'
            ? find.byIcon(Icons.fitness_center)
            : find.text(tab);
        expect(target, findsWidgets, reason: '找不到「$tab」的入口');
        await t.tap(target.last);
        await settle(t);
      } catch (e) {
        problems.add('切到「$tab」時：$e');
        continue;
      }
      final ex = t.takeException();
      if (ex != null) problems.add('切到「$tab」之後：$ex');
    }
    // **先還原再斷言。** 反過來的話框架會直接丟
    //「A test overrode FlutterError.onError but ... failed to return it」，
    // 把真正的錯誤蓋掉 —— 我第一次就是這樣寫的。
    FlutterError.onError = prev;

    final all = [...problems, ...caught];
    // 直接印出來。瀏覽器平台的 reporter 只會給一句
    //「See exception logs above」，而那個 above 是空的。
    for (final p in all) {
      // ignore: avoid_print
      print('【WEB 問題】$p');
    }
    expect(all, isEmpty, reason: '共 ${all.length} 個，詳見上面的【WEB 問題】');
  });

  testWidgets('中文字型畫得出來 —— 不是一排豆腐', (t) async {
    await boot(t);
    // 找得到中文文字節點，且它有實際尺寸（字型載不到時寬度會塌掉）。
    final f = find.text('首頁');
    expect(f, findsWidgets);
    final box = t.renderObject<RenderBox>(f.last);
    expect(box.size.width, greaterThan(0));
    expect(box.size.height, greaterThan(0));
  });

  testWidgets('進度存得進 localStorage，重開讀得回來', (t) async {
    final store = WebStore(key: 'web_smoke_state.json');
    await store.clear();
    addTearDown(store.clear);

    await boot(t, store: store);
    final s = AppScope.of(t.element(find.byType(Scaffold).first));
    s.coins = 12345;
    s.notifyListeners();               // 排一次 300ms 的延遲存檔
    await t.pump(const Duration(seconds: 1));
    await s.saveNow();                 // 確保寫完再讀

    final saved = await store.load();
    expect(saved, isNotNull, reason: '瀏覽器版沒把狀態寫進 localStorage');
    expect(saved!['coins'], 12345);
  });
}
