// 修改已公開的課表前要先確認（使用者裁決 A，2026-10-17）。
//
// 使用者測 Z5 時，把已公開的「測試課表 Z3」改名成 Z5 —— 已公開的課表一修改（連改名都算）
// 就會重新送審，雲端那份立刻變回審核中，別人看不到它。畫面上沒有任何警告，使用者不知道。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/screens/train/custom_plan_edit_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  late AppState s;
  SavedPlan? saved;
  var popped = false;

  CustomPlan planIn(CustomPlanState state) {
    s.addPlan('我的推日', [
      PlanExercise(
        exercise: s.platformExercises.firstWhere(
            (e) => e.type == ExerciseType.strength && !e.isBodyweight),
        planned: const [PlannedSet(40, 8)],
      ),
    ]);
    final p = s.customPlans.last;
    p.state = state;
    return p;
  }

  Future<void> open(WidgetTester t, CustomPlan p) async {
    saved = null;
    popped = false;
    t.view.physicalSize = const Size(393 * 3, 1800 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(AppScope(
      state: s,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<SavedPlan>(
                    MaterialPageRoute(
                        builder: (_) => CustomPlanEditScreen(initial: p)),
                  );
                  popped = true;
                },
                child: const Text('開編輯'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('開編輯'));
    await t.pumpAndSettle();
  }

  setUp(() => s = AppState());

  testWidgets('已公開的課表：按儲存先跳確認，選「先不要」留在編輯頁、沒有儲存', (t) async {
    await open(t, planIn(CustomPlanState.public));
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(find.text('修改後需要重新審核'), findsOneWidget);
    expect(find.textContaining('審核期間其他人暫時看不到'), findsWidgets);

    await t.tap(find.text('先不要'));
    await t.pumpAndSettle();
    expect(popped, isFalse, reason: '選先不要就不該離開編輯頁');
    expect(find.byType(CustomPlanEditScreen), findsOneWidget);
    expect(saved, isNull);
  });

  testWidgets('已公開的課表：選「繼續修改」才儲存', (t) async {
    await open(t, planIn(CustomPlanState.public));
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    await t.tap(find.text('繼續修改'));
    await t.pumpAndSettle();
    expect(popped, isTrue);
    expect(saved, isNotNull);
    expect(saved!.name, '我的推日');
  });

  testWidgets('還沒公開的課表：照舊，儲存不問', (t) async {
    await open(t, planIn(CustomPlanState.published));
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(find.text('修改後需要重新審核'), findsNothing);
    expect(popped, isTrue);
    expect(saved, isNotNull);
  });

  testWidgets('編輯頁底下的說明：已公開的課表講重新審核，不是「已儲存、尚未啟用」', (t) async {
    await open(t, planIn(CustomPlanState.public));
    expect(find.textContaining('這份課表已公開'), findsOneWidget);
    expect(find.textContaining('尚未啟用'), findsNothing);
  });
}
