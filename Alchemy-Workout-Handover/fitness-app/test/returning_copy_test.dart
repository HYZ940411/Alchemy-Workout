// 每次重開都被當成第一次來的人。
//
// 登入頁寫著「開始吧 / 選一種方式**建立帳號**，只要一分鐘」。那是給
// 第一次來的人看的，而 `AuthGate` 在未登入時一律畫這一頁 —— 於是
// 已經有帳號的人每次重開都被告知要「建立帳號」，第一個念頭是
// 「我的帳號不見了？」。
//
// 這是 `[BE-04]` 之前就留下的待辦。當時的註解寫著：
//   「等真的有『既有帳號登入』那條路徑時，再依情境分兩種文案。」
// 那條路徑在 `[BE-04]` 就存在了，只是沒人回頭處理。
//
// 判斷來自裝置層的小記事本（`deviceStore`），**不綁 uid** ——
// 登入頁必須在還不知道使用者是誰的時候回答這個問題。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/screens/signup/login_screen.dart';

Future<void> _pump(WidgetTester t, {required bool returning}) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LoginPane(
        onPhone: (_) {},
        onThirdParty: (_) {},
        returning: returning,
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('登入頁的兩種文案', () {
    testWidgets('第一次來：開始吧', (t) async {
      await _pump(t, returning: false);
      expect(find.text('開始吧'), findsOneWidget);
      expect(find.text('選一種方式建立帳號，只要一分鐘'), findsOneWidget);
      expect(find.text('歡迎回來'), findsNothing);
    });

    testWidgets('回訪：歡迎回來，而且不再叫他建立帳號', (t) async {
      await _pump(t, returning: true);
      expect(find.text('歡迎回來'), findsOneWidget);
      expect(find.text('開始吧'), findsNothing);
      expect(find.textContaining('建立帳號'), findsNothing,
          reason: '已經有帳號的人被叫去「建立帳號」，會以為帳號不見了');
    });

    testWidgets('預設是「第一次來」—— 猜錯要選傷害小的那一邊', (t) async {
      // 對老手說「開始吧」只是囉嗦；對新手說「歡迎回來」會讓他
      // 以為自己忘了舊帳號。
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LoginPane(onPhone: (_) {}, onThirdParty: (_) {}),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('開始吧'), findsOneWidget);
    });
  });

  group('裝置層的記事本', () {
    test('沒記過就是沒登入過', () async {
      expect(await hasSignedInBefore(MemoryStore()), isFalse);
    });

    test('記了之後讀得回來', () async {
      final s = MemoryStore();
      await markSignedIn(s);
      expect(await hasSignedInBefore(s), isTrue);
    });

    test('讀壞了當作沒登入過，不拋例外', () async {
      final s = MemoryStore();
      await s.save({'signedIn': '這不是布林'});
      expect(await hasSignedInBefore(s), isFalse);
    });

    test('它不綁 uid —— 登入頁問的時候還不知道使用者是誰', () {
      // 這條釘的是設計而不是行為：`deviceStore()` 不收任何參數。
      expect(deviceStore, isA<Store Function()>());
    });
  });
}
