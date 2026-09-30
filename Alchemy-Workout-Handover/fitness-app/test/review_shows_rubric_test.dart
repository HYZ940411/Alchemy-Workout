// 審核簡答題的人要看得到評分細則。
//
// 2026-09-29 的覆核意見要求「細則具體到兩位審核者依此評分會得到同一個
// 結果」，於是題庫補上了通過要素、不通過條件與追問範例。
//
// **但它們一開始只存在資料裡** —— 審核畫面照舊只顯示題目與作答。
// 細則沒送到判分的人面前等於沒寫，人工審核會退回各憑印象，
// 而那正是這次要修的東西。與「經驗值只有刪帳號頁看得到」同型：
// 做好了，路沒接上。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/screens/admin/review_queue_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  Future<void> openInstructorTab(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: ReviewQueueScreen()),
    ));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('教官 ').last);
    await t.pumpAndSettle();
  }

  testWidgets('待審的教官案件會帶出該題的評分細則', (t) async {
    final s = AppState();
    expect(s.instructorCases, isNotEmpty, reason: '前提：有待審案件');

    await openInstructorTab(t, s);

    expect(find.textContaining('通過要素'), findsWidgets);
    expect(find.textContaining('直接不通過'), findsWidgets);
    expect(find.textContaining('可以這樣追問'), findsWidgets,
        reason: '追問是辨識背稿者的唯一手段，要在審核當下看得到');
  });

  testWidgets('示範案件的題目文字與題庫一致 —— 否則回查不到細則', (t) async {
    final s = AppState();
    final bankText = s.examBank
        .where((q) => q.type == ExamQuestionType.shortAnswer)
        .map((q) => q.text)
        .toSet();
    for (final c in s.instructorCases) {
      for (final (q, _) in c.answers) {
        expect(bankText, contains(q),
            reason: '「${q.substring(0, 12)}…」不在題庫裡，細則會回查失敗');
      }
    }
  });

  testWidgets('題庫裡找不到的題目不顯示細則，而不是顯示別題的', (t) async {
    // 拿別題的標準判這一題，比沒有標準更糟。
    final s = AppState();
    for (final c in s.instructorCases) {
      c.answers
        ..clear()
        ..add(('一個題庫裡沒有的題目', '隨便寫的答案'));
    }
    await openInstructorTab(t, s);
    expect(find.textContaining('通過要素'), findsNothing);
    expect(find.text('隨便寫的答案'), findsWidgets, reason: '作答本身仍要看得到');
  });
}
