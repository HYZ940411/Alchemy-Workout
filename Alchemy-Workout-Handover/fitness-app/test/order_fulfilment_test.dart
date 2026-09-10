// 我買的東西要真的進出貨佇列。
//
// 先前後台的訂單佇列與我的訂單是兩份不相干的清單：後台那份全是假資料，
// 我買的東西永遠不會出現在裡面。[AppState.shipOrder] 裡那段
// 「同一筆訂單在使用者端亦轉為已出貨」以 id 比對，而兩邊的 id
// 從來不可能相同 —— 那段程式碼一次都沒被執行過。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/state/app_state.dart';

const shipping = ShippingInfo(
  name: '王小明',
  phone: '0912-345-678',
  zip: '110',
  address: '台北市信義區松高路 1 號',
);

/// 買一件實體商品，回傳那筆訂單。
Order buyPhysical(AppState s) {
  final p = s.products.firstWhere((x) => x.kind == ProductKind.physical);
  final spec = p.specs.firstWhere((x) => x.stock > 0);
  s.coins = 999999;
  expect(s.confirmPurchase(p, spec, 1, shipping: shipping), isNull);
  return s.orders.first;
}

void main() {
  test('付款後進出貨佇列，而且是同一個訂單編號', () {
    final s = AppState();
    final o = buyPhysical(s);
    expect(s.adminOrders.any((a) => a.id == o.id), isFalse,
        reason: '還沒付款，不該進佇列');

    s.payOrder(o);
    final a = s.adminOrders.firstWhere((x) => x.id == o.id);
    expect(a.state, '已付款');
    expect(a.product, o.productName);
    expect(a.qty, o.qty);
    expect(a.coinAmount, o.coinPaid, reason: '單位是金幣，兩邊要對得起來');
    expect(a.address, contains('王小明'),
        reason: '出貨要有收件資訊，空白地址等於出不了貨');
  });

  test('後台出貨，我的訂單頁跟著變 —— 這段先前執行不到', () {
    final s = AppState();
    final o = buyPhysical(s);
    s.payOrder(o);
    final a = s.adminOrders.firstWhere((x) => x.id == o.id);

    final shipper = s.admins.firstWhere((x) => x.can(AdminScope.productManage));
    s.runAsAdmin(shipper, () => s.shipOrder(a));

    expect(a.state, '已出貨');
    expect(o.state, OrderState.shipped,
        reason: '後台說已出貨、我的訂單頁還停在已付款，是兩份互相矛盾的紀錄');
    expect(o.trackingNo, a.trackingNo);
    expect(o.trackingNo, isNotNull);
    expect(s.unreadShipped, contains(o.id), reason: '我的訂單頁要標紅點');
  });

  test('虛擬訂單不進出貨佇列 —— 沒有東西要寄', () {
    final s = AppState();
    final p = s.products.firstWhere((x) => x.kind == ProductKind.virtual);
    final spec = p.specs.first;
    s.coins = 999999;
    final n = s.adminOrders.length;
    expect(s.confirmPurchase(p, spec, 1), isNull);
    s.payOrder(s.orders.first);
    expect(s.adminOrders.length, n);
  });

  test('同一筆不會重複進佇列', () {
    final s = AppState();
    final o = buyPhysical(s);
    s.payOrder(o);
    final n = s.adminOrders.where((x) => x.id == o.id).length;
    s.payOrder(o); // 已付款，第二次應該什麼都不做
    expect(s.adminOrders.where((x) => x.id == o.id).length, n);
    expect(n, 1);
  });

  group('虛擬商品的發放失敗', () {
    Order buyVirtual(AppState s) {
      final p = s.products.firstWhere((x) =>
          x.kind == ProductKind.virtual &&
          x.specs.any((sp) => sp.stock > 0));
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
