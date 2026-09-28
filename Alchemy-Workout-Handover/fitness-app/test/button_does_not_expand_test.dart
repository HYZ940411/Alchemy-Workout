// `AppButton` 在「有界但寬鬆」的約束下不可以把自己撐滿（2026-09-28）。
//
// 使用者點「作答教官測驗」之後看到**一整片橘色**，寫著「還有 23 題未作答」，
// 一題都答不了。
//
// 量出來：交卷鍵佔了 16,16 → 377,836（幾乎整個畫面），
// 而題目清單的**高度是 0** —— ListView 沒有高度就不會建任何一個子項，
// 二十三題一題都沒畫出來。
//
// 根因不在那一頁，在 `AppButton`：內層 `Container` 帶著
// `alignment: Alignment.center`，而**帶 alignment 的 Container 內部就是
// 一個 widthFactor／heightFactor 皆為空的 `Align`** —— 那種 `Align`
// 在有界寬鬆的約束下會撐到最大。
//
// 在 `Column`／`Row`／`ListView` 裡看不出來（主軸無界，`Align` 會縮），
// 所以這個缺陷一直藏著，直到有人把它放進 `bottomNavigationBar`。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/widgets/common.dart';

void main() {
  Future<Rect> rectIn(WidgetTester t, Widget Function(Widget) wrap) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: wrap(AppButton(label: '交卷', onPressed: () {}))),
    ));
    await t.pumpAndSettle();
    return t.getRect(find.byType(AppButton));
  }

  testWidgets('鬆約束（Center）：依內容決定高度，不是撐滿', (t) async {
    final r = await rectIn(t, (b) => Center(child: b));
    expect(r.height, 48, reason: '撐滿的話會是整個畫面的高度');
    expect(r.width, greaterThan(100), reason: '寬度照樣吃滿，版面不變');
  });

  testWidgets('Column 裡不變', (t) async {
    final r = await rectIn(t, (b) => Column(children: [b]));
    expect(r.height, 48);
  });

  testWidgets('ListView 裡不變', (t) async {
    final r = await rectIn(t, (b) => ListView(children: [b]));
    expect(r.height, 48);
  });

  // 這正是使用者踩到的擺法。
  testWidgets('bottomNavigationBar：不可以把 body 擠成 0 高', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: const [Text('題目一')]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AppButton(label: '交卷', onPressed: () {}),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(t.getRect(find.byType(AppButton)).height, 48);
    expect(t.getRect(find.byType(ListView)).height, greaterThan(100),
        reason: 'body 被擠成 0 高的話，清單一個子項都不會建');
    expect(find.text('題目一'), findsOneWidget);
  });

  testWidgets('字很長時仍然長得高 —— minHeight 不是固定高度', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 120,
          child: Center(
            child: AppButton(
              label: '這是一個很長很長很長的按鈕文字會換行',
              onPressed: () {},
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(t.getRect(find.byType(AppButton)).height, greaterThan(48));
  });

  testWidgets('loading 態也不撐滿', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: AppButton(label: 'X', loading: true)),
      ),
    ));
    await t.pump();
    expect(t.getRect(find.byType(AppButton)).height, 48);
  });
}
