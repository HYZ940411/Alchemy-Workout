import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/main.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/common.dart';

const kBase = Size(393 * 3, 852 * 3);
const kNarrow = Size(375 * 3, 667 * 3);

Future<void> _openShop(
  WidgetTester t, {
  Size size = kBase,
  double textScale = 1.0,
  int? productCount,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: const FitnessApp(),
    ),
  );
  await t.pumpAndSettle();
  // 想測奇數張時，把商品削到指定數量（商城打開之前改，打開時就是這個數量）。
  if (productCount != null) {
    final s = AppScope.of(t.element(find.byType(Scaffold).first));
    s.products.removeRange(productCount, s.products.length);
  }
  await t.tap(find.text('商店').last);
  await t.pumpAndSettle();
  // 商店分頁是入口頁，商城在它底下一層。
  await t.tap(find.text('商城'));
  await t.pumpAndSettle();
}

/// 同一列的兩張卡。
List<Rect> _cardRects(WidgetTester t) => t
    .widgetList<AppCard>(find.byType(AppCard))
    .map((w) => t.getRect(find.byWidget(w)))
    .toList();

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  testWidgets('商品是兩欄，不是一欄', (t) async {
    await _openShop(t);
    final rects = _cardRects(t);
    expect(rects.length, greaterThanOrEqualTo(2));

    // 前兩張在同一列：頂緣相同、左右並排。
    expect(rects[0].top, closeTo(rects[1].top, 0.5));
    expect(rects[0].right, lessThan(rects[1].left));
  });

  testWidgets('兩欄等寬，間距 12px', (t) async {
    await _openShop(t);
    final r = _cardRects(t);
    expect(r[0].width, closeTo(r[1].width, 0.5));
    expect(r[1].left - r[0].right, closeTo(12, 0.5));
  });

  testWidgets('同一列等高 —— 品名一行與兩行的卡底緣要對齊', (t) async {
    // 必須挑一列「兩張卡的自然高度本來就不一樣」的來驗，否則等高與否
    // 看不出差別。虛擬商品第一列的兩個品名長度差很多（375 寬時一個換行、
    // 一個不換行），自然高度差 20px。
    await _openShop(t, size: kNarrow);

    final r = _cardRects(t);
    final firstRow = r.where((x) => (x.top - r.first.top).abs() < 0.5).toList();
    expect(firstRow.length, 2);
    expect(firstRow[0].height, closeTo(firstRow[1].height, 0.5));
    expect(firstRow[0].bottom, closeTo(firstRow[1].bottom, 0.5));
  });

  testWidgets('奇數張時最後一張不撐成滿版', (t) async {
    await _openShop(t, productCount: 3);
    final s = AppScope.of(t.element(find.byType(AppCard).first));
    final r = _cardRects(t);
    expect(r.length.isOdd, isTrue, reason: '本測試要的是奇數張');
    expect(r.last.width, closeTo(r.first.width, 0.5),
        reason: '最後一張的寬度要跟其他張一樣');
    expect(s.products, isNotEmpty);
  });

  testWidgets('375 最窄不爆版', (t) async {
    await _openShop(t, size: kNarrow);
    expect(t.takeException(), isNull);
  });

  testWidgets('字級放大 1.3 倍仍不爆版 —— 兩欄最容易在這裡出事', (t) async {
    await _openShop(t, size: kNarrow, textScale: 1.3);
    expect(t.takeException(), isNull);
    // 捲到最後一列，確認整片格狀都畫得完。
    await t.drag(find.byType(AppCard).first, const Offset(0, -400));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('商城沒有實體／虛擬分頁，商品全部在同一片格狀裡', (t) async {
    await _openShop(t);
    expect(find.text('實體商品'), findsNothing);
    expect(find.text('虛擬商品'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    final r = _cardRects(t);
    expect(r.length, 4);
    expect(t.takeException(), isNull);
  });

  testWidgets('點卡片進得了商品詳情', (t) async {
    await _openShop(t);
    await t.tap(find.byType(AppCard).first);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('商城'), findsNothing);
  });
}
