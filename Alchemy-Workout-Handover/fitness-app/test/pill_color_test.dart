// `Pill` 的 `color` 必須真的畫出來。
//
// ## 為什麼需要這條測試
//
// 原本寫成：
//
// ```dart
// borderColor: filled ? color : C.lineDivider,
// fill: filled ? color : null,
// ```
//
// 沒有 `filled: true` 的時候，**傳進來的 `color` 不影響任何一個像素**。
// 全 App 用了 57 次 `Pill`，25 次傳了 `color` 而沒有 `filled` ——
// 那 25 個顏色一個都沒畫出來。
//
// 最明顯的後果是課表卡片：`[QA-02l]` 要「適用經驗／適用目標裡**符合我的
// 那一個**染亮色」，程式算得好好的，算完被扔掉。使用者 2026-09-29 的
// 截圖裡一整排標籤全是灰的 —— 而**那個畫面看起來沒有壞**，
// 只是少了一個本來該有的訊息。
//
// 這一家族的缺陷（算出來的值被靜靜丟掉）在這個專案已經出現多次，
// 共同點是**沒有任何錯誤、沒有任何紅燈**。所以要有人去驗「那個值到底有
// 沒有走到畫面上」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/tokens.dart';
import 'package:fitness_app/widgets/common.dart';

void main() {
  /// 畫一顆 Pill，回傳它實際用的邊框色與字色。
  Future<({Color border, Color text})> render(WidgetTester t, Pill pill) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: pill))));
    final box = t.widget<Container>(find.descendant(
      of: find.byWidget(pill),
      matching: find.byType(Container),
    ));
    final deco = box.decoration! as BoxDecoration;
    final text = t.widget<Text>(find.descendant(
      of: find.byWidget(pill),
      matching: find.byType(Text),
    ));
    return (
      border: (deco.border! as Border).top.color,
      text: text.style!.color!,
    );
  }

  testWidgets('傳了顏色就要看得見 —— 邊框與文字都上色', (t) async {
    const c = C.actionPrimary;
    final got = await render(t, const Pill('增肌', color: c));
    expect(got.border, c, reason: '這正是以前被丟掉的那一個值');
    expect(got.text, c, reason: '只染邊框在一排標籤裡幾乎看不出來');
  });

  testWidgets('沒傳顏色的行為一個位元都不變', (t) async {
    final got = await render(t, const Pill('器材：健身房'));
    expect(got.border, C.lineDivider);
    expect(got.text, C.textSecondary);
  });

  testWidgets('填色版維持原樣 —— 實心底配反白字', (t) async {
    const c = C.actionPrimary;
    final got = await render(t, const Pill('推薦', color: c, filled: true));
    expect(got.border, c);
    expect(got.text, C.onFill(c));
  });

  testWidgets('兩顆不同顏色的標籤畫出來真的不一樣', (t) async {
    // 這條是上面三條的總和 —— 「符合我的那一個看得出來」這件事，
    // 說到底就是**兩顆標籤不能長得一樣**。
    final on = await render(t, const Pill('增肌', color: C.actionPrimary));
    final off = await render(t, const Pill('減重', color: C.textSecondary));
    expect(on.text, isNot(off.text));
    expect(on.border, isNot(off.border));
  });
}
