// 帳號管理頁：真實帳號看到說明，示範身分才有那份假名單（使用者 2026-10-15 裁決 A）。
//
// ## 為什麼
//
// 管理員身分來自 Firebase 帳號上的 `admin` 宣告，設定宣告只有伺服器端做得到。
// 原本這一頁讓真實帳號也能「新增管理員」「停用」「調整權限組」，改的卻只是記憶體裡
// 的一份名單：畫面看起來管得到，實際沒有任何人因此變成或不再是管理員。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/screens/admin/admin_accounts_screen.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  Future<void> open(WidgetTester t, AppState s) async {
    await t.pumpWidget(AppScope(
      state: s,
      child: const MaterialApp(home: AdminAccountsScreen()),
    ));
    await t.pumpAndSettle();
  }

  group('畫面', () {
    testWidgets('真實帳號：看得到說明與自己的權限組，沒有新增／停用按鈕', (t) async {
      final s = AppState(demo: false)
        ..applyAdminClaim(true, scopes: ['contentReview']);
      await open(t, s);
      expect(find.text('管理員身分由 Firebase 帳號宣告決定'), findsOneWidget);
      expect(find.textContaining('內容審核'), findsOneWidget);
      expect(find.textContaining('商品管理'), findsNothing,
          reason: '只列宣告裡真的有的權限組');
      expect(find.text('新增管理員', skipOffstage: false), findsNothing);
      expect(find.text('停用', skipOffstage: false), findsNothing);
    });

    testWidgets('真實帳號沒有管理員宣告：照實說沒有', (t) async {
      final s = AppState(demo: false)..applyAdminClaim(false);
      await open(t, s);
      expect(find.text('這個帳號沒有管理員宣告。'), findsOneWidget);
    });

    testWidgets('示範身分：仍是原本的名單，有新增管理員', (t) async {
      // 清單是惰性建構，視窗要夠高才建得到底部的按鈕。
      t.view.physicalSize = const Size(800, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = AppState();
      await open(t, s);
      expect(find.text('管理員身分由 Firebase 帳號宣告決定'), findsNothing);
      expect(find.text('新增管理員', skipOffstage: false), findsWidgets);
    });
  });

  group('狀態層：真實帳號改名單一律被擋，且名單不動', () {
    AppState real() => AppState(demo: false)
      ..applyAdminClaim(true)
      ..admin = const Admin(
        id: 'A-1',
        name: '我',
        scopes: {
          AdminScope.platformConfig,
          AdminScope.contentReview,
        },
      );

    test('新增', () {
      final s = real();
      final before = s.admins.length;
      expect(s.addAdmin('某人', {AdminScope.contentReview}), contains('Firebase'));
      expect(s.admins.length, before);
    });

    test('停用、啟用、調整權限組', () {
      final s = real();
      final a = const Admin(
        id: 'A-2',
        name: '某人',
        scopes: {AdminScope.contentReview},
      );
      expect(s.disableAdmin(a), contains('Firebase'));
      expect(s.enableAdmin(a), contains('Firebase'));
      expect(s.setAdminScopesOf(a, {AdminScope.productManage}),
          contains('Firebase'));
    });

    test('示範身分照舊能新增', () {
      final s = AppState()
        ..admin = const Admin(
            id: 'A-1', name: '我', scopes: {AdminScope.platformConfig});
      expect(s.addAdmin('某人', {AdminScope.contentReview}), isNull);
    });
  });
}
