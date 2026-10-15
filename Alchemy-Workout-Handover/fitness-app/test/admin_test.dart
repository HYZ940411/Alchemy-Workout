import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/design/components.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/me/more_screen.dart';

import 'developer_mode.dart';

Future<void> _boot(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();
}

Future<void> _openAdmin(WidgetTester t) async {
  await t.tap(find.text('我的').last);
  await t.pumpAndSettle();
  // 「流程示範」那一區收進了開發者模式，一般使用者看不到。
  await enableDeveloperMode(t);
  final list = find
      .descendant(of: find.byType(MoreScreen), matching: find.byType(Scrollable))
      .first;
  final entry =
      find.descendant(of: find.byType(MoreScreen), matching: find.text('管理員後台'));
  await t.scrollUntilVisible(entry, 120, scrollable: list);
  await t.pumpAndSettle();
  await t.tap(entry);
  await t.pumpAndSettle();
}

void main() {
  group('處罰級距：固定階梯累犯制', () {
    test('依累計違規次數決定，與檢舉理由無關', () {
      expect(tierForViolations(1).label, '警告');
      expect(tierForViolations(2).label, '警告');
      expect(tierForViolations(3).label, '社群功能停權 7 天');
      expect(tierForViolations(4).label, '社群功能停權 7 天');
      expect(tierForViolations(5).label, '社群功能停權 30 天');
      expect(tierForViolations(6).label, '社群功能停權 30 天');
      expect(tierForViolations(7).label, '永久停權');
      expect(tierForViolations(99).label, '永久停權');
    });

    test('社群功能停權以上才撤銷教官資格，警告不撤銷', () {
      expect(revokesInstructor(2), isFalse);
      expect(revokesInstructor(3), isTrue);
    });
  });

  group('管理員 Aggregate', () {
    test('已停用者不得執行任何 Command', () {
      const a = Admin(
        id: 'A-9', name: 'X',
        scopes: {AdminScope.contentReview},
        status: AdminStatus.disabled,
      );
      expect(a.can(AdminScope.contentReview), isFalse);
    });

    test('權限組未涵蓋者不得執行該 Command', () {
      const a = Admin(id: 'A-9', name: 'X', scopes: {AdminScope.contentReview});
      expect(a.can(AdminScope.contentReview), isTrue);
      expect(a.can(AdminScope.productManage), isFalse);
    });

    test('三個權限組合計 34 個 Command', () {
      final total =
          adminScopeCommandCount.values.reduce((a, b) => a + b);
      expect(total, 34);
    });
  });

  testWidgets('後台三個入口都開得起來', (t) async {
    await _boot(t);
    await _openAdmin(t);
    for (final e in ['待審佇列', '商品清單', '評分彙總']) {
      await t.tap(find.text(e).last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$e 開啟時發生例外');
      await t.pageBack();
      await t.pumpAndSettle();
    }
  });

  testWidgets('待審佇列四分頁皆可 render', (t) async {
    await _boot(t);
    await _openAdmin(t);
    await t.tap(find.text('待審佇列').last);
    await t.pumpAndSettle();
    for (final tab in ['申訴 2', '教官 2', '公開課表 3', '檢舉 5']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('關閉商品管理權限後，商品清單被擋下', (t) async {
    await _boot(t);
    await _openAdmin(t);
    // 點權限標籤關閉「商品管理」
    await t.tap(find.text('商品管理（6）'));
    await t.pumpAndSettle();
    await t.tap(find.text('商品清單').last);
    await t.pumpAndSettle();
    expect(find.text('沒有「商品管理」權限'), findsOneWidget);
  });

  testWidgets('停用管理員後，待審佇列頁擋在門口', (t) async {
    await _boot(t);
    await _openAdmin(t);
    await t.tap(find.byType(AppSwitch));
    await t.pumpAndSettle();
    expect(find.text('已停用'), findsOneWidget);
    await t.tap(find.text('待審佇列').last);
    await t.pumpAndSettle();
    expect(find.text('沒有「內容審核」權限'), findsOneWidget);
  });

  testWidgets('檢舉：審視 → 成立並處罰', (t) async {
    await _boot(t);
    await _openAdmin(t);
    await t.tap(find.text('待審佇列').last);
    await t.pumpAndSettle();

    // 第二筆（R-2043，待審視）
    final btn = find.widgetWithText(AppButton, '審視檢舉').first;
    await t.ensureVisible(btn);
    await t.pumpAndSettle();
    await t.tap(btn);
    await t.pumpAndSettle();

    final uphold = find.widgetWithText(AppButton, '成立並處罰').first;
    await t.ensureVisible(uphold);
    await t.pumpAndSettle();
    await t.tap(uphold);
    await t.pumpAndSettle();
    expect(find.text('確認處罰'), findsOneWidget);
    // 累計 4 次 → 5 次，級距為社群功能停權 30 天
    expect(find.textContaining('社群功能停權 30 天'), findsWidgets);
  });

  testWidgets('逾期案件才可接手，未逾期者顯示處理中', (t) async {
    await _boot(t);
    await _openAdmin(t);
    await t.tap(find.text('待審佇列').last);
    await t.pumpAndSettle();
    // R-2041 為審視中且已逾檢舉的 7 天時限 → 可接手。
    // 【注意】檢舉是 7 天、申訴才是 72 小時，兩者不同長度。
    expect(find.widgetWithText(AppButton, '接手審核案件（已逾 200 小時）'),
        findsOneWidget);
  });

  testWidgets('商品下架須二次確認', (t) async {
    await _boot(t);
    await _openAdmin(t);
    await t.tap(find.text('商品清單').last);
    await t.pumpAndSettle();
    final off = find.widgetWithText(AppButton, '下架').first;
    await t.ensureVisible(off);
    await t.pumpAndSettle();
    await t.tap(off);
    await t.pumpAndSettle();
    expect(find.text('確認下架'), findsOneWidget);
  });

  testWidgets('後台沒有訂單佇列入口（實體商品已移除）', (t) async {
    await _boot(t);
    await _openAdmin(t);
    expect(find.text('訂單佇列'), findsNothing);
  });
}
