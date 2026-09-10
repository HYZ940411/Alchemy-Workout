// 實體與虛擬是兩條狀態機，終止狀態不同。
//
// 實體：待付款 → 已付款 → 已出貨（終止）。
// 虛擬：待付款 → 已付款 → 已發放（終止）。
//
// 假資料裡有一筆實體訂單標成「已發放」——畫面上寫著貨已經給你了，
// 系統裡卻沒有物流單號，客服查不到東西寄了沒。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('狀態值域', () {
    test('已出貨只給實體，已發放只給虛擬', () {
      expect(orderStateAllowed(ProductKind.physical, OrderState.shipped), isTrue);
      expect(
          orderStateAllowed(ProductKind.virtual, OrderState.shipped), isFalse);
      expect(
          orderStateAllowed(ProductKind.virtual, OrderState.delivered), isTrue);
      expect(orderStateAllowed(ProductKind.physical, OrderState.delivered),
          isFalse);
    });

    test('出貨前的退款只適用實體', () {
      expect(
          orderStateAllowed(ProductKind.physical, OrderState.refunded), isTrue);
      expect(orderStateAllowed(ProductKind.virtual, OrderState.refunded),
          isFalse,
          reason: '虛擬商品已定案不自動退款');
    });

    test('待付款、已付款、已取消、已失敗兩邊共用', () {
      for (final st in [
        OrderState.pendingPayment,
        OrderState.paid,
        OrderState.cancelled,
        OrderState.failed,
      ]) {
        for (final k in ProductKind.values) {
          expect(orderStateAllowed(k, st), isTrue, reason: '$k / $st');
        }
      }
    });
  });

  group('實際資料', () {
    test('每一筆訂單的狀態都落在該類商品的值域內', () {
      final s = AppState();
      for (final o in s.orders) {
        expect(orderStateAllowed(o.kind, o.state), isTrue,
            reason: '${o.productName}（${o.kind.name}）'
                '不該是「${orderStateNames[o.state]}」');
      }
    });

    test('已出貨的實體訂單一定有物流單號', () {
      final s = AppState();
      for (final o in s.orders.where((o) => o.state == OrderState.shipped)) {
        expect(o.trackingNo, isNotNull,
            reason: '${o.productName} 已出貨卻查不到物流單號');
        expect(o.trackingNo, isNotEmpty);
      }
    });

    test('走完虛擬購買流程，終止狀態是已發放', () {
      final s = AppState();
      final o = Order(
        id: 'V-x',
        productName: 'AI 點數 ×10',
        spec: '10 點',
        qty: 1,
        kind: ProductKind.virtual,
        placedAt: s.now,
        coinPaid: 1500,
        cashPaid: 0,
        state: OrderState.pendingPayment,
      );
      s.orders.insert(0, o);
      s.payOrder(o);
      expect(o.state, OrderState.delivered);
      expect(orderStateAllowed(o.kind, o.state), isTrue);
    });

    test('走完實體出貨，終止狀態是已出貨', () {
      final s = AppState();
      final o = s.adminOrders.firstWhere((o) => o.state == '已付款');
      s.shipOrder(o, trackingNo: 'TW123');
      final mine = s.orders.where((u) => u.id == o.id);
      for (final u in mine) {
        expect(u.state, OrderState.shipped);
        expect(orderStateAllowed(u.kind, u.state), isTrue);
      }
    });
  });
}
