// 在真的模擬器上逐頁巡覽並截圖。
//
// 這是目前唯一「看得見文字」的路徑：widget test 的環境沒有中文字型，
// golden 出來全是方框；模擬器截圖有真字型，但外部點不動它。
// integration_test 兩邊都有 —— 真字型，而且驅動得了。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/widgets/common.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('逐頁巡覽', (t) async {
    await b.convertFlutterSurfaceToImage();
    await t.pumpWidget(const FitnessApp());
    await t.pumpAndSettle();

    var n = 0;
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await b.takeScreenshot('${(++n).toString().padLeft(2, '0')}-$name');
    }

    /// 點一個文字並截圖。找不到就記下來，不讓整趟停掉。
    Future<bool> go(String text, String name, {bool last = true}) async {
      final f = find.text(text);
      if (f.evaluate().isEmpty) {
        debugPrint('!! 找不到「$text」，跳過 $name');
        return false;
      }
      await t.tap(last ? f.last : f.first);
      await t.pumpAndSettle();
      await shot(name);
      return true;
    }

    Future<void> back() async {
      final nav = Navigator.of(t.element(find.byType(Navigator).first));
      if (nav.canPop()) {
        nav.pop();
        await t.pumpAndSettle();
      }
    }

    Future<void> tab(String name) async {
      await t.tap(find.text(name).last);
      await t.pumpAndSettle();
    }

    // ---- 首頁 ----
    await shot('首頁');
    await go('查看全部', '首頁-任務');
    await back();

    // ---- 社群 ----
    await tab('社群');
    await shot('社群-動態');
    for (final s in ['團隊', '師徒', '私訊', '關注', '探索']) {
      await go(s, '社群-$s');
    }

    // ---- 商店 ----
    await tab('商店');
    await shot('商店');
    for (final s in ['商城', '金幣儲值', 'AI 點數', '會員訂閱', '我的訂單']) {
      if (await go(s, '商店-$s')) await back();
    }

    // ---- 我的 ----
    await tab('我的');
    await shot('我的');
    for (final s in ['六維能力值', '我的檔案', '訓練歷史', '成就']) {
      if (await go(s, '我的-$s')) await back();
    }

    // ---- 六維的時間維度：三個檔位要長得不一樣 ----
    await tab('我的');
    if (await go('六維能力值', '六維-現在')) {
      for (final label in ['30 天前', '31 天前', '90 天前', '91 天前']) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue;
        await t.tap(f.last);
        await t.pumpAndSettle();
        await shot('六維-$label');
      }
      await back();
    }

    // ---- 自動探索：每個分頁捲到底，把每個列都點開看一遍 ----
    //
    // 不猜標籤。先前寫死「成就與獎勵」「獎勵信箱」等字串，
    // 15 個裡有 12 個根本找不到 —— 它們在摺線下方，或名字不是那樣。
    for (final tabName in ['我的', '社群', '商店', '首頁']) {
      await tab(tabName);
      final seen = <String>{};
      for (var round = 0; round < 6; round++) {
        // 這一屏有哪些可點的列。
        final labels = <String>[];
        for (final e in find.byType(ListRow).evaluate()) {
          final texts = <String>[];
          void visit(Element c) {
            final w = c.widget;
            if (w is Text && (w.data ?? '').trim().isNotEmpty) {
              texts.add(w.data!.trim());
            }
            c.visitChildren(visit);
          }

          e.visitChildren(visit);
          if (texts.isNotEmpty) labels.add(texts.first);
        }
        var opened = false;
        for (final l in labels) {
          if (!seen.add(l)) continue;
          final f = find.text(l);
          if (f.evaluate().isEmpty) continue;
          await t.tap(f.first);
          await t.pumpAndSettle();
          await shot('$tabName-$l');
          await back();
          opened = true;
          break;
        }
        if (opened) continue;
        // 這一屏都看過了，往下捲。
        final sc = find.byType(Scrollable);
        if (sc.evaluate().isEmpty) break;
        await t.drag(sc.first, const Offset(0, -400));
        await t.pumpAndSettle();
      }
    }

    // ---- 訓練 ----
    await tab('首頁');
    await go('開始訓練', '訓練中');
  });
}
