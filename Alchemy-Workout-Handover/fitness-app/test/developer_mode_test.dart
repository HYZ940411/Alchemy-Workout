// 開發者模式的隱藏入口。
//
// 示範與除錯用的畫面（管理員後台、骨架屏樣式集、模擬對方、模擬時鐘）
// 不是使用者功能，前台不該看得到；但它們又還在用，不能刪。
// 解法是長按「我的」頁首才展開。
//
// 這份測試釘住的是**入口本身**：預設關、長按開、再長按關，
// 以及開關真的有換掉畫面上的東西。其他要走那些畫面的測試
// 一律改用 developer_mode.dart 的輔助函式，不重複這段手勢。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/screens/train/decay_screen.dart';

import 'developer_mode.dart';

Future<void> _openMore(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
  await t.tap(find.text('我的').last);
  await t.pumpAndSettle();
}

Finder _moreList() => find
    .descendant(of: find.byType(MoreScreen), matching: find.byType(Scrollable))
    .first;

/// 「流程示範」在整頁最下面，要捲到底才看得到有沒有。
Future<void> _scrollToBottom(WidgetTester t) async {
  await t.drag(_moreList(), const Offset(0, -4000));
  await t.pumpAndSettle();
  await t.drag(_moreList(), const Offset(0, -4000));
  await t.pumpAndSettle();
}

/// 頁首在最上面，捲下去之後就長按不到了。
Future<void> _scrollToTop(WidgetTester t) async {
  await t.drag(_moreList(), const Offset(0, 8000));
  await t.pumpAndSettle();
}

void main() {
  group('開發者模式的隱藏入口', () {
    testWidgets('預設是關的 —— 前台看不到流程示範那一區', (t) async {
      await _openMore(t);
      await _scrollToBottom(t);

      expect(find.text('流程示範'), findsNothing);
      expect(find.text('管理員後台'), findsNothing,
          reason: '一般使用者不該看得到後台入口');
      expect(find.text('骨架屏與錯誤頁'), findsNothing);
    });

    testWidgets('長按頁首才展開', (t) async {
      await _openMore(t);
      // longPress 壓的是頁首的**正中心**，那裡是兩張統計卡之間的空隙。
      // 這正是要釘住的事：GestureDetector 若用預設的 deferToChild，
      // 空隙上的長按會穿過去給底下的清單，使用者壓了沒反應。
      await t.longPress(find.byKey(moreHeaderKey));
      await t.pumpAndSettle();

      // 長按有回饋，不然使用者不知道自己做了什麼。
      expect(find.text('開發者模式：開'), findsOneWidget);

      await _scrollToBottom(t);
      expect(find.text('流程示範'), findsOneWidget);
      expect(find.text('管理員後台'), findsOneWidget);
    });

    testWidgets('再長按一次就收回去', (t) async {
      // 斷言看的是「那一區在不在」，不是 SnackBar 寫什麼 ——
      // 兩則 SnackBar 會排隊，用文字判斷等於在測 ScaffoldMessenger 的時序。
      // 提示文字由上一條測試釘住就夠了。
      await _openMore(t);
      await t.longPress(find.byKey(moreHeaderKey));
      await t.pumpAndSettle();
      await _scrollToBottom(t);
      expect(find.text('流程示範'), findsOneWidget, reason: '第一次長按要打開');

      await _scrollToTop(t);
      await t.longPress(find.byKey(moreHeaderKey));
      await t.pumpAndSettle();
      await _scrollToBottom(t);
      expect(find.text('流程示範'), findsNothing, reason: '第二次長按要收回去');
    });
  });

  group('退步頁的模擬時鐘', () {
    Future<void> openDecay(WidgetTester t) async {
      final list = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('能力值退步狀態'));
      await t.scrollUntilVisible(entry, 120, scrollable: list);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();
    }

    // 模擬時鐘在退步頁的最下面。ListView 是延遲建構的，不捲到底
    // 那一段根本不會被建出來 —— 直接斷言 findsNothing 會是假的綠燈。
    Future<void> scrollDecayToBottom(WidgetTester t) async {
      final page = find
          .descendant(
              of: find.byType(DecayScreen), matching: find.byType(Scrollable))
          .first;
      await t.drag(page, const Offset(0, -4000));
      await t.pumpAndSettle();
      await t.drag(page, const Offset(0, -4000));
      await t.pumpAndSettle();
    }

    testWidgets('前台看不到 —— 快轉時間不是使用者該有的能力', (t) async {
      await _openMore(t);
      await openDecay(t);
      await scrollDecayToBottom(t);
      expect(find.text('模擬時鐘'), findsNothing);
      expect(find.text('＋10 天'), findsNothing);
    });

    testWidgets('開發者模式打開後才看得到', (t) async {
      await _openMore(t);
      await enableDeveloperMode(t);
      await openDecay(t);
      await scrollDecayToBottom(t);
      expect(find.text('模擬時鐘'), findsOneWidget);
      expect(find.text('＋10 天'), findsOneWidget);
    });
  });
}
