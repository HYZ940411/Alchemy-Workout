// 初審通過之後，畫面只剩「作答教官測驗」，沒有地方可以略過
// （使用者 2026-10-17：要讓 HYZ 快速成為教官測師徒，AI 評分過了之後
// 「推進到下一階段（Demo）」不見了）。
//
// 那顆 Demo 鍵只出現在 `_ =>` 那一支，而 screenPassed／testing 兩階段
// 各自有「作答」的分支。開發者模式補一顆略過測驗的鍵。
//
// **不替申請人核准自己**：略過之後停在「待人工審核」，最後一步仍是管理員。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/me/instructor_apply_screen.dart';
import 'package:fitness_app/state/app_state.dart';

AppState _passedScreening({bool dev = true}) {
  final s = AppState()
    ..fastForwardToInstructorGate()
    ..instructorStage = InstructorStage.screenPassed;
  if (dev) s.toggleDeveloperMode();
  return s;
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('狀態', () {
    test('初審通過 → 略過 → 待人工審核，選擇題滿分', () {
      final s = _passedScreening();
      s.devSkipInstructorExam();
      expect(s.instructorStage, InstructorStage.pendingReview);
      expect(s.examMcScore, 100);
    });

    test('已在作答階段也行', () {
      final s = _passedScreening()..instructorStage = InstructorStage.testing;
      s.devSkipInstructorExam();
      expect(s.instructorStage, InstructorStage.pendingReview);
    });

    test('停在待人工審核，不會自己核准自己', () {
      final s = _passedScreening()..devSkipInstructorExam();
      s.devSkipInstructorExam(); // 再按一次也不會往下走
      expect(s.instructorStage, InstructorStage.pendingReview);
      expect(s.isInstructor, isFalse);
    });

    test('沒開開發者模式 → 沒有作用', () {
      final s = _passedScreening(dev: false);
      s.devSkipInstructorExam();
      expect(s.instructorStage, InstructorStage.screenPassed);
    });

    test('還沒過初審的階段 → 沒有作用', () {
      final s = AppState()..toggleDeveloperMode();
      s.devSkipInstructorExam();
      expect(s.instructorStage, InstructorStage.notApplied);
    });

    test('已駁回 → 沒有作用（那要走重考鎖的逃生門）', () {
      final s = _passedScreening()..submitExam(5);
      expect(s.instructorStage, InstructorStage.rejected, reason: '前提');
      s.devSkipInstructorExam();
      expect(s.instructorStage, InstructorStage.rejected);
    });
  });

  group('畫面', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: InstructorApplyScreen()),
      ));
      await t.pumpAndSettle();
    }

    final skip = find.text('（Demo）略過測驗，直接送人工審核');

    testWidgets('開發者模式 + 初審通過 → 看得到，按下去進待人工審核', (t) async {
      final s = _passedScreening();
      await open(t, s);
      await t.scrollUntilVisible(skip, 300,
          scrollable: find.byType(Scrollable).first);
      await t.tap(skip);
      await t.pumpAndSettle();
      expect(s.instructorStage, InstructorStage.pendingReview);
    });

    testWidgets('沒開開發者模式 → 沒有這顆', (t) async {
      final s = _passedScreening(dev: false);
      await open(t, s);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(skip, findsNothing);
    });

    testWidgets('其他階段 → 沒有這顆', (t) async {
      final s = AppState()..toggleDeveloperMode();
      await open(t, s);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(skip, findsNothing);
    });
  });
}
