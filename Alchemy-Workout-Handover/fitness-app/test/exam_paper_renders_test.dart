// 教官測驗要真的畫得出題目（2026-09-28）。
//
// 使用者點「作答教官測驗」之後看到一整片橘色，寫著「還有 23 題未作答」，
// 一題都答不了 —— 交卷鍵撐滿整個畫面，把題目清單擠成 0 高。
// 根因在 `AppButton`（見 `button_does_not_expand_test.dart`），
// 但這一頁要有自己的把關：**題目畫不出來這件事，要在這裡也紅一次。**

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/me/instructor_apply_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  testWidgets('點進測驗之後，題目與選項真的在畫面上', (t) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final s = AppState()
      ..fastForwardToInstructorGate()
      ..instructorStage = InstructorStage.screenPassed;
    expect(s.drawExam().length, greaterThan(0), reason: '前提：題庫抽得出來');

    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: InstructorApplyScreen()),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('作答教官測驗'));
    await t.pumpAndSettle();

    // 這三條任何一條紅了，使用者看到的就是那片橘色。
    expect(find.byType(RadioListTile<int>), findsWidgets,
        reason: '選項一個都沒有＝題目清單被擠成 0 高');
    expect(t.getRect(find.byType(ListView)).height, greaterThan(100),
        reason: '題目清單要有高度');
    expect(find.textContaining('未作答'), findsOneWidget);
  });
}
