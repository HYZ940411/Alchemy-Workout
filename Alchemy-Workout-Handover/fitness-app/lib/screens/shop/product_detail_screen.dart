import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../design/tokens.dart';
import '../../domain/commerce.dart';
import '../../design/skeleton.dart';
import '../../state/app_state.dart';
import '../../widgets/load_boundary.dart';
import '../../widgets/common.dart';
import 'checkout_screen.dart';
import 'shipping_screen.dart';

/// Read Model：商品頁（商品詳情）
///
/// 支撐的 Command：選擇尺寸與數量、確認購買。
/// 庫存為**規格層級** —— 某一規格售完不影響其他規格，故逐規格呈現庫存狀態。
/// 不呈現購買人數或熱門度：商城品項少且多為平台自營。
class ProductDetailScreen extends StatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int specIndex = 0;
  int qty = 1;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = widget.product;
    final spec = p.specs[specIndex];
    final total = spec.coinPrice * qty;
    // 補差額試算：金幣不足時所需支付的法幣金額。
    // 使用者於確認購買前若不知需付多少現金，該 Command 即無決策依據。
    final shortCoins = total - s.coins;
    final cash = cashForShortfall(shortCoins);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: Text(p.name, style: T.h3())),
      // E 詳情型骨架：大圖 ＋ 段落 ＋ 規格清單。詳情頁一定有資料，故無空狀態。
      body: LoadBoundary(
        id: 'product:${p.id}',
        kind: SkeletonKind.detailE,
        rows: 4,
        builder: (context) => ListView(
          padding: const EdgeInsets.fromLTRB(
            S.base,
            S.base,
            S.base,
            S.scrollBottom,
          ),
          children: [
            if (p.images.isNotEmpty)
              Center(child: AppImageView(id: p.images.first, size: 160)),
            const SizedBox(height: S.base),
            Row(
              children: [
                Expanded(child: Text(p.name, style: T.h2())),
                TagBadge(p.kind == ProductKind.physical ? '實體' : '虛擬'),
              ],
            ),
            if (p.note != null) ...[
              const SizedBox(height: S.xs),
              Text(p.note!, style: T.caption()),
            ],

            const SectionTitle('規格', trailing: '價格與庫存依所選規格決定'),
            Wrap(
              spacing: S.md,
              runSpacing: S.md,
              children: [
                for (var i = 0; i < p.specs.length; i++)
                  _SpecChip(
                    spec: p.specs[i],
                    selected: i == specIndex,
                    onTap: p.specs[i].inStock
                        ? () => setState(() {
                            specIndex = i;
                            // 換規格時數量回到 1：新規格的庫存可能更少。
                            qty = 1;
                          })
                        : null,
                  ),
              ],
            ),

            const SectionTitle('數量'),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.inStock ? '此規格庫存 ${spec.stock} 件' : '暫無庫存',
                      style: T.body(
                        color: spec.inStock ? C.textSecondary : C.statusError,
                      ),
                    ),
                  ),
                  _Stepper(
                    value: qty,
                    // 所選規格的庫存 ≥ 所選數量。
                    max: spec.stock,
                    onChanged: (v) => setState(() => qty = v),
                  ),
                ],
              ),
            ),

            const SectionTitle('金額'),
            AppCard(
              child: Column(
                children: [
                  _Line(label: '單價', value: '${spec.coinPrice} 金幣'),
                  const SizedBox(height: S.md),
                  _Line(label: '數量', value: '× $qty'),
                  const Divider(height: S.lg, color: C.lineDivider),
                  _Line(label: '小計', value: '$total 金幣', strong: true),
                  const SizedBox(height: S.md),
                  _Line(label: '我的金幣餘額', value: '${s.coins} 金幣'),
                  if (shortCoins > 0) ...[
                    const SizedBox(height: S.md),
                    _Line(
                      label: '金幣不足 $shortCoins，補差額',
                      value: 'NT\$$cash',
                      color: C.accentDeep,
                    ),
                  ],
                ],
              ),
            ),

            if (p.kind == ProductKind.physical) ...[
              const SizedBox(height: S.base),
              Text('下一步填寫收貨資訊，會帶入上次填寫的內容。', style: T.caption()),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: spec.inStock
                  ? (p.kind == ProductKind.physical ? '填寫收貨資訊' : '前往結帳')
                  : '暫無庫存',
              onPressed: !spec.inStock
                  ? null
                  : () async {
                      final shipping = p.kind == ProductKind.physical
                          ? await Navigator.of(context).push<ShippingInfo>(
                              MaterialPageRoute(
                                builder: (_) => const ShippingScreen(),
                              ),
                            )
                          : null;
                      if (!context.mounted) return;
                      if (p.kind == ProductKind.physical && shipping == null) {
                        return; // 使用者中途離開，不成立任何訂單
                      }
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CheckoutScreen(
                            product: p,
                            spec: spec,
                            qty: qty,
                            shipping: shipping,
                          ),
                        ),
                      );
                      if (context.mounted) setState(() {});
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  final ProductSpec spec;
  final bool selected;
  final VoidCallback? onTap;
  const _SpecChip({required this.spec, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final out = spec.stock == 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.base, vertical: S.md),
        decoration: BoxDecoration(
          color: selected ? C.actionOutline : C.bgSurface,
          borderRadius: BorderRadius.circular(R.control),
          border: Border.all(
            color: selected ? C.actionOutline : C.lineDivider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              spec.name,
              style: T.body(
                weight: FontWeight.w700,
                color: selected ? C.onFill(C.actionOutline) : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              // 庫存狀態為列舉（有庫存 / 暫無庫存），供前端判定按鈕是否可點。
              out ? '暫無庫存' : '${spec.coinPrice} 金幣',
              style: T.caption(
                color: out
                    ? C.statusError
                    : (selected ? C.onFill(C.actionOutline) : C.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  const _Stepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: C.bgPage,
      borderRadius: BorderRadius.circular(R.control),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: Sz.iconDense),
          color: C.textSecondary,
          constraints: const BoxConstraints(minWidth: Sz.tapTarget),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: T.numberS(),
          ),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add, size: Sz.iconDense),
          color: C.actionOutline,
          constraints: const BoxConstraints(minWidth: Sz.tapTarget),
        ),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final Color? color;
  const _Line({
    required this.label,
    required this.value,
    this.strong = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: T.body(
            color: color ?? (strong ? null : C.textSecondary),
            weight: strong ? FontWeight.w600 : null,
          ),
        ),
      ),
      Text(
        value,
        style: strong
            ? T.numberS(color: color)
            : T.body(color: color ?? C.textSecondary),
      ),
    ],
  );
}
