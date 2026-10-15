import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../mock/mock_admin.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'product_edit_screen.dart';

/// Read Model：管理員商品清單
///
/// 呈現全部商品（含已下架）—— 上架 Command 的對象正是已下架商品。
/// 本 Read Model 不含訂單明細，明細見〈管理員訂單佇列〉。
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.admin.can(AdminScope.productManage)) {
      return Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(title: const Text('權限不足')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: '沒有「${adminScopeNames[AdminScope.productManage]}」權限',
          message: '管理員 Command 的 Precondition 要求權限組涵蓋該 Command。',
        ),
      );
    }

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: const Text('商品清單'),
        actions: [
          IconButton(
            onPressed: () => _add(context, s),
            icon: const Icon(Icons.add, size: Sz.iconDefault),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          for (final p in s.adminProducts)
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 商品圖片為圖片集合；清單只呈現第一張。
                        p.images.isEmpty
                            ? Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: C.bgPage,
                                  borderRadius: BorderRadius.circular(R.child),
                                  border: Border.all(color: C.lineDivider),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.image_outlined,
                                  size: Sz.iconDense,
                                  color: C.textSecondary,
                                ),
                              )
                            : AppImageView(id: p.images.first, size: 48),
                        const SizedBox(width: S.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: T.h3()),
                              const SizedBox(height: 2),
                              Text(
                                '${p.id}'
                                '${p.subtype == null ? '' : '　·　${virtualSubtypeNames[p.subtype]}'}',
                                style: T.caption(),
                              ),
                            ],
                          ),
                        ),
                        TagBadge(
                          listingStateNames[p.listing]!,
                          borderColor: p.listing == ListingState.listed
                              ? C.statusSuccess
                              : C.lineDivider,
                        ),
                      ],
                    ),
                    const Divider(height: S.lg, color: C.lineDivider),
                    // 各規格的價格與庫存（屬商品規格子聚合）
                    for (final spec in p.specs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: S.sm),
                        child: Row(
                          children: [
                            Expanded(child: Text(spec.name, style: T.body())),
                            Text('${spec.price} 金幣', style: T.body()),
                            const SizedBox(width: S.base),
                            SizedBox(
                              width: 72,
                              child: Text(
                                // 權限解鎖類不適用庫存，不呈現庫存數字。
                                !p.stockApplies
                                    ? '不適用'
                                    : spec.stock == 0
                                    ? '無庫存'
                                    : '庫存 ${spec.stock}',
                                textAlign: TextAlign.end,
                                style: T.body(
                                  color: p.stockApplies && spec.stock == 0
                                      ? C.statusError
                                      : C.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: S.md),
                    if (!p.infoComplete) ...[
                      const SizedBox(height: S.sm),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(S.md),
                        decoration: BoxDecoration(
                          color: C.statusError.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(R.child),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: Sz.iconDense,
                              color: C.statusError,
                            ),
                            const SizedBox(width: S.sm),
                            Expanded(
                              child: Text(
                                '商品資訊未設定完，不得上架。',
                                style: T.caption(color: C.statusError),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: S.md),
                    ButtonRow(
                      left: AppButton(
                        label: '設定商品資訊',
                        kind: BtnKind.secondary,
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProductEditScreen(product: p),
                            ),
                          );
                          if (context.mounted) setState(() {});
                        },
                      ),
                      right: AppButton(
                        label: p.listing == ListingState.listed ? '下架' : '上架',
                        kind: p.listing == ListingState.listed
                            ? BtnKind.secondary
                            : BtnKind.primary,
                        // 上架的 Precondition 不成立時，按鈕直接不可點 ——
                        // 讓管理員按下去才被擋，不如一開始就看得出來。
                        onPressed:
                            (p.listing == ListingState.delisted && !p.canList)
                            ? null
                            : () => _toggle(context, s, p),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, AppState s) async {
    final name = TextEditingController();
    VirtualSubtype? subtype = VirtualSubtype.consumable;
    final ok = await showAppDialog(
      context,
      title: '新增商品',
      size: DialogSize.medium,
      confirmLabel: '新增',
      content: StatefulBuilder(
        builder: (_, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              style: T.body(),
              decoration: InputDecoration(
                hintText: '商品名稱',
                hintStyle: T.body(color: C.textDisabled),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.control),
                ),
              ),
            ),
            const SizedBox(height: S.base),
            Text('子類型（新增後不再變更）', style: T.caption()),
            const SizedBox(height: S.sm),
            Wrap(
              spacing: S.sm,
              children: [
                for (final v in VirtualSubtype.values)
                  GestureDetector(
                    onTap: () => setInner(() => subtype = v),
                    child: TagBadge(
                      virtualSubtypeNames[v]!,
                      borderColor: subtype == v
                          ? C.actionOutline
                          : C.lineDivider,
                      fill: subtype == v ? C.actionOutline : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final failure = s.addProduct(name: name.text, subtype: subtype);
    if (failure != null) {
      showToast(context, failure);
      return;
    }
    setState(() {});
    // 新商品一律自已下架起算，直接帶進編輯器補齊資訊。
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductEditScreen(product: s.adminProducts.last),
      ),
    );
    if (context.mounted) setState(() {});
  }

  Future<void> _toggle(BuildContext context, AppState s, AdminProduct p) async {
    if (p.listing == ListingState.delisted) {
      final failure = s.listProduct(p);
      showToast(context, failure ?? '已上架');
      setState(() {});
      return;
    }
    final pending = s.pendingOrdersOf(p);
    final ok = await showAppDialog(
      context,
      title: '確認下架',
      message:
          '${p.name} 下架後不再販售。'
          '${pending > 0 ? '$pending 筆待付款訂單將自動取消並釋放庫存；' : ''}',
      confirmLabel: '下架',
      // 破壞性動作仍用次要樣式（§4.5 R-23），安全由本彈窗承擔。
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    final cancelled = s.delistProduct(p);
    showToast(
      context,
      cancelled.isEmpty ? '已下架' : '已下架，並取消 ${cancelled.length} 筆待付款訂單',
    );
    setState(() {});
  }
}
