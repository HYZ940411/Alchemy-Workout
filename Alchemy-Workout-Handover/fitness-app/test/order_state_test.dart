// 商城只有虛擬商品（2026-10-15 使用者裁決移除實體商品）。
//
// 訂單狀態只剩虛擬的那條：待付款 → 已付款 → 已發放（終止）；
// 另有已取消、已失敗兩個終止狀態。「已出貨」「已退款」屬實體商品，已移除。
//
// 這支測試的任務是**擋住實體商品被不小心加回來**：狀態值域、假資料、
// 後台商品清單三處都不該再出現實體商品的痕跡。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

const _removedNames = ['健金術 訓練 T', '助力帶', '搖搖杯', '限量毛巾（春季）'];

void main() {
  group('狀態值域', () {
    test('只有虛擬商品那條狀態機的五個值', () {
      expect(OrderState.values, [
        OrderState.pendingPayment,
        OrderState.paid,
        OrderState.delivered,
        OrderState.cancelled,
        OrderState.failed,
      ]);
    });

    test('每個狀態都有顯示名稱', () {
      for (final st in OrderState.values) {
        expect(orderStateNames[st], isNotNull, reason: '$st');
      }
    });

    test('失敗原因只剩餘額不足、商品售完（消耗品庫存）、其他', () {
      expect(FailReason.values,
          [FailReason.insufficientBalance, FailReason.soldOut, FailReason.other]);
    });
  });

  group('實際資料', () {
    test('商城、訂單、後台商品清單都沒有實體商品', () {
      final s = AppState();
      for (final n in _removedNames) {
        expect(s.products.map((p) => p.name), isNot(contains(n)));
        expect(s.orders.map((o) => o.productName), isNot(contains(n)));
        expect(s.adminProducts.map((p) => p.name), isNot(contains(n)));
      }
    });

    test('每一筆訂單都落在五個狀態內，且有顯示名稱', () {
      final s = AppState();
      expect(s.orders, isNotEmpty, reason: '前提：示範資料有訂單');
      for (final o in s.orders) {
        expect(orderStateNames[o.state], isNotNull);
      }
    });

    test('走完虛擬購買流程，終止狀態是已發放', () {
      final s = AppState();
      final o = Order(
        id: 'V-x',
        productName: 'AI 點數 ×10',
        spec: '10 點',
        qty: 1,
        placedAt: s.now,
        coinPaid: 1500,
        cashPaid: 0,
        state: OrderState.pendingPayment,
      );
      s.orders.insert(0, o);
      s.payOrder(o);
      expect(o.state, OrderState.delivered);
    });
  });
}
