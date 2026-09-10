import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/shop/checkout_screen.dart';
import 'package:fitness_app/screens/shop/order_detail_screen.dart';
import 'package:fitness_app/screens/shop/product_detail_screen.dart';
import 'package:fitness_app/screens/shop/shipping_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 〈實體商品購買流程〉：選規格與數量 → 填收貨資訊 → 確認購買 → 支付 → 出貨
void main() {
  tearDown(() {
    platformConfig.group('commerce').param('holdMinutes').value = 15;
    platformConfig.group('commerce').param('coinsPerNtd').value = 5;
    platformConfig.log.clear();
  });

  const shipping = ShippingInfo(
    name: '測試人',
    phone: '0912345678',
    zip: '100',
    address: '測試路 1 號',
  );

  group('收貨資訊', () {
    test('五個欄位只有備註選填', () {
      expect(
          ShippingInfo.validate(
              name: '', phone: '0912345678', zip: '100', address: 'x'),
          contains('姓名'));
      expect(
          ShippingInfo.validate(
              name: 'a', phone: '', zip: '100', address: 'x'),
          contains('手機'));
      expect(
          ShippingInfo.validate(
              name: 'a', phone: '0912345678', zip: '', address: 'x'),
          contains('郵遞區號'));
      expect(
          ShippingInfo.validate(
              name: 'a', phone: '0912345678', zip: '100', address: ''),
          contains('地址'));
      // 備註沒有進 validate，本來就不擋。
      expect(
          ShippingInfo.validate(
              name: 'a', phone: '0912345678', zip: '100', address: 'x'),
          isNull);
    });

    test('手機號碼須符合格式', () {
      expect(
          ShippingInfo.validate(
              name: 'a', phone: '12345', zip: '100', address: 'x'),
          contains('格式'));
      // 帶連字號的照樣接受 —— 使用者不該為了格式重打一次。
      expect(
          ShippingInfo.validate(
              name: 'a', phone: '0912-345-678', zip: '100', address: 'x'),
          isNull);
    });
  });

  group('確認購買', () {
    test('預扣庫存，而非支付成功後才扣減', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      final spec = p.specs.single;
      final before = spec.stock;

      expect(s.confirmPurchase(p, spec, 2, shipping: shipping), isNull);

      expect(spec.stock, before - 2, reason: '確認購買當下就扣');
      expect(s.orders.first.state, OrderState.pendingPayment);
    });

    test('所選規格的庫存 ≥ 所選數量', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g1');
      final spec = p.specs.firstWhere((x) => x.name == 'M'); // 庫存 4
      expect(s.confirmPurchase(p, spec, 5, shipping: shipping),
          FailReason.soldOut);
      expect(spec.stock, 4, reason: '被擋下者不得動到庫存');
      expect(s.orders.any((o) => o.spec == 'M' && o.qty == 5), isFalse);
    });

    test('實體商品沒有收貨資訊不得成立訂單', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      expect(s.confirmPurchase(p, p.specs.single, 1), FailReason.other);
      expect(p.specs.single.stock, 40);
    });

    test('支付明細拆分：金幣扣到不足為止，其餘以法幣補差額', () {
      final s = AppState();
      s.coins = 200;
      final p = s.products.firstWhere((x) => x.id == 'g3'); // 350 金幣
      s.confirmPurchase(p, p.specs.single, 1, shipping: shipping);
      final o = s.orders.first;
      expect(o.coinPaid, 200);
      // 差 150 金幣，1 元 ＝ 5 金幣 → 30 元
      expect(o.cashPaid, 30);
      expect(s.coins, 0);
    });

    test('每筆訂單於確認購買當下鎖定自己的到期時點', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      s.confirmPurchase(p, p.specs.single, 1, shipping: shipping);
      final first = s.orders.first.holdUntil!;

      // 事後把保留時間改成 60 分鐘，不影響已成立的訂單。
      s.applySettings('commerce', {'holdMinutes': 60});
      expect(s.orders.first.holdUntil, first);
    });

    test('虛擬商品沒有預扣到期時點', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.kind == ProductKind.virtual);
      s.confirmPurchase(p, p.specs.first, 1);
      expect(s.orders.first.holdUntil, isNull);
    });

    test('收貨資訊會被記住，供下次預帶', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      s.confirmPurchase(p, p.specs.single, 1, shipping: shipping);
      expect(s.lastShipping?.name, '測試人');
    });
  });

  group('支付與釋放', () {
    test('支付成功：實體 → 已付款，虛擬 → 已發放', () {
      final s = AppState();
      final phy = s.products.firstWhere((x) => x.id == 'g3');
      s.confirmPurchase(phy, phy.specs.single, 1, shipping: shipping);
      s.payOrder(s.orders.first);
      expect(s.orders.first.state, OrderState.paid);

      final vir = s.products.firstWhere((x) => x.kind == ProductKind.virtual);
      s.confirmPurchase(vir, vir.specs.first, 1);
      s.payOrder(s.orders.first);
      expect(s.orders.first.state, OrderState.delivered);
    });

    test('支付失敗一併釋放預扣庫存與金幣', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      final coins = s.coins;
      final stock = p.specs.single.stock;
      s.confirmPurchase(p, p.specs.single, 1, shipping: shipping);
      s.failPayment(s.orders.first, FailReason.other);

      expect(s.orders.first.state, OrderState.failed);
      expect(s.orders.first.failReason, FailReason.other);
      expect(p.specs.single.stock, stock);
      expect(s.coins, coins);
    });

    test('取消訂單一併釋放預扣庫存與金幣', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      final coins = s.coins;
      final stock = p.specs.single.stock;
      s.confirmPurchase(p, p.specs.single, 1, shipping: shipping);
      s.cancelOrder(s.orders.first);

      expect(s.orders.first.state, OrderState.cancelled);
      expect(s.orders.first.cancelledBySystem, isFalse);
      expect(p.specs.single.stock, stock);
      expect(s.coins, coins);
    });

    test('已付款的訂單不可再取消', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      s.confirmPurchase(p, p.specs.single, 1, shipping: shipping);
      final o = s.orders.first;
      s.payOrder(o);
      final stock = p.specs.single.stock;
      s.cancelOrder(o);
      expect(o.state, OrderState.paid);
      expect(p.specs.single.stock, stock, reason: '不得因無效的取消而回補庫存');
    });

    test('預扣逾時：系統取消並釋放，且與使用者自行取消可區別', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'g3');
      final stock = p.specs.single.stock;
      // 保留時間設為最短，讓它立刻到期。
      s.applySettings('commerce', {'holdMinutes': 1});
      s.confirmPurchase(p, p.specs.single, 1, shipping: shipping);
      final o = s.orders.first;
      expect(s.releaseExpiredHolds(), isEmpty, reason: '還沒到期');

      // 把到期時點推到過去（模擬時間流逝）
      final expired = Order(
        id: o.id,
        productName: o.productName,
        spec: o.spec,
        qty: o.qty,
        kind: o.kind,
        placedAt: o.placedAt,
        coinPaid: o.coinPaid,
        cashPaid: o.cashPaid,
        state: OrderState.pendingPayment,
        shipping: o.shipping,
        holdUntil: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      s.orders[s.orders.indexOf(o)] = expired;

      expect(s.releaseExpiredHolds(), [o.id]);
      expect(expired.state, OrderState.cancelled);
      expect(expired.cancelledBySystem, isTrue);
      expect(p.specs.single.stock, stock);
    });

    test('已付款的訂單不受逾時釋放影響', () {
      final s = AppState();
      final paid = s.orders.where((o) => o.state == OrderState.shipped).length;
      s.releaseExpiredHolds();
      expect(
          s.orders.where((o) => o.state == OrderState.shipped).length, paid);
    });
  });

  group('出貨', () {
    test('管理員出貨 → 使用者端同步轉為已出貨，並標紅點', () {
      final s = AppState();
      final admin = s.adminOrders.firstWhere((o) => o.state == '已付款');
      // 使用者端補一筆同 ID 的已付款訂單
      s.orders.insert(
        0,
        Order(
          id: admin.id,
          productName: admin.product,
          spec: admin.spec,
          qty: admin.qty,
          kind: ProductKind.physical,
          placedAt: admin.placedAt,
          coinPaid: admin.coinAmount,
          cashPaid: 0,
          state: OrderState.paid,
        ),
      );
      s.shipOrder(admin, trackingNo: 'TW123');

      expect(admin.state, '已出貨');
      expect(s.orders.first.state, OrderState.shipped);
      expect(s.orders.first.trackingNo, 'TW123');
      expect(s.unreadShipped.contains(admin.id), isTrue,
          reason: '出貨通知為 App 內通知類，以紅點呈現');

      s.markOrderSeen(s.orders.first);
      expect(s.unreadShipped.contains(admin.id), isFalse);
    });
  });

  group('補差額試算', () {
    test('依金幣對法幣比率換算，不足 1 元進位', () {
      expect(cashForShortfall(0), 0);
      expect(cashForShortfall(-50), 0);
      expect(cashForShortfall(150), 30);
      expect(cashForShortfall(151), 31);
    });

    test('比率為平台級可調參數', () {
      final s = AppState();
      s.applySettings('commerce', {'coinsPerNtd': 10});
      expect(cashForShortfall(150), 15);
    });
  });

  group('走一遍購買鏈', () {
    testWidgets('商品詳情 → 收貨資訊 → 結帳確認 → 訂單詳情', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      // 底部導覽的第四格是「商店」，進去後才是「商城」清單。
      await t.tap(find.text('商店').last);
      await t.pumpAndSettle();
      await t.tap(find.text('商城').first);
      await t.pumpAndSettle();

      // 實體商品分頁的第三張卡，393×852 下不需捲動即可見。
      await t.tap(find.text('搖搖杯').first);
      await t.pumpAndSettle();
      expect(find.byType(ProductDetailScreen), findsOneWidget);

      await t.tap(find.text('填寫收貨資訊'));
      await t.pumpAndSettle();
      expect(find.byType(ShippingScreen), findsOneWidget);
      // 預帶上次填寫的內容，直接按下一步即可
      await t.tap(find.text('下一步：確認訂單'));
      await t.pumpAndSettle();

      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text('支付明細'), findsOneWidget);

      await t.tap(find.text('確認購買'));
      await t.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('待付款'), findsWidgets);
      expect(find.textContaining('庫存已為你保留'), findsOneWidget);
    });
  });
}
