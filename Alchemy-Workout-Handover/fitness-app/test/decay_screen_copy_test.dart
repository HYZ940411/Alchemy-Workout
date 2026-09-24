// 退步頁開頭那張說明卡移除（使用者裁決 2026-09-24）。
//
// 原本頁首有一張卡，把兩件事整段寫出來：
//
//   「六維各自獨立計時，自該維最後訓練日的日界（次日 04:00）起算，
//     滿 10 天未訓練該維即退 5%。」
//   「退步下限為『本次中斷前所處節點的主階降 2 階、小節點保留』之下緣…」
//
// 那是**推導過程**。使用者要的兩個結果，每一列自己就寫著了 ——
// 「距下次退步 3 天」與「下限 C+ 40 點」。把公式再講一次，只是讓人
// 以為自己漏懂了什麼。
//
// 同批移除兩個 `SectionTitle` 的補充字：
//   · 「24 / 36 / 96 / 240 小時」—— 四個沒有標籤的數字，而且是**寫死的**，
//     `decayHours` 其實可由平台參數調整，改了這裡不會跟著動
//   · 「攜帶資訊：肌群維度」—— 事件風暴的詞漏到畫面上，
//     已補進 `ui_jargon_test` 的術語清單，以後同類會被擋下

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/screens/train/decay_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Future<void> _pump(WidgetTester t, AppState s) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
      AppScope(state: s, child: const MaterialApp(home: DecayScreen())));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('頁首不再解釋退步公式', (t) async {
    await _pump(t, AppState());
    expect(find.textContaining('未訓練該維即退'), findsNothing);
    expect(find.textContaining('日界'), findsNothing);
  });

  testWidgets('頁首不再解釋下限怎麼算出來的', (t) async {
    await _pump(t, AppState());
    expect(find.textContaining('主階降'), findsNothing);
    expect(find.textContaining('小節點保留'), findsNothing);
  });

  testWidgets('六個計時器的標題沒有那串沒標籤的數字', (t) async {
    await _pump(t, AppState());
    expect(find.text('六個計時器'), findsOneWidget, reason: '標題本身要留著');
    expect(find.textContaining('24 / 36'), findsNothing);
  });

  testWidgets('退步紀錄的標題沒有規格術語', (t) async {
    // 示範身分才有退步流水，這一段才會出現。
    final s = AppState();
    expect(s.decayLog, isNotEmpty, reason: '前提：這一段要真的有被畫出來');
    await _pump(t, s);
    expect(find.text('能力值已退步'), findsOneWidget);
    expect(find.textContaining('攜帶資訊'), findsNothing);
  });

  testWidgets('該留的數字都還在 —— 拿掉的是說明，不是內容', (t) async {
    await _pump(t, AppState());
    // 每一列自己就寫著結果，這才是使用者要看的。
    expect(find.textContaining('下限'), findsWidgets);
    expect(find.textContaining('距下次退步'), findsWidgets);
    expect(find.text('胸'), findsOneWidget);
  });
}
