// 商品上雲（2026-10-15，使用者要求補的缺功能；庫存取裁決 A）。
//
// 在此之前後台有一整頁商品管理，但 `adminProducts` 只存在記憶體，
// 與使用者看到的 `products` 是兩份不相干的清單 —— 管理員改了商品，使用者的商城
// 一個字都不會變，而且後台自己重新整理也會打回原形。
//
// 現在：後台改的商品寫進 `products/{id}`，商城看到的是「已上架的後台商品」。
// 庫存只是上架條件與顯示用，購買不會扣它。

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/data/platform_data_firestore.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/mock/mock_admin.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  late FakeFirebaseFirestore db;
  late AppState admin;

  setUp(() {
    db = FakeFirebaseFirestore();
    admin = AppState()
      ..applyAdminClaim(true)
      ..platformSource = FirestorePlatformData(firestore: db);
  });

  /// 模擬另一位使用者登入：整份從雲端載入。
  Future<AppState> userLoads() async => AppState(demo: false)
    ..applyPlatformData(await FirestorePlatformData(firestore: db).load());

  group('文件形狀來回', () {
    test('消耗品：名稱、圖片、點數、說明、規格、上架狀態都在', () {
      final p = AdminProduct(
        id: 'x1',
        name: '點數包',
        emoji: '✨',
        subtype: VirtualSubtype.consumable,
        listing: ListingState.listed,
        images: ['im_badge', 'im_chart'],
        aiCredits: 25,
        note: '限時加碼',
        specs: [AdminProductSpec('25 點', 3500, 40)],
      );
      final back = productFromDoc('x1', productToMap(p));
      expect(back.name, '點數包');
      expect(back.images, ['im_badge', 'im_chart']);
      expect(back.aiCredits, 25);
      expect(back.note, '限時加碼');
      expect(back.listing, ListingState.listed);
      expect(back.subtype, VirtualSubtype.consumable);
      expect(back.specs.single.price, 3500);
      expect(back.specs.single.stock, 40);
    });

    test('權限解鎖類：解鎖標的也在', () {
      final p = buildAdminProducts().firstWhere((x) => x.id == 'v4');
      final back = productFromDoc('v4', productToMap(p));
      expect(back.subtype, VirtualSubtype.unlock);
      expect(back.unlockTarget, p.unlockTarget);
    });
  });

  group('載入：內建當底，雲端按 id 蓋上去', () {
    test('雲端沒有商品 → 就是內建那一份', () async {
      final loaded = await FirestorePlatformData(firestore: db).load();
      expect(loaded.products.map((p) => p.id),
          buildAdminProducts().map((p) => p.id));
    });

    test('管理員只改了一件 → 其他內建商品還在（不會整份被取代）', () async {
      final p = admin.adminProducts.firstWhere((x) => x.id == 'v3');
      admin.setProductInfo(p,
          name: '補簽券 ×3（新）', images: p.images, specs: [
        AdminProductSpec('3 張', 450, 999),
      ]);
      expect(await admin.pushProduct(p), isNull);

      final user = await userLoads();
      final names = user.products.map((x) => x.name).toList();
      expect(names, contains('補簽券 ×3（新）'));
      expect(names, contains('AI 點數 ×10'), reason: '沒動過的內建商品照舊');
      expect(user.products.firstWhere((x) => x.id == 'v3').specs.single.coinPrice,
          450);
    });

    test('雲端獨有的新商品接在後面', () async {
      admin.addProduct(name: '新點數包', subtype: VirtualSubtype.consumable);
      final p = admin.adminProducts.last;
      admin.setProductInfo(p,
          name: '新點數包',
          images: ['im_badge'],
          aiCredits: 5,
          specs: [AdminProductSpec('5 點', 800, 20)]);
      expect(admin.listProduct(p), isNull);
      expect(await admin.pushProduct(p), isNull);

      final user = await userLoads();
      final shop = user.products.firstWhere((x) => x.name == '新點數包');
      expect(shop.aiCredits, 5);
      expect(shop.specs.single.coinPrice, 800);
    });

    test('壞掉的一筆文件略過，不拖垮整份', () async {
      await db.collection('products').doc('bad').set({'listing': 'listed'});
      final loaded = await FirestorePlatformData(firestore: db).load();
      expect(loaded.products.any((p) => p.id == 'bad'), isFalse);
      expect(loaded.products, isNotEmpty);
    });
  });

  group('後台動作 → 使用者的商城', () {
    test('下架：寫上雲之後，使用者的商城看不到', () async {
      final p = admin.adminProducts.firstWhere((x) => x.id == 'v1');
      admin.delistProduct(p);
      expect(await admin.pushProduct(p), isNull);

      final user = await userLoads();
      expect(user.products.any((x) => x.id == 'v1'), isFalse);
      expect(user.adminProducts.firstWhere((x) => x.id == 'v1').listing,
          ListingState.delisted);
    });

    test('重新上架：回得來', () async {
      final p = admin.adminProducts.firstWhere((x) => x.id == 'v5');
      admin.setProductInfo(p,
          name: p.name,
          images: p.images,
          specs: [AdminProductSpec('5 點', 300, 10)],
          aiCredits: 5);
      expect(admin.listProduct(p), isNull);
      await admin.pushProduct(p);

      final user = await userLoads();
      expect(user.products.any((x) => x.id == 'v5'), isTrue);
    });

    test('後台本機改了之後，同一次連線商城就跟著變', () {
      final p = admin.adminProducts.firstWhere((x) => x.id == 'v2');
      admin.setProductInfo(p, name: '改名了', images: p.images, specs: [
        AdminProductSpec('1 次', 170, 999),
      ]);
      expect(admin.products.firstWhere((x) => x.id == 'v2').name, '改名了');
      expect(admin.products.firstWhere((x) => x.id == 'v2').specs.single.coinPrice,
          170);
    });

    test('發放的 AI 點數是後台設的數額，買了就真的加', () async {
      final p = admin.adminProducts.firstWhere((x) => x.id == 'v3');
      admin.setProductInfo(p,
          name: p.name,
          images: p.images,
          specs: p.specs, // 傳進來的就是它自己 —— 不能因此把規格清空
          aiCredits: 7);
      expect(p.specs, isNotEmpty);
      await admin.pushProduct(p);

      final user = await userLoads()..coins = 99999;
      final before = user.aiPermanent;
      final shop = user.products.firstWhere((x) => x.id == 'v3');
      expect(user.confirmPurchase(shop, shop.specs.first, 1), isNull);
      user.payOrder(user.orders.first);
      expect(user.aiPermanent, before + 7);
    });
  });

  group('庫存只當條件與顯示（裁決 A）', () {
    test('庫存 0 → 買不了；庫存夠 → 買了也不會減少', () async {
      final p = admin.adminProducts.firstWhere((x) => x.id == 'v3');
      admin.setProductInfo(p,
          name: p.name, images: p.images, specs: [AdminProductSpec('3 張', 400, 0)]);
      final soldOut = admin.products.firstWhere((x) => x.id == 'v3');
      admin.coins = 99999;
      expect(admin.confirmPurchase(soldOut, soldOut.specs.first, 1),
          FailReason.soldOut);

      admin.setProductInfo(p,
          name: p.name, images: p.images, specs: [AdminProductSpec('3 張', 400, 3)]);
      final ok = admin.products.firstWhere((x) => x.id == 'v3');
      expect(admin.confirmPurchase(ok, ok.specs.first, 2), isNull);
      expect(ok.specs.first.stock, 3, reason: '賣出去不會自動減少');
      expect(p.specs.single.stock, 3);
    });

    test('權限解鎖類：價格一律是全站統一定價，文件上寫的價格不算', () async {
      final p = admin.adminProducts.firstWhere((x) => x.id == 'v4');
      admin.setProductInfo(p,
          name: p.name,
          images: p.images,
          specs: [AdminProductSpec('單一計畫', 123, 0)],
          subtype: VirtualSubtype.unlock,
          unlockTarget: p.unlockTarget);
      await admin.pushProduct(p);

      final user = await userLoads();
      final shop = user.products.firstWhere((x) => x.id == 'v4');
      expect(shop.specs.single.coinPrice, kPlanUnlockCoins);
      expect(shop.specs.single.inStock, isTrue, reason: '解鎖類不適用庫存');
    });
  });

  group('寫不上去要講出來', () {
    test('沒有管理員標記 → 說寫不上雲，不假裝成功', () async {
      final nobody = AppState()
        ..platformSource = FirestorePlatformData(firestore: db);
      final msg = await nobody.pushProduct(nobody.adminProducts.first);
      expect(msg, isNotNull);
      expect((await db.collection('products').get()).docs, isEmpty);
    });
  });

  test('安全規則：products 唯讀給登入者、只有管理員可寫', () {
    final rules = File('firestore.rules').readAsStringSync();
    final i = rules.indexOf('match /products/{document=**}');
    expect(i, isNot(-1), reason: '規則裡沒有 products');
    final block = rules.substring(i, rules.indexOf('\n    }\n', i));
    expect(block, contains('allow read: if request.auth != null'));
    expect(block, contains('allow write: if isAdmin()'));
  });
}
