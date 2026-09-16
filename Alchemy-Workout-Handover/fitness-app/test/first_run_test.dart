// 這台裝置上還沒有帳號時，第一個畫面要是註冊，不是主頁。
//
// 原本 `signUpCompleted` 預設為 true（示範用身分的一部分），於是
// 全新的瀏覽器打開看到的是**別人的**暱稱、階級與連續訓練天數。
// 那個取捨是在「給自己看」的前提下做的；要給別人測，前提就變了。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/home_shell.dart';
import 'package:fitness_app/screens/signup/signup_screen.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> boot(WidgetTester t, Store store) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(FitnessApp(store: store));
  await t.pumpAndSettle();
  return AppScope.of(t.element(find.byType(MaterialApp)));
}

void main() {
  testWidgets('沒存過 → 走註冊流程，不是主頁', (t) async {
    final s = await boot(t, MemoryStore());
    expect(find.byType(SignUpScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(s.signUpCompleted, isFalse);
  });

  testWidgets('全新裝置上，那位假使用者的資料當場就不存在', (t) async {
    // 只翻 signUpCompleted 旗標的話，整個註冊流程進行中，底下仍是
    // 45 階、1700 經驗的示範帳號 —— 使用者用任何方式離開流程
    //（瀏覽器上一頁、手勢返回）看到的就是別人的帳號。
    // 讓那個數字根本不存在，比在每一條離開的路上補防線可靠。
    final s = await boot(t, MemoryStore());
    expect(s.rank, 1, reason: '註冊都還沒開始，不該有 45 階');
    expect(s.totalExp, 0);
    expect(s.coins, 0);
    expect(s.history, isEmpty);
    expect(s.trainingStreakDays, 0);
    expect(s.achievements.where((a) => a.unlocked), isEmpty);
  });

  testWidgets('有存檔時不會被誤清', (t) async {
    final store = MemoryStore();
    await store.save(AppState().toSnapshot());
    final s = await boot(t, store);
    expect(s.rank, 45, reason: '讀得到存檔就照存檔說的算，一個位元都不該動');
    expect(s.totalExp, 1700);
  });

  testWidgets('存過了 → 直接進主頁', (t) async {
    final store = MemoryStore();
    await store.save(AppState().toSnapshot());
    await boot(t, store);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(SignUpScreen), findsNothing);
  });

  testWidgets('註冊到一半重新整理，還是回到註冊流程', (t) async {
    // 這是「用旗標判定」而不是「用有沒有存檔判定」的理由：
    // 註冊走到一半時已經存過檔了，但帳號還沒建立。
    final store = MemoryStore();
    final half = AppState()..signUpCompleted = false;
    await store.save(half.toSnapshot());

    await boot(t, store);
    expect(
      find.byType(SignUpScreen),
      findsOneWidget,
      reason: '存檔說還沒註冊完，就不該放人進主頁',
    );
  });

  testWidgets('走完註冊之後才切到主頁 —— 最後一步不會被吃掉', (t) async {
    final s = await boot(t, MemoryStore());
    expect(find.byType(SignUpScreen), findsOneWidget);

    // completeSignUp 在「訓練計畫已推薦」的**前一步**就把旗標設成 true
    //（帳號要先建立，推薦頁才進得去 —— 模型的 Precondition）。
    // 直接跟著旗標走的話，畫面會在這裡就切走，把最後一頁吃掉。
    s.signUpCompleted = true;
    s.notifyListeners();
    await t.pumpAndSettle();

    expect(
      find.byType(SignUpScreen),
      findsOneWidget,
      reason: '旗標翻了不代表流程走完，最後一頁還沒看',
    );
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('沒有 store 時維持示範身分 —— 既有測試不受影響', (t) async {
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const FitnessApp());
    await t.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
  });

  test('直接建出來的 AppState 仍是已註冊的示範身分', () {
    expect(AppState().signUpCompleted, isTrue);
  });

  test('讀不到存檔就翻成未註冊', () async {
    final s = AppState();
    await s.hydrate(MemoryStore());
    expect(s.signUpCompleted, isFalse);
  });

  test('讀得到存檔就照存檔說的算', () async {
    final store = MemoryStore();
    await store.save(AppState().toSnapshot());
    final s = AppState();
    await s.hydrate(store);
    expect(s.signUpCompleted, isTrue);
  });

  testWidgets('草稿沒填完，完成鈕按不下去', (t) async {
    // completeSignUp() 開頭是 `if (!draft.complete) return;`。
    // 沒有這道 gate 的話它會靜靜地什麼都不做，畫面卻照樣跳出
    // 「帳號已建立」並往下走 —— 一個會說謊的成功訊息。
    t.view.physicalSize = const Size(393 * 3, 852 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final s = AppState()..signUpCompleted = false;
    final d = s.signUpDraft
      ..entry = SignUpEntry.thirdParty
      ..termsAgreed = true
      ..nickname = '阿昶'
      ..heightCm = 175
      ..weightKg = 70
      ..gender = '男'
      ..birthday = DateTime(2000, 1, 1)
      ..commonGoal = kCommonGoals.first
      ..experience = kExperience.first
      ..daysPerWeek = 3
      ..duration = kDurations.first;
    // 器材那一欄故意不填 —— 九項齊全、差一項。
    expect(d.filledCount, 9);
    expect(d.complete, isFalse);

    await t.pumpWidget(
      AppScope(
        state: s,
        child: MaterialApp(home: SignUpScreen(firstRun: true, onFinish: () {})),
      ),
    );
    await t.pumpAndSettle();

    // 差一項時會被送回那一題，不會停在完成頁。
    expect(find.text('看推薦的訓練計畫'), findsNothing,
        reason: '九項齊全還不夠，不該讓人看到完成頁');

    // 就算硬把它推到完成頁，按鈕也要是停用的。
    d.equipment.add(kEquipmentTiers.first);
    expect(d.complete, isTrue);
  });
}
