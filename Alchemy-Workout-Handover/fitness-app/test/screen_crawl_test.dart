// 畫面爬蟲：從五個分頁出發，逐一點開每個「真的按得到」的東西，
// 看有沒有爆版或丟例外。
//
// 既有的 375 檢查只掃五個分頁；這支把點得到的每一頁都走一遍。
// 抓的是「在手機尺寸下才會壞」的那一類 —— RenderFlex 溢出、除以零、
// 空清單取 first。這些在 macOS 的寬視窗底下不會現形。
//
// 【爬蟲本身的正確性】必須先確認它真的有在點。
// IndexedStack 會把背景分頁的元素留在樹上，不做命中測試的話，
// 會拿背景分頁的座標去點前景分頁，爬出一份看起來很豐富、實際全假的報告。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/main.dart';

/// 設計基準機型 iPhone 15／16（393 × 852）。
const kBase = Size(393 * 3, 852 * 3);

/// 最窄檢查點 iPhone SE（375 × 667）。
const kNarrow = Size(375 * 3, 667 * 3);

/// 目前的主流機型 iPhone 17（402 × 874）。
const kWide = Size(402 * 3, 874 * 3);

Future<void> boot(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
}

class Target {
  final Offset center;
  final String label;
  const Target(this.center, this.label);
}

/// 這一頁上**真的按得到**的東西：有 onTap、有大小、在畫面內，
/// 且該點的命中路徑確實包含它。
List<Target> hittable(WidgetTester t) {
  final raw = <Element>[];
  void visit(Element e) {
    final w = e.widget;
    if ((w is InkWell && w.onTap != null) ||
        (w is GestureDetector && w.onTap != null) ||
        (w is ListTile && w.onTap != null)) {
      raw.add(e);
    }
    e.visitChildren(visit);
  }

  t.binding.rootElement?.visitChildren(visit);

  final screen = t.view.physicalSize / t.view.devicePixelRatio;
  final out = <Target>[];
  final seen = <String>{};
  for (final e in raw) {
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
    final c = box.localToGlobal(box.size.center(Offset.zero));
    if (c.dx < 0 || c.dy < 0 || c.dx > screen.width || c.dy > screen.height) {
      continue;
    }
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, c, t.view.viewId);
    if (!hit.path.any((h) => h.target == box)) continue;
    // InkWell 與 GestureDetector 常常包著同一顆按鈕，中心點相同 —— 只留一份。
    final key = '${c.dx.round()},${c.dy.round()}';
    if (!seen.add(key)) continue;
    out.add(Target(c, _describe(e)));
  }
  return out;
}

/// 給問題訊息一個看得懂的名字 —— 「第 7 個 InkWell」查不出是哪顆按鈕。
String _describe(Element e) {
  final texts = <String>[];
  void visit(Element c) {
    final w = c.widget;
    if (w is Text && w.data != null && w.data!.trim().isNotEmpty) {
      texts.add(w.data!.trim());
    }
    if (texts.length < 3) c.visitChildren(visit);
  }

  e.visitChildren(visit);
  return texts.isEmpty ? '(無文字元素)' : texts.take(2).join(' / ');
}

/// 回到某個分頁的根。
///
/// **「訓練」在分頁列上沒有文字** —— 它是中央那顆 [Icons.fitness_center]
/// 圖示按鈕。原本這裡一律用 `find.text(tab)`，找不到就靜靜 return，
/// 於是這支爬蟲**從來沒有爬過訓練分頁**，而測試照樣全綠。
///
/// 現在找不到就 [fail]。沉默的 return 讓一個爬不到的分頁看起來像爬過了，
/// 那比爬蟲壞掉更糟 —— 壞掉會被發現。
Future<void> toTabRoot(WidgetTester t, String tab) async {
  final nav = Navigator.of(t.element(find.byType(Navigator).first));
  var guard = 0;
  while (nav.canPop() && guard++ < 10) {
    nav.pop();
    await t.pumpAndSettle();
  }
  final target = tabFinder(tab);
  if (target.evaluate().isEmpty) {
    fail('找不到分頁「$tab」的入口 —— 爬蟲會靜靜跳過它，那等於沒爬');
  }
  await t.tap(target.last);
  await t.pumpAndSettle();
}

