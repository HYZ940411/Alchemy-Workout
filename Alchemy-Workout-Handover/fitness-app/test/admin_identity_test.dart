// 管理員身分改由 Firebase Auth 的 custom claim 決定（2026-09-24）。
//
// 使用者問「我有一個 XXX 的帳號可以成為管理員嗎」。查下去發現整個後台
// 是斷的：
//
//   · `AppState.admin` 是**寫死的假管理員**（`kCurrentAdmin`，三種權限全開）
//   · `adminMode` 這個欄位**全 App 沒有任何地方切換它**
//   · 後台唯一的入口掛在「流程示範」區底下，而那一區的條件是
//     **開發者模式** —— 也就是任何人長按「我的」頁首三秒都進得去。
//     它之所以看起來沒問題，只是因為裡面全是假資料。
//   · 後台那七份佇列（檢舉、申訴、教官審核、公開計畫、商品、訂單、
//     管理員名冊）**全都沒有 `demo` 開關** —— 真管理員會看到一批編出來
//     的案件並對它們做裁決。
//
// ## 為什麼判準必須與 `firestore.rules` 同源
//
// 規則的 `isAdmin()` 看的是 `request.auth.token.admin`。畫面上若各自
// 判斷，會做出「後台進得去、每一個寫入都被規則擋下」的狀態 ——
// 那是最難查的一種，因為兩邊都覺得自己是對的，而失敗是靜默的。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/screens/me/more_screen.dart';
import 'package:fitness_app/state/app_state.dart';

AppState real() => AppState(demo: false)
  ..myUid = 'u-me'
  ..displayName = '阿健';

void main() {
  group('管理員身分來自 custom claim', () {
    test('沒有 claim 就不是管理員', () {
      expect(real().isPlatformAdmin, isFalse);
    });

    test('claim 為真就是管理員', () {
      final s = real()..applyAdminClaim(true);
      expect(s.isPlatformAdmin, isTrue);
    });

    test('沒給權限組＝三種全開', () {
      final s = real()..applyAdminClaim(true);
      expect(s.admin.scopes, AdminScope.values.toSet());
      expect(s.canReview, isTrue);
      expect(s.canManageProducts, isTrue);
      expect(s.canConfigure, isTrue);
    });

    test('給了權限組就只有那幾組', () {
      final s = real()..applyAdminClaim(true, scopes: ['contentReview']);
      expect(s.admin.scopes, {AdminScope.contentReview});
      expect(s.canReview, isTrue);
      expect(s.canManageProducts, isFalse,
          reason: '畫面上比規則嚴格可以，比規則寬鬆才是問題');
    });

    test('不認得的權限組名稱略過，不會整組變成全開', () {
      final s = real()
        ..applyAdminClaim(true, scopes: ['contentReview', '打錯的名字']);
      expect(s.admin.scopes, {AdminScope.contentReview});
    });

    test('權限組全部都認不得時退回全開 —— 但他確實是管理員', () {
      // claim 說了 admin: true，那一點沒有疑義；認不得的是細分權限。
      final s = real()..applyAdminClaim(true, scopes: ['全都打錯']);
      expect(s.isPlatformAdmin, isTrue);
      expect(s.admin.scopes, AdminScope.values.toSet());
    });

    test('身分帶著我的 uid 與暱稱，不是寫死的 A-001', () {
      final s = real()..applyAdminClaim(true);
      expect(s.admin.id, 'u-me');
      expect(s.admin.name, '阿健');
    });

    test('撤銷後不再是管理員，而且後台模式跟著關掉', () {
      final s = real()
        ..applyAdminClaim(true)
        ..adminMode = true;

      s.applyAdminClaim(false);

      expect(s.isPlatformAdmin, isFalse);
      expect(s.adminMode, isFalse, reason: '留著的話下一個登入的人會停在後台');
    });
  });

  group('後台的佇列不給真帳號看假案件', () {
    test('非示範帳號的七份佇列都是空的', () {
      final s = real();
      expect(s.reports, isEmpty);
      expect(s.appeals, isEmpty);
      expect(s.instructorCases, isEmpty);
      expect(s.publicPlanCases, isEmpty);
      // 商品是平台目錄（內建一份預設，雲端覆蓋），不是假案件，真帳號也有。
      expect(s.adminProducts, isNotEmpty);
      expect(s.admins, isEmpty);
    });

    test('示範身分維持原樣 —— 那些假案件還撐著「這幾頁長什麼樣」', () {
      final s = AppState();
      expect(s.reports, isNotEmpty);
      expect(s.appeals, isNotEmpty);
      expect(s.instructorCases, isNotEmpty);
    });
  });

  group('入口', () {
    Future<void> pump(WidgetTester t, AppState s) async {
      t.view.physicalSize = const Size(393 * 3, 852 * 6);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(AppScope(
          state: s, child: const MaterialApp(home: Scaffold(body: MoreScreen()))));
      await t.pumpAndSettle();
    }

    /// 「我的」是一長串清單，後台那一項在下面 —— 捲到看得到為止。
    /// 捲不到就是真的沒有。
    Future<bool> scrollTo(WidgetTester t, String label) async {
      try {
        await t.scrollUntilVisible(find.text(label), 200,
            scrollable: find.byType(Scrollable).first);
        await t.pumpAndSettle();
        return true;
      } catch (_) {
        return false;
      }
    }

    testWidgets('一般使用者看不到後台', (t) async {
      await pump(t, real());
      expect(await scrollTo(t, '管理員後台'), isFalse,
          reason: '整份清單捲完都不該有');
    });

    testWidgets('管理員看得到，而且不必開發者模式', (t) async {
      final s = real()..applyAdminClaim(true);
      expect(s.developerMode, isFalse, reason: '前提：沒開開發者模式');

      await pump(t, s);

      // 在此之前後台只掛在開發者模式底下 —— 真管理員沒有入口，
      // 而任何人長按頁首三秒都進得去。
      expect(await scrollTo(t, '管理員後台'), isTrue);
      expect(find.text('管理員'), findsOneWidget, reason: '自成一個區塊');
    });

    testWidgets('開發者模式那個示範入口還留著', (t) async {
      final s = real()..toggleDeveloperMode();
      await pump(t, s);
      expect(await scrollTo(t, '管理員後台'), isTrue);
      expect(find.text('流程示範'), findsOneWidget);
    });
  });
}
