// 管理員後台與其餘深層畫面的巡覽。
//
// 後台掛在「我的 → 更多 → 管理員後台」底下，自動探索碰不到。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fitness_app/main.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('管理員後台逐頁', (t) async {
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

    /// 捲到看得見再點。找不到就跳過，不讓整趟停掉。
    Future<bool> go(String label, String name) async {
      final f = find.text(label);
      if (f.evaluate().isEmpty) {
        final sc = find.byType(Scrollable);
        if (sc.evaluate().isNotEmpty) {
          try {
            await t.scrollUntilVisible(find.text(label), 300,
                scrollable: sc.first);
            await t.pumpAndSettle();
          } catch (_) {}
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

    // 我的 → 更多
    await t.tap(find.text('我的').last);
    await t.pumpAndSettle();
    // 「更多」在我的分頁最底下，先捲到底。
    final sc = find.byType(Scrollable);
    for (var i = 0; i < 8; i++) {
      if (find.text('更多').evaluate().isNotEmpty) break;
      await t.drag(sc.first, const Offset(0, -500));
      await t.pumpAndSettle();
    }
    await go('更多', '更多');

    // 其餘深層畫面
    for (final s in ['註冊流程', 'AI 自動優化', '骨架屏與錯誤頁']) {
      if (await go(s, s)) await back();
    }

    // 管理員後台
    if (await go('管理員後台', '管理員後台')) {
      for (final s in [
        '待審佇列',
        '訂單佇列',
        '商品清單',
        '評分彙總',
        '平台設定',
      ]) {
        if (await go(s, '後台-$s')) await back();
      }
    }
  });
}