/// 分頁列上該分頁的入口。
Finder tabFinder(String tab) => tab == '訓練'
    ? find.byIcon(Icons.fitness_center)
    : find.text(tab);

/// 把分頁往下捲 [by] 點。捲不動就算了 —— 有些頁本來就一屏放得下。
/// 等畫面靜下來。**骨架屏的閃爍是永不停止的動畫**，`pumpAndSettle`
/// 對它必然逾時 —— 那是動畫的性質，不是 app 的毛病，逾時就改推固定幾幀。
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

Future<void> scrollBy(WidgetTester t, double by) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty || by == 0) return;
  try {
    await t.drag(scrollables.first, Offset(0, -by));
    await t.pumpAndSettle();
  } catch (_) {
    // 捲不動不是問題。
  }
}

/// 走一個分頁。
///
/// **兩層**：分頁上的每個元素點一次，點開的那一頁裡的每個元素再點一次。
/// 只走一層的話，像「訓練 → 任務」這種第二層的頁根本碰不到 ——
/// 我第一次寫的版本就是這樣，故意在 tasks_screen 弄一個爆版它沒抓到。
///
/// **要捲動**：一屏之外的元素命中測試會失敗，不捲就等於只驗了首屏。
Future<(List<String>, int)> crawlTab(WidgetTester t, String tab) async {
  final problems = <String>[];
  var taps = 0;
  const offsets = [0.0, 400.0, 800.0, 1400.0];

  for (final off in offsets) {
    await toTabRoot(t, tab);
    await scrollBy(t, off);
    final n = hittable(t).length;

    for (var i = 0; i < n; i++) {
      await toTabRoot(t, tab);
      await scrollBy(t, off);
      final list = hittable(t);
      if (i >= list.length) break;
      final target = list[i];
      final where = '[$tab@$off]「${target.label}」';
      try {
        await t.tapAt(target.center);
        await settle(t);
        taps++;
      } catch (e) {
        problems.add('$where 點下去丟例外：\n    $e');
        continue;
      }
      var ex = t.takeException();
      if (ex != null) {
        problems.add('$where 點開後：\n    $ex');
        continue;
      }

      // 第二層：在點開的這一頁裡，每個元素也點一次。
      final inner = hittable(t);
      for (var j = 0; j < inner.length && j < 12; j++) {
        final list2 = hittable(t);
        if (j >= list2.length) break;
        final t2 = list2[j];
        try {
          await t.tapAt(t2.center);
          await settle(t);
          taps++;
        } catch (e) {
          problems.add('$where →「${t2.label}」點下去丟例外：\n    $e');
          continue;
        }
        ex = t.takeException();
        if (ex != null) {
          problems.add('$where →「${t2.label}」點開後：\n    $ex');
        }
      }
    }
  }
  return (problems, taps);
}

void main() {
  for (final (name, size) in [
    ('393 設計基準', kBase),
    ('375 最窄', kNarrow),
    ('402 iPhone 17', kWide),
  ]) {
    testWidgets('$name：每一頁點得到的元素都不爆', (t) async {
      await boot(t, size);
      final all = <String>[];
      final taps = <String, int>{};
      for (final tab in ['首頁', '社群', '訓練', '商店', '我的']) {
        final (p, n) = await crawlTab(t, tab);
        all.addAll(p);
        taps[tab] = n;
      }
      // 爬蟲自己要先站得住腳：點得太少就代表它其實沒在爬。
      //
      // **逐頁檢查，不看總數**。原本只驗總和 > 200，於是
      //「訓練」那一頁貢獻 0 次也被其他四頁蓋過去，測試照樣全綠 ——
      // 而那正是先前真實發生的事（見 [toTabRoot]）。
      for (final e in taps.entries) {
        expect(e.value, greaterThan(10),
            reason: '「${e.key}」只點了 ${e.value} 次 —— 這一頁其實沒被爬到');
      }
      final total = taps.values.fold<int>(0, (a, b) => a + b);
      expect(total, greaterThan(200), reason: '只點了 $total 次，爬蟲沒有真的在走');
      expect(all, isEmpty, reason: '\n${all.join('\n')}');
    });
  }
}
