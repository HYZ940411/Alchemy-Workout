// 開發者模式「略過換隊冷卻」（`[QA-09]`，使用者選 A，2026-10-17）。
//
// 換隊冷卻只存在記憶體，測的人一退隊就被鎖住。這個開關讓測試能直接換隊，
// 但**不改規格**：預設關、不進存檔、只在開發者模式開著時才生效。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/screens/me/settings_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 剛退出隊伍的人（示範帳號的隊伍已加入 20 天，不在誤入的免罰窗口內，所以會進冷卻）。
AppState _justLeft() {
  final s = AppState();
  s.leaveTeam();
  return s;
}

PublicTeam _open(AppState s) =>
    s.publicTeams.firstWhere((t) => t.isPublic && !t.isFull);

void main() {
  test('預設：退隊後在冷卻中，不能申請加入別隊', () {
    final s = _justLeft();
    expect(s.switchCooldownLeft, greaterThan(Duration.zero));
    expect(s.joinBlockedReason(_open(s)), contains('換隊冷卻中'));
  });

  test('只開開關、沒開開發者模式：冷卻照舊（開關不能單獨生效）', () {
    final s = _justLeft()..devSkipTeamCooldown = true;
    expect(s.developerMode, isFalse);
    expect(s.switchCooldownLeft, greaterThan(Duration.zero));
    expect(s.joinBlockedReason(_open(s)), contains('換隊冷卻中'));
  });

  test('開發者模式加開關：冷卻當作已結束，可以申請加入', () {
    final s = _justLeft()
      ..toggleDeveloperMode()
      ..devSkipTeamCooldown = true;
    expect(s.switchCooldownLeft, Duration.zero);
    expect(s.joinBlockedReason(_open(s)), isNull);
  });

  test('接受隊長邀請也放行', () {
    final s = _justLeft()
      ..toggleDeveloperMode()
      ..devSkipTeamCooldown = true;
    final t = _open(s);
    s.receiveInbound(InboundRequest(
      id: 'i1',
      kind: InboundKind.teamInvite,
      from: '隊長甲',
      fromRank: 40,
      subject: t.name,
      sentAt: s.now,
    ));
    expect(s.inboundBlockedReason(s.liveInbox.single), isNull);
    expect(s.acceptInbound(s.liveInbox.single), isTrue);
    expect(s.myTeam?.name, t.name);
  });

  test('關掉開關後剩餘的冷卻照舊 —— 開關沒有清掉冷卻紀錄', () {
    final s = _justLeft()
      ..toggleDeveloperMode()
      ..devSkipTeamCooldown = true;
    expect(s.switchCooldownLeft, Duration.zero);
    s.toggleDevSkipTeamCooldown();
    expect(s.switchCooldownLeft, greaterThan(Duration.zero));
    expect(s.teamLeftAt, isNotNull);
  });

  group('畫面', () {
    Future<void> open(WidgetTester t, AppState s) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('開發者模式才有，按下去切換開關', (t) async {
      final s = _justLeft()..toggleDeveloperMode();
      await open(t, s);
      final button = find.widgetWithText(AppButton, '開啟：退隊後立刻可換隊');
      await t.scrollUntilVisible(button, 300,
          scrollable: find.byType(Scrollable).first);
      await t.tap(button);
      await t.pump();
      expect(s.devSkipTeamCooldown, isTrue);
      expect(s.switchCooldownLeft, Duration.zero);
    });

    testWidgets('沒開開發者模式就看不到', (t) async {
      final s = _justLeft();
      await open(t, s);
      expect(find.text('略過換隊冷卻'), findsNothing);
    });
  });
}
