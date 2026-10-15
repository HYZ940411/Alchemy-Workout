import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/screens/shop/checkout_screen.dart';
import 'package:fitness_app/screens/shop/order_detail_screen.dart';
import 'package:fitness_app/screens/shop/product_detail_screen.dart';
import 'package:fitness_app/state/app_state.dart';

/// 〈虛擬商品購買流程〉：選規格與數量 → 確認購買 → 支付 → 發放
///
/// 2026-10-15 移除實體商品後，這支測試原本的收貨資訊、15 分鐘預扣、逾時釋放、
/// 後台出貨都不存在了；留下的是虛擬商品那條流程。
void main() {
  tearDown(() {
    platformConfig.group('commerce').param('coinsPerNtd').value = 5;
    platformConfig.log.clear();
  });

  group('確認購買', () {
    test('購買不會扣庫存 —— 庫存是管理員設的上架條件與顯示用（裁決 A）', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'v2');
      final spec = p.specs.single;
      final before = spec.stock;

      expect(s.confirmPurchase(p, spec, 2), isNull);

      expect(spec.stock, before, reason: '使用者端沒有被信任的寫入權，不扣共用庫存');
      expect(s.orders.first.state, OrderState.pendingPayment);
    });

    test('所選規格的庫存 ≥ 所選數量', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'v2');
      final spec = p.specs.single..stock = 4;
      expect(s.confirmPurchase(p, spec, 5), FailReason.soldOut);
      expect(spec.stock, 4, reason: '被擋下者不得動到庫存');
      expect(s.orders.any((o) => o.productName == p.name && o.qty == 5),
          isFalse);
    });

    test('支付明細拆分：金幣扣到不足為止，其餘以法幣補差額', () {
      final s = AppState();
      s.coins = 200;
      final p = s.products.firstWhere((x) => x.id == 'v3'); // 400 金幣
      s.confirmPurchase(p, p.specs.single, 1);
      final o = s.orders.first;
      expect(o.coinPaid, 200);
      // 差 200 金幣，1 元 ＝ 5 金幣 → 40 元
      expect(o.cashPaid, 40);
      expect(s.coins, 0);
    });

    test('發放數額在確認購買當下凍結', () {
      final s = AppState();
      s.coins = 99999;
      final p = s.products.firstWhere((x) => x.id == 'v1'); // 發 10 點
      s.confirmPurchase(p, p.specs.single, 2);
      expect(s.orders.first.aiCredits, 20);
    });
  });

  group('支付與回補', () {
    test('支付成功 → 已發放', () {
      final s = AppState();
      s.coins = 99999;
      final p = s.products.firstWhere((x) => x.id == 'v3');
      s.confirmPurchase(p, p.specs.first, 1);
      s.payOrder(s.orders.first);
      expect(s.orders.first.state, OrderState.delivered);
    });

    test('支付失敗退回金幣', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'v3');
      final coins = s.coins;
      final stock = p.specs.single.stock;
      s.confirmPurchase(p, p.specs.single, 1);
      s.failPayment(s.orders.first, FailReason.other);

      expect(s.orders.first.state, OrderState.failed);
      expect(s.orders.first.failReason, FailReason.other);
      expect(p.specs.single.stock, stock);
      expect(s.coins, coins);
    });

    test('取消訂單退回金幣', () {
      final s = AppState();
      final p = s.products.firstWhere((x) => x.id == 'v3');
      final coins = s.coins;
      final stock = p.specs.single.stock;
      s.confirmPurchase(p, p.specs.single, 1);
      s.cancelOrder(s.orders.first);

      expect(s.orders.first.state, OrderState.cancelled);
      expect(s.orders.first.cancelledBySystem, isFalse);
      expect(p.specs.single.stock, stock);
      expect(s.coins, coins);
    });

    test('已發放的訂單不可再取消，也不得因無效的取消而回補庫存', () {
      final s = AppState();
      s.coins = 99999;
      final p = s.products.firstWhere((x) => x.id == 'v3');
      s.confirmPurchase(p, p.specs.single, 1);
      final o = s.orders.first;
      s.payOrder(o);
      final stock = p.specs.single.stock;
      final coins = s.coins;
      s.cancelOrder(o);
      expect(o.state, OrderState.delivered);
      expect(p.specs.single.stock, stock);
      expect(s.coins, coins);
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
    testWidgets('商城 → 商品詳情 → 結帳確認 → 訂單詳情，沒有實體商品與收貨資訊', (t) async {
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

      expect(find.text('實體商品'), findsNothing, reason: '商城不再有實體商品分頁');

      await t.tap(find.text('補簽券 ×3').first);
      await t.pumpAndSettle();
      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(find.text('填寫收貨資訊'), findsNothing);

      // 直接前往結帳，中間不再有收貨資訊那一頁。
      await t.tap(find.text('前往結帳'));
      await t.pumpAndSettle();

      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text('支付明細'), findsOneWidget);
      expect(find.text('收貨資訊'), findsNothing);

      await t.tap(find.text('確認購買'));
      await t.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('待付款'), findsWidgets);
      expect(find.textContaining('庫存已為你保留'), findsNothing);
    });
  });
}
