import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../design/tokens.dart';
import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'order_detail_screen.dart';

/// 結帳確認頁（〈實體商品購買流程〉：使用者已確認購買）
///
/// 確認購買時**預扣庫存**，非支付成功後才扣減 —— 實體商品超賣的後果是
/// 須向真實顧客道歉退款，非可由失敗補償帶過的技術問題。
/// 預扣保留一段時間（平台級可調參數），逾時未付款自動釋放。
///
/// 支付邊界：實體商品的支付由第三方金流執行，不走 App Store 應用內購買
/// （App Store 3.1.3(e)：於 App 外消費的實體商品須以 IAP 以外的方式收款）。
class CheckoutScreen extends StatelessWidget {
  final Product product;
  final ProductSpec spec;
  final int qty;
  final ShippingInfo? shipping;

  const CheckoutScreen({
    super.key,
    required this.product,
    required this.spec,
    required this.qty,
    this.shipping,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final total = spec.coinPrice * qty;
    final coinPart = s.coins >= total ? total : s.coins;
    final cashPart = cashForShortfall(total - coinPart);
    final physical = product.kind == ProductKind.physical;

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

          if (physical && shipping != null) ...[
            const SectionTitle('收貨資訊'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shipping!.name, style: T.body(weight: FontWeight.w600)),
                  const SizedBox(height: S.xs),
                  Text(shipping!.phone, style: T.caption()),
                  const SizedBox(height: S.xs),
                  Text('${shipping!.zip} ${shipping!.address}',
                      style: T.caption()),
                  if (shipping!.note.isNotEmpty) ...[
                    const SizedBox(height: S.xs),
                    Text('備註：${shipping!.note}', style: T.caption()),
                  ],
                ],
              ),
            ),
          ],

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

          if (physical) ...[
            const SectionTitle('付款方式'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.credit_card_rounded,
                          size: Sz.iconDense, color: C.textSecondary),
                      const SizedBox(width: S.md),
                      Expanded(
                        child: Text('第三方金流（信用卡／行動支付）',
                            style: T.body()),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.md),
                  Text(
                    '實體商品不走 App Store 應用內購買。確認後訂單成立為待付款，'
                    '庫存立即預扣並保留 ${kStockHold.inMinutes} 分鐘，逾時未付款自動釋放。',
                    style: T.caption(),
                  ),
                ],
              ),
            ),
          ],
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
                final failure = s.confirmPurchase(
                  product,
                  spec,
                  qty,
                  shipping: shipping,
                );
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
