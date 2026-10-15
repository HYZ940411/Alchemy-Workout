import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../design/tokens.dart';
import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'order_detail_screen.dart';

/// 結帳確認頁（〈虛擬商品購買流程〉：使用者已確認購買）
///
/// 確認購買時訂單成立為待付款並扣減庫存，取消或支付失敗時回補。
class CheckoutScreen extends StatelessWidget {
  final Product product;
  final ProductSpec spec;
  final int qty;

  const CheckoutScreen({
    super.key,
    required this.product,
    required this.spec,
    required this.qty,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final total = spec.coinPrice * qty;
    final coinPart = s.coins >= total ? total : s.coins;
    final cashPart = cashForShortfall(total - coinPart);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('確認訂單')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          const SectionTitle('商品'),
          AppCard(
            child: Row(
              children: [
                if (product.images.isNotEmpty) ...[
                  AppImageView(id: product.images.first, size: 56),
                  const SizedBox(width: S.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          style: T.body(weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${spec.name}　×$qty', style: T.caption()),
                    ],
                  ),
                ),
                Text('$total 金幣', style: T.numberS()),
              ],
            ),
          ),

          // 支付明細拆分呈現：僅顯示總額者，使用者數月後無從對照
          // 當時扣了多少金幣、補了多少現金 —— 而那正是爭議發生時他要查的資料。
          const SectionTitle('支付明細', trailing: '金幣與法幣分列'),
          AppCard(
            child: Column(
              children: [
                _Line(label: '訂單金額', value: '$total 金幣'),
                const SizedBox(height: S.md),
                _Line(label: '金幣扣除', value: '$coinPart 金幣'),
                const SizedBox(height: S.md),
                _Line(
                  label: '法幣支付',
                  value: cashPart == 0 ? '—' : 'NT\$$cashPart',
                  color: cashPart == 0 ? null : C.accentDeep,
                ),
                const Divider(height: S.lg, color: C.lineDivider),
                Text(
                  cashPart == 0
                      ? '金幣足額支付，不需補差額。'
                      : '金幣不足，差額以法幣支付。訂單成立時鎖定當時比率'
                          '（1 元 ＝ $kCoinsPerNtd 金幣），其後比率變動不影響本筆訂單。',
                  style: T.caption(),
                ),
              ],
            ),
          ),

        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: '確認購買',
              onPressed: () {
                final failure = s.confirmPurchase(product, spec, qty);
                if (failure != null) {
                  showToast(context, '購買失敗：${failReasonNames[failure]}');
                  return;
                }
                final order = s.orders.first;
                // 訂單已成立，結帳頁就此換成訂單詳情 ——
                // 使用者按返回時不該又掉回一個已經按過的結帳頁。
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => OrderDetailScreen(order: order)));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Line({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(label, style: T.body(color: C.textSecondary))),
          Text(value, style: T.numberS(color: color)),
        ],
      );
}
