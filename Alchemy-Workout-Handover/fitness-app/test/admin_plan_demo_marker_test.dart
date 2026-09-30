// 後台的課表清單要在**點進去之前**就標出哪幾份改了存不住。
//
// ## 使用者 2026-09-29 測 5 = B
//
// 「後台改訓練計畫 → 存 → 重新整理 → 打回原形」。查了雲端，`plans`
// 那 27 筆與種子一字不差 —— 什麼都沒寫進去。
//
// 根因不在寫回路徑（`[BE-12b]` 是好的），在**清單本身**：
// `AppState.platformPlans` 是 `[...kPlans, ...buildCsvPlansFrom(...)]`，
// 也就是**七份示範用假課表排在 27 份真課表前面**。管理員打開這一頁，
// 前七筆全是雲端沒有文件、改了存不住的，而畫面上看不出任何差別。
// 更巧的是七份裡唯一有解鎖價格的「進階：爆發力週期」也在其中 ——
// 想測「改金幣解鎖價格」的人幾乎一定會挑到它。
//
// `pushPlanSpec` 會在存檔時講「這是示範用的課表，不在雲端」，
// 但**那時候人已經改完了**。訊息出現在正確的時機才有用。
//
// 那七份不刪：它們撐著 AI 優化、會員鎖定、自訂課表那幾條流程的示範
// （見 `AppState.platformPlans` 的說明）。要做的是讓人分得出來。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/screens/admin/platform_catalog_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: PlatformPlansScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('雲端沒有對應文件的課表，列上就標明改動不上雲', (t) async {
    final s = AppState();
    final demo =
        s.platformPlans.where((p) => !s.planSpecById.containsKey(p.id)).toList();
    expect(demo, isNotEmpty, reason: '示範假課表本來就該存在，這條測試才有意義');

    await open(t, s);
    expect(find.textContaining('示範課表 · 改動不上雲'), findsWidgets);
  });

  testWidgets('真的平台課表不該被標成示範', (t) async {
    final s = AppState();
    final real =
        s.platformPlans.where((p) => s.planSpecById.containsKey(p.id)).toList();
    expect(real, isNotEmpty);

    await open(t, s);
    // 標記數不可以等於總數 —— 全部都標等於沒標。
    final marked = find.textContaining('示範課表 · 改動不上雲').evaluate().length;
    expect(marked, lessThan(s.platformPlans.length),
        reason: '27 份真課表改得動，不該被一起標掉');
    expect(marked, demoCountOf(s));
  });
}

/// 這個帳號有幾份課表在雲端沒有對應文件。
int demoCountOf(AppState s) =>
    s.platformPlans.where((p) => !s.planSpecById.containsKey(p.id)).length;
