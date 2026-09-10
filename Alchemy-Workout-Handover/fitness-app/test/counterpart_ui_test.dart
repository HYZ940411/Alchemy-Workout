// 兩個新畫面點得動 —— 而且點下去真的改變了狀態。
//
// 畫面爬蟲只從分頁往下走兩層，這兩頁在第三層（我的 → 更多 → …），
// 爬不到。這支補上：把每個按鈕點過一遍，看有沒有爆版或丟例外。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/screens/design/counterpart_screen.dart';
import 'package:fitness_app/screens/social/inbox_screen.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> boot(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(375 * 3, 667 * 3); // 最窄機型
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final s = AppState();
  await t.pumpWidget(AppScope(
    state: s,
    child: MaterialApp(home: child),
  ));
  await t.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('收件匣：空的時候講得出這一頁是幹嘛的', (t) async {
    await boot(t, const InboxScreen());
    expect(find.textContaining('沒有等你回應的請求'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('收件匣：接受按鈕真的把我加進團隊', (t) async {
    final s = await boot(t, const InboxScreen());
    s.leaveTeam();
    s.teamLeftAt = null;
    final team = s.publicTeams.firstWhere((x) => x.isPublic && !x.isFull);
    s.receiveInbound(InboundRequest(
      id: 'i1',
      kind: InboundKind.teamInvite,
      from: '隊長甲',
      fromRank: 40,
      subject: team.name,
      sentAt: s.now,
    ));
    await t.pumpAndSettle();

    expect(find.textContaining(team.name), findsWidgets,
        reason: '前提：這筆邀請要真的被畫出來，否則下面的點擊是空的');
    await t.tap(find.text('接受'));
    await t.pumpAndSettle();

    expect(s.myTeam?.name, team.name);
    expect(find.textContaining('沒有等你回應的請求'), findsOneWidget,
        reason: '處理完就該回到空狀態');
    expect(t.takeException(), isNull);
  });

  testWidgets('收件匣：接不了的時候，按鈕是暗的而且說得出理由', (t) async {
    final s = await boot(t, const InboxScreen());
    expect(s.myTeam, isNotNull, reason: '前提：預設已在某支隊裡');
    final team = s.publicTeams.firstWhere((x) => x.isPublic && !x.isFull);
    s.receiveInbound(InboundRequest(
      id: 'i1',
      kind: InboundKind.teamInvite,
      from: '隊長甲',
      fromRank: 40,
      subject: team.name,
      sentAt: s.now,
    ));
    await t.pumpAndSettle();

    expect(find.textContaining('一次只能屬於一個團隊'), findsWidgets);
    await t.tap(find.text('接受'));
    await t.pumpAndSettle();
    expect(s.myTeam!.name, isNot(team.name), reason: '按了也不該進得去');
  });

  testWidgets('模擬對方：每一列都點得動，不爆版也不丟例外', (t) async {
    final s = await boot(t, const CounterpartScreen());

    // 每一列點一次。點完清單會變（動作消失、新動作出現），
    // 所以每輪重新抓一次，不快取索引。
    var taps = 0;
    for (var round = 0; round < 30; round++) {
      final rows = find.byType(InkWell).evaluate().toList();
      if (round >= rows.length) break;
      final finder = find.byType(InkWell).at(round);
      if (finder.evaluate().isEmpty) break;
      try {
        await t.tap(finder, warnIfMissed: false);
        await t.pumpAndSettle();
        taps++;
      } catch (_) {
        // 捲出畫面外的點不到，不是問題。
      }
      expect(t.takeException(), isNull, reason: '第 $round 列點下去丟了例外');
    }
    expect(taps, greaterThan(3), reason: '只點了 $taps 次，這支測試沒有真的在點');
    expect(s.followers, isNotEmpty);
  });

  testWidgets('模擬對方：沒有待回應的請求時，時間那一節照樣講得出話', (t) async {
    final s = await boot(t, const CounterpartScreen());
    s.sentApplications.clear();
    s.mentorApplications.clear();
    s.inbox.clear();
    // 直接改集合不會觸發重繪 —— 少了這一行，畫面還是舊的，斷言就成了空話。
    s.notifyListeners();
    await t.pumpAndSettle();

    // 「時間」在整頁最底下，375×667 一屏放不下 ——
    // ListView 沒建出來的節點找不到，得先捲下去。
    await t.dragUntilVisible(
      find.text('快轉 8 天，讓待回應的都逾期'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await t.pumpAndSettle();
    expect(find.text('目前沒有待回應的請求'), findsOneWidget);
  });
}
