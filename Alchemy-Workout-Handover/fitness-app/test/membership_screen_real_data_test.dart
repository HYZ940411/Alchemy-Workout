// 會員頁：新帳號打開不會當掉，而且權益對照的是真的資料。
//
// 2026-09-28 使用者回報「會員頁是灰色的，無法顯示任何資料」。
//
// 元兇是這一行：
//     '你已累積 ${s.snapshots.keys.reduce((a, b) => a > b ? a : b)} 天…'
// **`reduce` 對空集合丟 StateError**，而新帳號一份能力值快照都沒有。
// 整頁因此炸掉 —— 使用者看到的是一片灰。
//
// 同一段還有兩處寫死的假資料（「你目前 5 / 5」「你這個月用了 6 次，
// 花了 900 金幣」）。這一頁的用途是「權益逐條對照使用者現況」，
// 對照的若是假的，它就沒有存在的理由。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/shop/membership_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: MembershipScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('一份能力值快照都沒有時也打得開', (t) async {
    final s = AppState()..snapshots.clear();
    expect(s.snapshots, isEmpty, reason: '前提：要真的是空的');
    await open(t, s);
    expect(lastBuildError(), isNull);
    expect(find.text('會員訂閱'), findsOneWidget);
    expect(find.textContaining('還沒有能力值歷史'), findsOneWidget);
  });

  testWidgets('有快照時講得出實際天數', (t) async {
    final s = AppState();
    if (s.snapshots.isEmpty) return;
    await open(t, s);
    expect(find.textContaining('你已累積 ${s.snapshots.length} 天'), findsOneWidget);
  });

  group('權益對照的是真的資料，不是寫死的字串', () {
    testWidgets('自訂訓練講的是我真的有幾份', (t) async {
      final s = AppState();
      await open(t, s);
      expect(find.textContaining('你目前 ${s.myPlanCount}'), findsOneWidget);
      // 「你目前 5 / 5」是原本寫死的那一行。
      if (s.myPlanCount != 5 || s.customPlanQuota != 5) {
        expect(find.text('你目前 5 / 5'), findsNothing);
      }
    });

    testWidgets('AI 點數講的是我真的剩幾點', (t) async {
      final s = AppState();
      await open(t, s);
      expect(find.textContaining('900 金幣'), findsNothing,
          reason: '「你這個月用了 6 次，花了 900 金幣」是寫死的');
      expect(find.textContaining('永久點數 ${s.aiPermanent} 點'), findsWidgets);
    });

    testWidgets('會員與非會員看到不同的句子', (t) async {
      final s = AppState();
      await open(t, s);
      expect(find.textContaining('沒有每月配發'), findsOneWidget);

      s.subscribe(yearly: false);
      await t.pumpAndSettle();
      expect(find.textContaining('本月剩餘 ${s.aiMonthly} 點'), findsOneWidget);
      expect(find.textContaining('會員不限數量'), findsOneWidget);
    });
  });
}

/// 這一輪 pump 有沒有丟出例外。`pumpAndSettle` 不會因為 build 丟例外而失敗，
/// 它只把例外記進 `takeException` —— 不主動去拿就等於沒驗到。
Object? lastBuildError() => TestWidgetsFlutterBinding
    .instance.takeException();
