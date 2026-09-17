// 註冊走完要看到新手任務（`[QA-02g]`）。
//
// 〈註冊流程〉的最後兩步是「訓練計畫已推薦 → 新手任務已指派」，兩者為
// 嚴格順序，而**指派是系統做的**。實作照著發生了，但發生完就把人丟在
// 首頁 —— 新手任務的入口在「我的」頁往下捲很久的地方，等於指派了
// 卻沒告訴他。
//
// `[QA-02f]` 之後這件事更要緊：社群互動全部鎖在新手任務後面，
// 找不到任務就等於整個社群永遠是鎖著的，而且看不出為什麼。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/home_shell.dart';
import 'package:fitness_app/screens/signup/launch_screen.dart';
import 'package:fitness_app/screens/train/tasks_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

void main() {
  testWidgets('註冊的最後一步按下去，看到的是新手任務', (t) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(FitnessApp(store: MemoryStore()));
    await t.pumpAndSettle();
    final s = AppScope.of(t.element(find.byType(MaterialApp)));
    expect(s.signUpCompleted, isFalse, reason: '前提：這是全新裝置');

    // 十題逐一點過去不是這條測試要驗的事（那是 smoke_test 的工作），
    // 所以直接把草稿填好，再一路按「下一步」走完。
    final d = s.signUpDraft
      ..nickname = '阿昶'
      ..heightCm = 175
      ..weightKg = 70
      ..gender = '男'
      ..birthday = DateTime(2000, 1, 1)
      ..commonGoal = kCommonGoals.first
      ..experience = kExperience.first
      ..daysPerWeek = 3
      ..duration = kDurations.first;
    d.equipment.add(kEquipmentTiers.first);
    expect(d.complete, isTrue);

    // 啟動頁 → 登入頁 → 條款
    await t.tap(find.byType(LaunchScreen));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '使用 Apple 帳號繼續'));
    await t.pumpAndSettle();
    await t.tap(find.byType(AppSwitch));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '同意並建立帳號'));
    await t.pumpAndSettle();

    // 十題都已有值，一路下一步。
    for (var i = 0; i < SignUpDraft.total; i++) {
      final label = i == SignUpDraft.total - 1 ? '完成' : '下一步';
      await t.tap(find.widgetWithText(AppButton, label));
      await t.pumpAndSettle();
    }

    // 完成註冊 → 訓練計畫推薦
    expect(s.signUpCompleted, isTrue);
    await t.tap(find.widgetWithText(AppButton, '看推薦的訓練計畫'));
    await t.pumpAndSettle();

    // 最後一步。原本這裡直接進首頁。
    await t.tap(find.widgetWithText(AppButton, '開始使用'));
    await t.pumpAndSettle();

    expect(find.byType(TasksScreen), findsOneWidget,
        reason: '「新手任務已指派」發生了，就要讓他看得到');
    expect(find.byType(HomeShell), findsOneWidget,
        reason: '任務頁疊在主畫面上 —— 按返回要有東西接住');
  });

  testWidgets('新手任務頁按返回就回到主畫面，不是死路', (t) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(FitnessApp(store: MemoryStore()));
    await t.pumpAndSettle();
    final s = AppScope.of(t.element(find.byType(MaterialApp)));
    final d = s.signUpDraft
      ..nickname = '阿昶'
      ..heightCm = 175
      ..weightKg = 70
      ..gender = '男'
      ..birthday = DateTime(2000, 1, 1)
      ..commonGoal = kCommonGoals.first
      ..experience = kExperience.first
      ..daysPerWeek = 3
      ..duration = kDurations.first;
    d.equipment.add(kEquipmentTiers.first);

    await t.tap(find.byType(LaunchScreen));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '使用 Apple 帳號繼續'));
    await t.pumpAndSettle();
    await t.tap(find.byType(AppSwitch));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '同意並建立帳號'));
    await t.pumpAndSettle();
    for (var i = 0; i < SignUpDraft.total; i++) {
      await t.tap(find.widgetWithText(
          AppButton, i == SignUpDraft.total - 1 ? '完成' : '下一步'));
      await t.pumpAndSettle();
    }
    await t.tap(find.widgetWithText(AppButton, '看推薦的訓練計畫'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(AppButton, '開始使用'));
    await t.pumpAndSettle();

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(TasksScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
