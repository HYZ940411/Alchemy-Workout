import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/design/image_library.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/mock/mock_admin.dart';
import 'package:fitness_app/screens/admin/product_edit_screen.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/state/app_state.dart';

import 'developer_mode.dart';

/// 〈管理員商品上架流程〉：新增商品、設定商品資訊、上架、下架
void main() {
  group('新增商品', () {
    test('新商品一律自已下架起算 —— 上架另有 Precondition，不能靠新增繞過', () {
      final s = AppState();
      expect(s.addProduct(name: '護腕', subtype: VirtualSubtype.consumable),
          isNull);
      final p = s.adminProducts.last;
      expect(p.name, '護腕');
      expect(p.listing, ListingState.delisted);
      expect(p.canList, isFalse, reason: '沒有圖片也沒有庫存');
    });

    test('虛擬商品須指定子類型', () {
      final s = AppState();
      expect(s.addProduct(name: '點數包', subtype: null), contains('子類型'));
    });

    test('權限組不含商品管理者不得執行', () {
      final s = AppState();
      s.setAdminScopes({AdminScope.contentReview});
      expect(s.addProduct(name: '護腕', subtype: VirtualSubtype.consumable),
          contains('權限不足'));
    });
  });

  group('設定商品資訊', () {
    test('寫入名稱與圖片，價格與庫存逐規格設定', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v1');
      final failure = s.setProductInfo(
        p,
        name: 'AI 點數 ×10（新款）',
        images: const ['im_ticket', 'im_dumbbell'],
        specs: [AdminProductSpec('10 點', 1650, 30)],
      );
      expect(failure, isNull);
      expect(p.name, 'AI 點數 ×10（新款）');
      expect(p.images, ['im_ticket', 'im_dumbbell']);
      expect(p.specs.single.price, 1650);
      expect(p.specs.single.stock, 30);
    });

    test('庫存不得為負值', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v1');
      expect(
        s.setProductInfo(p, name: 'AI 點數', images: const ['im_ticket'], specs: [
          AdminProductSpec('10 點', 1500, -1),
        ]),
        contains('庫存'),
      );
      expect(p.specs.single.stock, 999, reason: '被擋下者不得留下半套變更');
    });

    test('虛擬商品僅有一個預設規格', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v1');
      expect(
        s.setProductInfo(p, name: 'AI 點數', images: const ['im_ticket'], specs: [
          AdminProductSpec('10 點', 1500, 999),
          AdminProductSpec('20 點', 2800, 999),
        ]),
        contains('一個預設規格'),
      );
    });

    test('解鎖標的僅權限解鎖類有值，改成消耗品時清空', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v4');
      expect(p.unlockTarget, isNotNull);
      s.setProductInfo(
        p,
        name: '進階計畫解鎖',
        images: const ['im_plan'],
        specs: [AdminProductSpec('預設規格', 800, 0)],
        subtype: VirtualSubtype.consumable,
      );
      expect(p.unlockTarget, isNull);
    });

    test('已上架商品被改成不符合上架條件時，當場退回已下架', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v1');
      expect(p.listing, ListingState.listed);
      // 圖片清空 → 商品資訊不完整
      s.setProductInfo(p, name: 'AI 點數', images: const [], specs: [
        AdminProductSpec('10 點', 1500, 25),
      ]);
      expect(p.listing, ListingState.delisted);
    });
  });

  group('上架 Precondition', () {
    test('須已設定完商品資訊，且至少一個規格庫存 > 0', () {
      final s = AppState();
      s.addProduct(name: '點數包', subtype: VirtualSubtype.consumable);
      final p = s.adminProducts.last;

      expect(s.listProduct(p), contains('商品資訊'));

      s.setProductInfo(p, name: '點數包', images: const ['im_ticket'], specs: [
        AdminProductSpec('預設規格', 400, 0),
      ]);
      expect(s.listProduct(p), contains('庫存'));

      s.setProductInfo(p, name: '點數包', images: const ['im_ticket'], specs: [
        AdminProductSpec('預設規格', 400, 5),
      ]);
      expect(s.listProduct(p), isNull);
      expect(p.listing, ListingState.listed);
    });

    test('權限解鎖類不適用庫存，庫存為 0 仍可上架', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v4');
      s.delistProduct(p);
      s.setProductInfo(
        p,
        name: '進階計畫解鎖',
        images: const ['im_plan'],
        specs: [AdminProductSpec('單一計畫', 800, 0)],
        subtype: VirtualSubtype.unlock,
        unlockTarget: '推日：胸肩三頭',
      );
      expect(p.stockApplies, isFalse);
      expect(s.listProduct(p), isNull);
      expect(p.listing, ListingState.listed);
    });

    test('權限解鎖類未指定解鎖標的者不得上架', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v4');
      s.delistProduct(p);
      s.setProductInfo(
        p,
        name: '進階計畫解鎖',
        images: const ['im_plan'],
        specs: [AdminProductSpec('單一計畫', 800, 0)],
        subtype: VirtualSubtype.unlock,
        unlockTarget: '',
      );
      expect(s.listProduct(p), contains('商品資訊'));
    });

    test('售完不自動下架', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v1');
      s.setProductInfo(p, name: p.name, images: const ['im_ticket'], specs: [
        AdminProductSpec('10 點', 1500, 0),
      ]);
      // 上一條規則會讓它退回已下架嗎？不會 —— 資訊仍完整，只是沒庫存。
      expect(p.soldOut, isTrue);
      expect(p.listing, ListingState.listed,
          reason: '售完維持已上架，只是買不到');
    });
  });

  group('下架', () {
    test('待付款訂單自動取消，庫存與金幣回補', () {
      final s = AppState();
      final p = s.adminProducts.firstWhere((x) => x.id == 'v1');
      final order = s.orders.firstWhere((o) => o.id == 'O-20260826-004');
      expect(order.state, OrderState.pendingPayment, reason: '前提：示範訂單待付款');
      final spec = s.products.firstWhere((x) => x.id == 'v1').specs.first;
      final stockBefore = spec.stock;
      final coinsBefore = s.coins;

      final cancelled = s.delistProduct(p);

      expect(cancelled, ['O-20260826-004']);
      expect(order.state, OrderState.cancelled);
      expect(order.cancelledBySystem, isTrue, reason: '由系統取消，非使用者自行取消');
      expect(spec.stock, stockBefore + 1, reason: '回補待付款訂單佔用的 1 件');
      expect(s.coins, coinsBefore + order.coinPaid, reason: '已扣的金幣退回');
      expect(p.listing, ListingState.delisted);
    });

    test('別的商品的待付款訂單不受牽連', () {
      final s = AppState()..coins = 99999;
      final other = s.products.firstWhere((x) => x.id == 'v2');
      expect(s.confirmPurchase(other, other.specs.first, 1), isNull);
      final mine = s.orders.first;

      s.delistProduct(s.adminProducts.firstWhere((x) => x.id == 'v1'));

      expect(mine.state, OrderState.pendingPayment);
    });

    test('已付款、已發放的訂單不受下架影響', () {
      final s = AppState();
      final delivered = s.orders.firstWhere((o) => o.state == OrderState.delivered);
      final p = s.adminProducts.firstWhere((x) => x.name == delivered.productName);

      s.delistProduct(p);

      expect(delivered.state, OrderState.delivered);
    });
  });

  group('圖庫', () {
    test('每張圖的 ID 唯一，且查得到', () {
      final ids = kImageLibrary.map((i) => i.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(imageOf(id), isNotNull);
      }
    });

    test('查不到的 ID 回傳空值，讓畫面畫成破圖而非留白', () {
      expect(imageOf('im_not_there'), isNull);
    });

    test('商品的預設圖片都指得到圖庫裡的圖', () {
      for (final p in buildAdminProducts()) {
        for (final id in p.images) {
          expect(imageOf(id), isNotNull, reason: '${p.name} 的圖片 $id 不存在');
        }
      }
    });
  });

  group('貼文圖片', () {
    test('發布時帶著圖片集合', () {
      final s = AppState();
      s.publishPost('今天練胸', PostVisibility.public,
          images: const ['im_barbell', 'im_fire']);
      expect(s.posts.first.images, ['im_barbell', 'im_fire']);
    });

    test('沒選圖時為空集合，不是空值', () {
      final s = AppState();
      s.publishPost('隨手記一下', PostVisibility.public);
      expect(s.posts.first.images, isEmpty);
    });
  });

  group('後台走一遍', () {
    testWidgets('新增商品 → 補圖片與庫存 → 上架', (t) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const FitnessApp());
      await t.pumpAndSettle();

      await t.tap(find.text('我的').last);
      await t.pumpAndSettle();
      // 「流程示範」那一區收進了開發者模式，一般使用者看不到。
      await enableDeveloperMode(t);
      final more = find
          .descendant(
              of: find.byType(MoreScreen), matching: find.byType(Scrollable))
          .first;
      final entry = find.descendant(
          of: find.byType(MoreScreen), matching: find.text('管理員後台'));
      await t.scrollUntilVisible(entry, 120, scrollable: more);
      await t.pumpAndSettle();
      await t.tap(entry);
      await t.pumpAndSettle();

      await t.tap(find.text('商品清單'));
      await t.pumpAndSettle();

      // 新增商品
      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '測試護腕');
      await t.pumpAndSettle();
      await t.tap(find.text('新增'));
      await t.pumpAndSettle();

      // 自動進入編輯器
      expect(find.byType(ProductEditScreen), findsOneWidget);

      // 選圖。抽屜底下的商品清單也有「助力帶」，故把 finder 限縮在抽屜內。
      await t.tap(find.text('加入圖片'));
      await t.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final tile =
          find.descendant(of: sheet, matching: find.text('訓練上衣'));
      await t.ensureVisible(tile);
      await t.pumpAndSettle();
      await t.tap(tile);
      await t.pumpAndSettle();
      expect(find.descendant(of: sheet, matching: find.text('已選 1 張')),
          findsOneWidget);
      final confirm = find.descendant(of: sheet, matching: find.text('確定'));
      await t.ensureVisible(confirm);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(sheet, findsNothing, reason: '確定後抽屜應關閉');
      expect(find.text('尚未加入圖片'), findsNothing);

      // 補價格與庫存
      // 虛擬商品的編輯頁多了子類型那一段，規格在下面 —— 先捲到看得見再輸入。
      final priceField = find.widgetWithText(TextField, '價格');
      await t.scrollUntilVisible(priceField, 200,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.enterText(priceField, '400');
      await t.enterText(find.widgetWithText(TextField, '庫存'), '5');
      await t.pumpAndSettle();
      await t.tap(find.text('儲存'));
      await t.pumpAndSettle();

      // 回到清單，上架鈕此時可點
      final listBtn = find.text('上架').last;
      await t.scrollUntilVisible(listBtn, 200);
      await t.pumpAndSettle();
      await t.tap(listBtn);
      await t.pumpAndSettle();

      // 上架成功的證據看畫面即可：該商品的狀態徽章變成已上架。
      expect(find.text('已上架'), findsWidgets);
      expect(find.text('測試護腕'), findsOneWidget);
    });
  });
}
