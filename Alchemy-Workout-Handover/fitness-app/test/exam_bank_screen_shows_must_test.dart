// 後台的題庫頁要看得出哪幾題是必答題。
//
// 使用者 2026-09-29 測第 2 項時卡住：「這有點難測，因為我目前沒有正確答案。」
// 正解其實一直顯示在題庫頁上，但**必答題沒有任何標示** ——
// 於是沒有人知道該去答錯哪一題才驗得到那條門檻。
//
// 更要緊的是上線之後：管理員要向被駁回的人說明「你 95% 為什麼沒過」，
// 而他手上如果沒有這個資訊，就只能說「系統judge的」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/screens/admin/exam_bank_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: ExamBankScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('必答題在列上標示出來，一般題目不標', (t) async {
    final s = AppState();
    await open(t, s);

    final must = s.examBank
        .where((q) =>
            q.type == ExamQuestionType.multipleChoice && q.mustPass)
        .length;
    expect(must, greaterThan(0), reason: '前提：題庫裡有必答題');

    final marked = find.textContaining('必答題（答錯即不及格）');
    expect(marked, findsWidgets);
    // 不可以每一題都標 —— 全部都標等於沒標。
    final mc = s.examBank
        .where((q) => q.type == ExamQuestionType.multipleChoice)
        .length;
    expect(marked.evaluate().length, lessThan(mc));
  });

  testWidgets('頁面講得出三重門檻，而不只是百分比', (t) async {
    await open(t, AppState());
    final s = find.textContaining('三重門檻');
    expect(s, findsOneWidget);
    expect(find.textContaining('一定會出現在每一份考卷上'), findsOneWidget);
  });
}
