// 浮動提示不可以擋住底部的主按鈕（第 5 節 12c）。
//
// `showToast` 用 `SnackBarBehavior.floating`，貼在畫面最底；
// 而本專案的主按鈕一律在 `_Footer` 裡，也在最底。兩者重疊的那兩秒，
// **使用者按了沒反應** —— 沒有任何提示說明為什麼。
//
// 註冊流程那一處 2026-09-17 是靠「把那個提示拿掉」繞過的，但同一個陷阱
// 在任何「動作完成 → 換頁 → 新頁底部有按鈕」的組合裡都還在。
//
// ## 為什麼改位置而不是改點擊行為
//
// 2026-09-29 實測過兩條「讓提示不攔截點擊」的路，**都無效**：
//
// | 試法 | 結果 |
// |---|---|
// | `hitTestBehavior: HitTestBehavior.translucent` | 仍被擋住 |
// | 把 `content` 包進 `IgnorePointer` | 仍被擋住 |
//
// 吃掉點擊的那一層在 Flutter 的 `SnackBar` 內部，我們碰不到。真要根治得
// 自己寫 `OverlayEntry`，而那會動到全站 `showToast` 的計時器生命週期
// —— 兩千多個測試裡有大量間接呼叫它的。所以先解掉重疊本身。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/overlays.dart';

void main() {
  /// 照 App 真正的版面搭：底部按鈕在 `body` 的 Column 裡，
  /// **不是** `bottomNavigationBar`。
  ///
  /// 這個差別是這條測試的成敗關鍵 —— 用 `bottomNavigationBar` 搭的話，
  /// 浮動提示本來就會浮在它上面，測不到任何東西（第一版探針就是這樣
  /// 得到「沒被擋住」的假答案）。
  Future<int> tapsThroughToast(WidgetTester t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Center(
                  child: ElevatedButton(
                    onPressed: () => showToast(c, '已完成'),
                    child: const Text('做一件事'),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => taps++,
                    child: const Text('底部主按鈕'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    await t.tap(find.text('做一件事'));
    await t.pumpAndSettle();
    // 前提：提示真的出現了。沒出現的話下面那一下本來就按得到，
    // 這條測試會變成永遠綠的。
    expect(find.text('已完成'), findsOneWidget);

    await t.tap(find.text('底部主按鈕'), warnIfMissed: false);
    await t.pump();
    return taps;
  }

  testWidgets('提示浮著的時候，底部主按鈕仍然按得到', (t) async {
    expect(await tapsThroughToast(t), 1,
        reason: '按了沒反應是最難查的一種壞掉 —— 它看起來跟「App 當了」一樣');
  });
}
