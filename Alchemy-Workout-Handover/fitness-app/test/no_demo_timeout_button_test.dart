// 等 AI 回話的那一頁，右下角不可以有一顆會讓它失敗的按鈕。
//
// 2026-09-28 使用者截圖回報：「分析時，右下角會寫『模擬逾時』請移除」。
// 那是驗收用的 Demo 入口，但它**沒有藏在開發者模式後面** ——
// 一般使用者盯著「AI 分析中」等待時，旁邊就擺著它。
//
// 這是同一個形狀第二次出現（第一次是教官申請頁的 Demo 按鈕，
// `PROGRESS.md` 0D）。失敗路徑本來就由 `ai_source_test.dart` 直接
// 呼叫 `aiFail()` 驗過，畫面不需要留入口。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/mock/mock_data.dart';
import 'package:fitness_app/screens/ai/ai_adjust_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  const src = AiSource.beforeTraining;

  testWidgets('分析中的畫面沒有「模擬逾時」', (t) async {
    final s = AppState();
    s.startWorkout(kAllPlans.firstWhere((p) => p.id == 'p_push'));
    s.aiRequest(src, '今天狀況不太好');
    await s.aiConfirmDemand(src, '整體降強度');
    expect(s.aiStage[src], AiStage.analyzing, reason: '前提：要停在分析中');

    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: AiAdjustScreen(source: src)),
    ));
    await t.pump();

    expect(find.text('AI 分析中，請稍候…'), findsOneWidget);
    expect(find.text('模擬逾時'), findsNothing);
  });
}
