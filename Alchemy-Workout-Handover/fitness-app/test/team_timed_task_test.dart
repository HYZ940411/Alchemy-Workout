// 團隊限時任務頁的兩件事。
//
// 一、限時任務是**每日**指派、當日有效。標題寫「本週」旁邊寫「當日有效」，
//     同一行自相矛盾。
// 二、「提醒」是催隊友的。自己那一列也給一顆，等於催自己。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> openTeam(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
  await t.tap(find.text('社群').last);
  await t.pumpAndSettle();
  await t.tap(find.text('團隊').last);
  await t.pumpAndSettle();
  return AppScope.of(t.element(find.byType(Scaffold).first));
}

void main() {
  testWidgets('標題講的週期與有效期一致', (t) async {
    await openTeam(t);
    expect(find.text('本週限時任務'), findsNothing,
        reason: '限時任務每日指派，不是每週');
    expect(find.text('今日限時任務'), findsOneWidget);
    expect(find.textContaining('當日有效'), findsWidgets);
  });

  testWidgets('自己那一列沒有「提醒」', (t) async {
    final s = await openTeam(t);
    final tally = s.timedTally;

    // 前提：自己確實還沒完成，否則這條測不到東西。
    expect(tally.credited.contains(s.displayName), isFalse,
        reason: '前提：假資料裡自己尚未完成今日限時任務');
    expect(find.text(s.displayName), findsWidgets);

    final myRow = find.ancestor(
      of: find.text(s.displayName),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: myRow.last, matching: find.text('提醒')),
      findsNothing,
      reason: '催自己沒有意義',
    );
  });

  testWidgets('還沒完成的隊友仍然催得動', (t) async {
    final s = await openTeam(t);
    final tally = s.timedTally;
    final other = tally.members
        .map((m) => m.name)
        .firstWhere((n) => n != s.displayName && !tally.credited.contains(n));

    final row = find.ancestor(
      of: find.text(other),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: row.last, matching: find.text('提醒')),
      findsOneWidget,
      reason: '「就差你了」的互相催促正是限時任務的核心設計',
    );
  });
}
