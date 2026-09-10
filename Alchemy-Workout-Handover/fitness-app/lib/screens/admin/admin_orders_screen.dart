import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../mock/mock_admin.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Read Model：管理員訂單佇列
///
/// 只收實體訂單 —— 虛擬商品無出貨作業，其狀態子集亦無「已出貨」。
class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.admin.can(AdminScope.productManage)) {
      return const _Denied(scope: AdminScope.productManage);
    }
    final toShip = s.adminOrders.where((o) => o.state == '已付款').toList()
      ..sort((a, b) => a.paidAt.compareTo(b.paidAt)); // 待出貨依付款時戳排序
    final toRefund = s.adminOrders.where((o) => o.state == '待退款').toList();
    final shipped = s.adminOrders.where((o) => o.state == '已出貨').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(
          title: const Text('訂單佇列'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(Sz.tapTarget),
            child: AppTabBar(tabs: [
              '待出貨 ${toShip.length}',
              '待退款 ${toRefund.length}',
              '已出貨 ${shipped.length}',
            ]),
          ),
        ),
        body: TabBarView(
          children: [
            _List(
              orders: toShip,
              state: s,
              action: '出貨',
              showWait: true,
              empty: '沒有待出貨的訂單。',
            ),
            _List(
                orders: toRefund, state: s, action: '退款', empty: '沒有待退款的訂單。'),
            _List(orders: shipped, state: s, empty: '還沒有已出貨的訂單。'),
          ],
        ),
      ),
    );
  }
}

class _Denied extends StatelessWidget {
  final AdminScope scope;
  const _Denied({required this.scope});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(title: const Text('權限不足')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: '沒有「${adminScopeNames[scope]}」權限',
          message: '管理員 Command 的 Precondition 要求權限組涵蓋該 Command。',
        ),
      );
}

class _List extends StatelessWidget {
  final List<AdminOrder> orders;
  final AppState state;
  final String? action;
  final bool showWait;
  final String empty;
  const _List({
    required this.orders,
    required this.state,
    required this.empty,
    this.action,
    this.showWait = false,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return EmptyState(
          icon: Icons.local_shipping_outlined, title: '目前沒有訂單', message: empty);
    }
    final longest = showWait
        ? orders
            .map((o) => appNow().difference(o.paidAt))
            .reduce((a, b) => a > b ? a : b)
        : null;

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        AppCard(
          child: Row(
            children: [
              Expanded(
                  child: StatField(
                      label: '筆數', value: '${orders.length}', unit: '筆')),
              if (longest != null)
                Expanded(
                  child: StatField(
                      label: '最久等待（自付款起算）',
                      value: '${longest.inHours}',
                      unit: '小時'),
                ),
            ],
          ),
        ),
        const SizedBox(height: S.md),
        for (final o in orders)
          Padding(
            padding: const EdgeInsets.only(bottom: S.md),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(o.id, style: T.caption())),
                      TagBadge(o.state),
                    ],
                  ),
                  const SizedBox(height: S.sm),
                  Text('${o.product}　${o.spec}', style: T.h3()),
                  const SizedBox(height: S.xs),
                  Row(
                    children: [
                      ValueUnit(
                          value: '${o.qty}', unit: '件', style: T.numberS()),
                      const SizedBox(width: S.base),
                      // **金幣，不是法幣**。商品定價一律以金幣標示，
                      // 使用者端的訂單頁寫的也是「金幣扣除 900　法幣支付 NT$0」；
                      // 這裡寫 NT$ 900 就成了同一筆訂單兩個金額單位。
                      ValueUnit(
                          value: '${o.coinAmount}',
                          unit: '金幣',
                          style: T.numberS()),
                    ],
                  ),
                  const SizedBox(height: S.md),
                  Text('收貨資訊', style: T.caption()),
                  const SizedBox(height: S.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(S.md),
                    decoration: BoxDecoration(
                      color: C.bgPage,
                      borderRadius: BorderRadius.circular(R.child),
                    ),
                    child: Text(o.address, style: T.body()),
                  ),
                  const SizedBox(height: S.sm),
                  Text(
                    '下單 ${o.placedAt.month}/${o.placedAt.day}　·　'
                    '付款 ${o.paidAt.month}/${o.paidAt.day} '
                    '${o.paidAt.hour.toString().padLeft(2, '0')}:'
                    '${o.paidAt.minute.toString().padLeft(2, '0')}',
                    style: T.caption(),
                  ),
                  if (action != null) ...[
                    const SizedBox(height: S.md),
                    AppButton(
                      label: action!,
                      onPressed: () async {
                        final ok = await showAppDialog(
                          context,
                          title: '確認$action',
                          message: '${o.id}　${o.product} ${o.spec} × ${o.qty}',
                          confirmLabel: action!,
                        );
                        if (ok != true || !context.mounted) return;
                        action == '出貨'
                            ? state.shipOrder(o)
                            : state.refundOrder(o);
                        showToast(context, '已$action');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
