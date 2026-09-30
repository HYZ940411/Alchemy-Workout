// 有人想拜我為師，師徒頁要講出來。
//
// ## 使用者 2026-09-29 實測 T1 = C：「重整也沒有」
//
// A 送出拜師申請、雲端那筆在、B 是教官、申請未逾期 —— 而 B 看不到。
//
// 因為**拜師申請進的是 `inbox`，而收件匣的入口在「我的 → 收件匣」**。
// 師徒頁上沒有任何跡象：一位教官打開師徒頁，看到的是
// 「我的學徒」按鈕與一份拜師清單，而有人正在等他回應。
//
// **回應仍然在收件匣做** —— 接受／拒絕的判定（名額、停權、逾期）
// 已經在那裡，複製第二份就會有兩份慢慢長不一樣的規則。
// 這一塊只負責讓他知道有這件事。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/screens/social/mentor_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  /// 一位已解鎖師徒的教官。
  AppState instructor() => AppState(demo: false)
    ..markMentorUnlocked()
    ..isInstructor = true;

  InboundRequest apply(String from) => InboundRequest(
        id: 'r-$from',
        kind: InboundKind.apprenticeApply,
        from: from,
        subject: from,
        fromRank: 20,
        sentAt: DateTime.now(),
      );

  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: Scaffold(body: MentorScreen())),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('收到拜師申請 → 師徒頁最上面就看得到', (t) async {
    final s = instructor()..receiveInbound(apply('阿明'));
    await open(t, s);
    expect(find.text('有 1 位想拜你為師'), findsOneWidget);
    expect(find.text('阿明'), findsWidgets);
    expect(find.text('去收件匣回應'), findsOneWidget);
  });

  testWidgets('兩個人申請 → 數字與名字都對', (t) async {
    final s = instructor()
      ..receiveInbound(apply('阿明'))
      ..receiveInbound(apply('小華'));
    await open(t, s);
    expect(find.text('有 2 位想拜你為師'), findsOneWidget);
    // 收件匣是新的排前面（`receiveInbound` 插在 index 0）。
    expect(find.text('小華、阿明'), findsOneWidget);
  });

  testWidgets('沒有人申請就不要放一塊空的', (t) async {
    await open(t, instructor());
    expect(find.textContaining('想拜你為師'), findsNothing);
  });

  testWidgets('逾期的申請不算 —— 那一筆已經回應不了了', (t) async {
    final s = instructor()
      ..receiveInbound(InboundRequest(
        id: 'old',
        kind: InboundKind.apprenticeApply,
        from: '很久以前的人',
        subject: '很久以前的人',
        fromRank: 20,
        sentAt: DateTime(2020, 1, 1),
      ));
    await open(t, s);
    expect(find.textContaining('想拜你為師'), findsNothing);
  });

  testWidgets('團隊邀請不會被算成拜師申請', (t) async {
    final s = instructor()
      ..receiveInbound(InboundRequest(
        id: 'ti',
        kind: InboundKind.teamInvite,
        from: '某隊長',
        subject: '某支隊伍',
        fromRank: 20,
        sentAt: DateTime.now(),
      ));
    await open(t, s);
    expect(find.textContaining('想拜你為師'), findsNothing);
  });
}
