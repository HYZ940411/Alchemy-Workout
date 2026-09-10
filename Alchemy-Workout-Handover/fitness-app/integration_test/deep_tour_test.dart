// 深入巡覽：要多步操作才走得到的畫面。
//
// 自動探索只碰得到分頁下一兩層。結算頁得先練完一次訓練，
// 補簽日曆得從簽到卡進去，管理員後台得先切身分。這些都得手動帶路。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('練完一次，看結算', (t) async {
    await b.convertFlutterSurfaceToImage();
    await t.pumpWidget(const FitnessApp());
    await t.pumpAndSettle();

    var n = 0;
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await b.takeScreenshot('${(++n).toString().padLeft(2, '0')}-$name');
    }

    // 訓練分頁 → 課表 → 開始訓練
    await t.tap(find.byIcon(Icons.fitness_center).last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('推日：胸肩三頭'), 300);
    await t.tap(find.text('推日：胸肩三頭'));
    await t.pumpAndSettle();
    await shot('課表詳情');
    await t.scrollUntilVisible(find.text('開始訓練'), 300);
    await t.tap(find.text('開始訓練'));
    await t.pumpAndSettle();
    await shot('訓練中');

    // 把每一組都勾完。防作弊要求相鄰兩組不得連續低於 30 秒，
    // 故直接推進示範時鐘，不是真的等。
    final s = AppScope.of(t.element(find.byType(Scaffold).first));
    var guard = 0;
    while (s.currentRecord != null && guard++ < 40) {
      s.advanceDemoClock(const Duration(seconds: 45));
      await t.pumpAndSettle();
      if (!s.completeCurrentSet()) break;
      await t.pumpAndSettle();
      // 有休息倒數就跳過
      if (find.text('跳過休息').evaluate().isNotEmpty) {
        await t.tap(find.text('跳過休息').last);
        await t.pumpAndSettle();
      }
    }
    await shot('全部勾完');

    // 結束訓練：頂部的關閉鈕開結束彈窗，彈窗裡再按「完成訓練」。
    final close = find.byIcon(Icons.close);
    if (close.evaluate().isNotEmpty) {
      await t.tap(close.last);
      await t.pumpAndSettle();
      await shot('結束確認');
    }
    final done = find.text('完成訓練');
    if (done.evaluate().isNotEmpty) {
      await t.tap(done.last);
      await t.pumpAndSettle();
    }
    await shot('結算');

    // 結算頁往下捲，看完整份
    for (var i = 0; i < 4; i++) {
      final sc = find.byType(Scrollable);
      if (sc.evaluate().isEmpty) break;
      await t.drag(sc.first, const Offset(0, -600));
      await t.pumpAndSettle();
      await shot('結算-捲$i');
    }
  });
}
