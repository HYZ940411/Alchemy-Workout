import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'admin_orders_screen.dart';
import 'admin_products_screen.dart';
import 'admin_ratings_screen.dart';
import 'platform_settings_screen.dart';
import 'review_queue_screen.dart';

/// 管理員後台首頁
///
/// 管理員為獨立 Aggregate，與使用者帳號分離。
/// 每個管理員 Command 的 Precondition：狀態為生效中，且權限組涵蓋該 Command。
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    void go(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    final disabled = s.admin.status == AdminStatus.disabled;
    final toShip = s.adminOrders.where((o) => o.state == '已付款').length;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('管理員後台')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.admin.name, style: T.h3()),
                          const SizedBox(height: 2),
                          Text('管理員 ID ${s.admin.id}', style: T.caption()),
                        ],
                      ),
                    ),
                    TagBadge(
                      disabled ? '已停用' : '生效中',
                      borderColor:
                          disabled ? C.statusError : C.statusSuccess,
                    ),
                  ],
                ),
                const SizedBox(height: S.md),
                Text('權限組（至少 1 項，可同時具備多組）', style: T.caption()),
                const SizedBox(height: S.sm),
                Wrap(
                  spacing: S.sm,
                  runSpacing: S.sm,
                  children: [
                    for (final sc in AdminScope.values)
                      GestureDetector(
                        onTap: () {
                          final next = {...s.admin.scopes};
                          next.contains(sc) ? next.remove(sc) : next.add(sc);
                          s.setAdminScopes(next);
                        },
                        child: TagBadge(
                          '${adminScopeNames[sc]}'
                          '（${adminScopeCommandCount[sc]}）',
                          borderColor: s.admin.scopes.contains(sc)
                              ? C.actionOutline
                              : C.lineDivider,
                          fill: s.admin.scopes.contains(sc)
                              ? C.actionOutline
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: S.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        disabled ? '已停用者不得執行任何管理員 Command。' : '帳號狀態生效中',
                        style: T.caption(),
                      ),
                    ),
                    AppSwitch(
                      value: !disabled,
                      onChanged: (v) => s.setAdminStatus(
                          v ? AdminStatus.active : AdminStatus.disabled),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionTitle('作業'),
          ListGroup(rows: [
            ListRow(
              title: '待審佇列',
              subtitle: '檢舉、申訴、教官申請、公開課表',
              trailing: s.pendingReviewCount > 0
                  ? CountBadge(s.pendingReviewCount)
                  : null,
              chevron: true,
              onTap: () => go(const ReviewQueueScreen()),
            ),
            ListRow(
              title: '訂單佇列',
              subtitle: '待出貨、待退款、已出貨',
              trailing: toShip > 0 ? CountBadge(toShip) : null,
              chevron: true,
              onTap: () => go(const AdminOrdersScreen()),
            ),
            ListRow(
              title: '商品清單',
              subtitle: '${s.adminProducts.length} 項（含已下架）',
              chevron: true,
              onTap: () => go(const AdminProductsScreen()),
            ),
            ListRow(
              title: '評分彙總',
              subtitle: '延遲更新　·　分析用途',
              chevron: true,
              onTap: () => go(const AdminRatingsScreen()),
            ),
          ]),
          const SectionTitle('平台設定'),
          ListGroup(rows: [
            ListRow(
              title: '平台設定',
              subtitle: '16 個 Command　·　訓練計畫、平台動作、成就與獎勵定義、'
                  '任務範本、各項門檻、管理員帳號',
              trailing: s.settingLog.isEmpty
                  ? null
                  : TagBadge('${s.settingLog.length} 筆變更'),
              chevron: true,
              showDivider: false,
              onTap: () => go(const PlatformSettingsScreen()),
            ),
          ]),
        ],
      ),
    );
  }
}
