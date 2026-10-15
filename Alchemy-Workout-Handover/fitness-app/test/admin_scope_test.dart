import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/domain/custom_plan.dart';
import 'package:fitness_app/state/app_state.dart';

/// 換一位管理員。空的權限組即「什麼都不能做」。
AppState asAdmin({Set<AdminScope> scopes = const {}, bool active = true}) {
  final s = AppState();
  s.admin = Admin(
    id: 'A-999',
    name: '測試管理員',
    scopes: scopes,
    status: active ? AdminStatus.active : AdminStatus.disabled,
  );
  return s;
}

ReportCase pendingReport(AppState s) =>
    s.reports.firstWhere((r) => r.state == CaseState.pending);

AppealCase pendingAppeal(AppState s) =>
    s.appeals.firstWhere((a) => a.state == CaseState.pending);

void main() {
  group('內容審核：無權限者在狀態層就被擋下', () {
    test('審視檢舉', () {
      final s = asAdmin();
      final c = pendingReport(s);
      s.reviewReport(c);
      expect(c.state, CaseState.pending, reason: '畫面擋不算，後端須擋');
    });

    test('成立並處罰 / 駁回檢舉', () {
      final s = asAdmin(scopes: {AdminScope.contentReview});
      final c = pendingReport(s);
      s.reviewReport(c);
      expect(c.state, CaseState.reviewing);

      // 中途被拔掉權限。
      s.admin = Admin(id: 'A-999', name: 'x', scopes: const {});
      final violations = s.violationsOf(c.accused);
      s.upholdReport(c);
      expect(c.state, CaseState.reviewing, reason: '沒有權限就不該改變案件狀態');
      expect(s.violationsOf(c.accused), violations, reason: '更不該記次');
      s.dismissReport(c);
      expect(c.state, CaseState.reviewing);
    });

    test('審視申訴 / 撤銷處罰 / 駁回申訴', () {
      final s = asAdmin();
      final a = pendingAppeal(s);
      s.reviewAppeal(a);
      expect(a.state, CaseState.pending);
      s.upholdAppeal(a);
      expect(a.state, CaseState.pending);
      s.dismissAppeal(a);
      expect(a.state, CaseState.pending);
    });

    test('接手審核案件', () {
      final s = asAdmin();
      final c = s.reports.firstWhere((r) => r.state == CaseState.reviewing);
      final handler = c.handlerName;
      s.takeOverReport(c);
      expect(c.handlerName, handler);
    });

    test('審核公開訓練', () {
      final s = asAdmin();
      final p = s.customPlans
          .firstWhere((p) => p.state == CustomPlanState.pendingPublic);
      s.approvePublicPlan(p);
      expect(p.state, CustomPlanState.pendingPublic);
      s.rejectPublicPlan(p, '理由');
      expect(p.state, CustomPlanState.pendingPublic);
    });

    test('審核教官測驗', () {
      final s = asAdmin();
      final c = s.instructorCases.firstWhere((c) => c.state == CaseState.pending);
      s.decideInstructor(c, true);
      expect(c.state, CaseState.pending);
    });

    test('撤銷教官資格', () {
      final s = asAdmin();
      s.isInstructor = true;
      s.revokeInstructor();
      expect(s.isInstructor, isTrue);
    });

    test('有權限就做得了 —— 擋的是權限，不是功能', () {
      final s = asAdmin(scopes: {AdminScope.contentReview});
      final c = pendingReport(s);
      s.reviewReport(c);
      s.upholdReport(c);
      expect(c.state, CaseState.upheld);
    });
  });

  group('商品管理：無權限者在狀態層就被擋下', () {
    test('新增商品 / 設定商品資訊', () {
      final s = asAdmin();
      final n = s.adminProducts.length;
      expect(s.addProduct(name: '新品', subtype: VirtualSubtype.consumable),
          isNotNull, reason: '回傳權限不足的理由');
      expect(s.adminProducts.length, n);
    });

    test('上架 / 下架', () {
      final s = asAdmin();
      final p = s.adminProducts.first;
      final listing = p.listing;
      s.listProduct(p);
      s.delistProduct(p);
      expect(p.listing, listing);
    });

    test('有權限就新增得了商品', () {
      final s = asAdmin(scopes: {AdminScope.productManage});
      final n = s.adminProducts.length;
      expect(
          s.addProduct(name: '新品', subtype: VirtualSubtype.consumable), isNull);
      expect(s.adminProducts.length, n + 1);
    });
  });

  group('停用的管理員一律不能動作', () {
    test('權限組齊全但狀態已停用，照樣擋下', () {
      final s = asAdmin(scopes: AdminScope.values.toSet(), active: false);
      expect(s.canReview, isFalse);
      expect(s.canManageProducts, isFalse);
      expect(s.canConfigure, isFalse);

      final c = pendingReport(s);
      s.reviewReport(c);
      expect(c.state, CaseState.pending,
          reason: '停用者只要進得了畫面就審得了案，正是這條 Precondition 要擋的');
    });
  });

  group('權限組不互相涵蓋', () {
    test('只有商品管理者審不了案', () {
      final s = asAdmin(scopes: {AdminScope.productManage});
      final c = pendingReport(s);
      s.reviewReport(c);
      expect(c.state, CaseState.pending);
    });

    test('只有內容審核者動不了商品、也改不了平台參數', () {
      final s = asAdmin(scopes: {AdminScope.contentReview});
      final n = s.adminProducts.length;
      expect(s.addProduct(name: '新品', subtype: VirtualSubtype.consumable),
          isNotNull);
      expect(s.adminProducts.length, n);
      expect(s.applySettings('reward', {'checkInCoin': 99}), isNotNull);
    });
  });
}
