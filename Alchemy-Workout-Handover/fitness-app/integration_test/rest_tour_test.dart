// 剩下的畫面：補簽日曆、教官申請、自訂訓練編輯，以及後台第二層。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fitness_app/main.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('剩下的畫面', (t) async {
    await b.convertFlutterSurfaceToImage();
    await t.pumpWidget(const FitnessApp());
    await t.pumpAndSettle();

    var n = 0;
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await b.takeScreenshot('${(++n).toString().padLeft(2, '0')}-$name');
    }

    Future<void> back() async {
      final nav = Navigator.of(t.element(find.byType(Navigator).first));
      if (nav.canPop()) {
        nav.pop();
        await t.pumpAndSettle();
      }
    }

    Future<bool> go(String label, String name) async {
      if (find.text(label).evaluate().isEmpty) {
        final sc = find.byType(Scrollable);
        if (sc.evaluate().isNotEmpty) {
          for (var i = 0; i < 10; i++) {
            if (find.text(label).evaluate().isNotEmpty) break;
            await t.drag(sc.first, const Offset(0, -450));
            await t.pumpAndSettle();
          }
        }
      }
      if (find.text(label).evaluate().isEmpty) {
        debugPrint('!! 找不到「$label」');
        return false;
      }
      await t.tap(find.text(label).last);
      await t.pumpAndSettle();
      await shot(name);
      return true;
    }

    Future<void> tab(String name) async {
      await t.tap(find.text(name).last);
      await t.pumpAndSettle();
    }

    // 首頁 → 補簽
    await tab('首頁');
    if (await go('補簽', '補簽日曆')) await back();

    // 我的（＝更多）底下的其餘畫面
    for (final s in [
      '自訂訓練',
      '動作庫',
      '新手 / 回歸任務',
      '能力值退步狀態',
      '教官申請',
      '師徒互動頁',
      '處罰與申訴',
      '設定',
    ]) {
      await tab('我的');
      if (await go(s, s.replaceAll('/', '＿'))) await back();
    }

    // 後台第二層
    await tab('我的');
    if (await go('管理員後台', '後台')) {
      if (await go('平台設定', '後台-平台設定')) {
        for (final s in ['設定訓練計畫', '設定成就定義', '設定每日任務池', '設定限時任務']) {
          if (await go(s, '後台-$s')) await back();
        }
        await back();
      }
      if (await go('商品清單', '後台-商品清單')) {
        if (await go('設定商品資訊', '後台-商品編輯')) await back();
        await back();
      }
    }
  });
}
