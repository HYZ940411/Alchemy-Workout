// 14 天重考鎖的逃生門（2026-09-28）。
//
// 使用者測完 P3–P5 之後選擇題沒到 80%，被駁回並鎖 14 天。
// 他問「有沒有辦法跳過測驗進入待審核」—— **當下沒有**：
//
//   · `advanceInstructorApplication()`（Demo 推進鍵）的階段清單裡
//     沒有 `rejected`，`indexOf` 回 -1 就直接 return，按了沒反應
//   · `reapplyInstructor()` 擋在 `examRetakeLeft > 0`
//
// **開發者模式的逃生門，在最需要它的時候打不開。**

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 走到「被駁回且鎖住」—— 使用者當下的處境。
AppState rejected() {
  final s = AppState()
    ..fastForwardToInstructorGate()
    ..instructorStage = InstructorStage.screenPassed;
  // 20 題只對 5 題，遠低於 80%。
  s.submitExam(5);
  return s;
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('前提：沒過就是駁回，而且鎖住', () {
    final s = rejected();
    expect(s.instructorStage, InstructorStage.rejected);
    expect(s.examRetakeLeft, greaterThan(Duration.zero));
    expect(s.reapplyInstructor(), isFalse, reason: '鎖著就重新申請不了');
  });

  test('Demo 推進鍵救不了「已駁回」—— 這正是缺口', () {
    final s = rejected();
    s.advanceInstructorApplication();
    expect(s.instructorStage, InstructorStage.rejected,
        reason: '階段清單裡沒有 rejected，按了不會動');
  });

  test('解除之後重新申請得了', () {
    final s = rejected()..clearExamRetakeLock();
    expect(s.examRetakeLeft, Duration.zero);
    expect(s.reapplyInstructor(), isTrue);
    // 沒接雲端評分時會**同步結算**（「只有『根本沒接雲端評分』那條路
    // 才在此結算」），所以落在初審通過而不是初審中。
    // 要驗的是「走出駁回了」，不是落在哪一格。
    expect(s.instructorStage, isNot(InstructorStage.rejected));
    expect(s.examMcScore, isNull, reason: '舊分數要清掉，不沿用');
  });

  // **只清時間鎖，不改階段、不給分數。**
  test('解除本身不改階段也不給分數', () {
    final s = rejected();
    final score = s.examMcScore;
    s.clearExamRetakeLock();
    expect(s.instructorStage, InstructorStage.rejected, reason: '階段不動');
    expect(s.examMcScore, score, reason: '分數不動');
  });

  group('畫面', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('教官門檻'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }

    testWidgets('鎖著時才出現這顆鍵', (t) async {
      final s = rejected()..toggleDeveloperMode();
      await open(t, s);
      expect(find.text('解除重考鎖'), findsOneWidget);
      expect(find.textContaining('重考鎖剩餘'), findsOneWidget);
    });

    testWidgets('沒鎖就不出現 —— 不留一顆按了沒事的鍵', (t) async {
      final s = AppState()..toggleDeveloperMode();
      expect(s.examRetakeLeft, Duration.zero, reason: '前提：沒考過');
      await open(t, s);
      expect(find.text('解除重考鎖'), findsNothing);
    });
  });
}
