// 虛擬商品的發放失敗。
//
// 2026-10-15 移除實體商品後，這支測試原本守的「付款後進出貨佇列」「後台出貨」
// 都不存在了（出貨佇列整個移除）；只剩發放失敗的重試與轉人工。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('虛擬商品的發放失敗', () {
    Order buyVirtual(AppState s) {
      final p = s.products.firstWhere((x) => x.specs.any((sp) => sp.stock > 0));
      s.coins = 999999;
      expect(s.confirmPurchase(p, p.specs.first, 1), isNull);
      final o = s.orders.first;
      o.state = OrderState.paid; // 直接進到等待發放
      return o;
    }

    test('失敗會重試，訂單狀態不變、不自動退款', () {
      final s = AppState();
      final o = buyVirtual(s);
      expect(o.awaitingDelivery, isTrue);
      s.deliverOrder(o, fails: true);
      expect(o.state, OrderState.paid, reason: '發放失敗不改變訂單狀態');
      expect(o.deliveryRetries, 1);
      expect(o.deliveryFailReason, isNotNull);
      expect(o.deliveryManual, isFalse);
    });

    test('重試用完轉人工處理', () {
      final s = AppState();
      final o = buyVirtual(s);
      for (var i = 0; i < kDeliveryMaxRetries + 1; i++) {
        s.deliverOrder(o, fails: true);
      }
      expect(o.deliveryManual, isTrue);
      expect(s.manualDeliveryOrders, contains(o));
    });

    test('後來成功了就清掉失敗痕跡', () {
      final s = AppState();
      final o = buyVirtual(s);
      s.deliverOrder(o, fails: true);
      s.deliverOrder(o);
      expect(o.state, OrderState.delivered);
      expect(o.deliveryFailReason, isNull);
      expect(o.deliveryManual, isFalse);
    });
  });
}
