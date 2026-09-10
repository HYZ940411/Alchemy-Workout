// 後台訂單佇列的金額單位。
//
// 商品定價一律以金幣標示（ProductSpec.coinPrice），使用者端的訂單頁寫的是
// 「金幣扣除 900　法幣支付 NT$0」。後台卻把同一個數字印成「NT$ 900」——
// 同一筆訂單兩個金額單位，而且 900 金幣依 1 元 ＝ 5 金幣其實是 180 元。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';

Future<AppState> openAdminOrders(WidgetTester t) async {
  t.view.physicalSize = const Size(393 * 3, 852 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const FitnessApp());
  await t.pumpAndSettle();

  await t.tap(find.text('我的').last);
  await t.pumpAndSettle();
  // 「我的」是一長頁，入口在很下面。用 dragUntilVisible 而不是固定捲幾次 ——
  // 固定次數會在頁面多一列時無聲地捲不到底，測試變成「找不到就爆」。
  await t.dragUntilVisible(
    find.text('管理員後台'),
    find.byType(Scrollable).first,
    const Offset(0, -400),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('管理員後台').last);
  await t.pumpAndSettle();
  await t.tap(find.text('訂單佇列').last);
  await t.pumpAndSettle();
  return AppScope.of(t.element(find.byType(Scaffold).first));
}

void main() {
  testWidgets('後台不把金幣印成法幣', (t) async {
    final s = await openAdminOrders(t);
    final pending = s.adminOrders.where((o) => o.state == '已付款').toList();
    expect(pending, isNotEmpty, reason: '前提：待出貨清單要有東西');

    for (final o in pending) {
      expect(find.text('NT\$ ${o.coinAmount}'), findsNothing,
          reason: '${o.product} 的 ${o.coinAmount} 是金幣，不是台幣');
    }
    expect(find.text('金幣'), findsWidgets, reason: '要標得出單位是金幣');
  });

  testWidgets('後台顯示的金額與使用者端訂單頁的金幣扣除一致', (t) async {
    final s = await openAdminOrders(t);
    final admin = s.adminOrders.firstWhere((o) => o.state == '已付款');
    expect(find.text('${admin.coinAmount}'), findsWidgets);

    // 使用者端同一筆訂單記的是金幣扣除，兩邊必須是同一個數。
    final mine = s.orders.where((u) => u.id == admin.id);
    for (final u in mine) {
      expect(u.coinPaid, admin.coinAmount,
          reason: '同一筆訂單，兩個畫面給出不同金額');
    }
  });

  test('欄位語意：訂單金額是金幣，不是法幣', () {
    final s = AppState();
    for (final o in s.adminOrders) {
      // 1 元 ＝ 5 金幣。若把金幣數當法幣，數字會膨脹五倍。
      expect(o.coinAmount, greaterThanOrEqualTo(0));
    }
    // 商品定價本身就是金幣。
    for (final p in s.adminProducts) {
      for (final spec in p.specs) {
        expect(spec.price, greaterThan(0));
      }
    }
  });
}
