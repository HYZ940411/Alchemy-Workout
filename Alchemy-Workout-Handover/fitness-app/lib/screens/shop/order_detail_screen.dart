import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 訂單詳情頁（〈Read Model：我的訂單頁〉的單筆檢視）
///
/// 支撐的 Command：取消訂單（僅待付款可用）。
/// 支付明細金幣與法幣分列；已失敗者呈現失敗原因。
///
/// 虛擬商品沒有物流與退款（發放失敗不自動退款，見〈虛擬商品購買流程〉）。
class OrderDetailScreen extends StatefulWidget {
  final Order order;
  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Order get o => widget.order;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // 訂單可能已被整筆替換（失敗原因為 final 欄位），故依 ID 取回當前狀態。
    final cur = s.orders.firstWhere((x) => x.id == o.id, orElse: () => o);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('訂單詳情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cur.productName,
                        style: T.body(weight: FontWeight.w700),
                      ),
                    ),
                    TagBadge(
                      orderStateNames[cur.state]!,
                      borderColor: _stateColor(cur.state),
                    ),
                  ],
                ),
                const SizedBox(height: S.xs),
                Text('${cur.spec}　×${cur.qty}', style: T.caption()),
                const SizedBox(height: S.xs),
                Text('訂單編號 ${cur.id}', style: T.caption()),
                const SizedBox(height: S.xs),
                Text(
                  '下單於 ${cur.placedAt.month}/${cur.placedAt.day} '
                  '${cur.placedAt.hour.toString().padLeft(2, '0')}:'
                  '${cur.placedAt.minute.toString().padLeft(2, '0')}',
                  style: T.caption(),
                ),
              ],
            ),
          ),

          if (cur.state == OrderState.cancelled && cur.cancelledBySystem) ...[
            const SizedBox(height: S.md),
            AppCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: Sz.iconDense,
                    color: C.textSecondary,
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Text(
                      '本筆由系統取消（商品下架），'
                      '非你自行取消。已扣的金幣與庫存皆已回補。',
                      style: T.caption(),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (cur.failReason != null) ...[
            const SizedBox(height: S.md),
            AppCard(
              borderColor: C.statusError,
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: Sz.iconDense,
                    color: C.statusError,
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Text(
                      '失敗原因：${failReasonNames[cur.failReason]}',
                      style: T.caption(color: C.statusError),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SectionTitle('支付明細', trailing: '金幣與法幣分列'),
          AppCard(
            child: Column(
              children: [
                _Line(label: '金幣扣除', value: '${cur.coinPaid} 金幣'),
                const SizedBox(height: S.md),
                _Line(
                  label: '法幣支付',
                  value: cur.cashPaid == 0 ? '—' : 'NT\$${cur.cashPaid}',
                ),
              ],
            ),
          ),

          const SizedBox(height: S.lg),
          // 取消的可用條件須明示，否則使用者將反覆尋找取消入口。
          Text(
            cur.cancellable
                ? '僅待付款的訂單可取消。'
                : '本訂單狀態為「${orderStateNames[cur.state]}」，不可取消。',
            style: T.caption(),
          ),
        ],
      ),
      bottomNavigationBar: cur.state != OrderState.pendingPayment
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
              // bottomNavigationBar 給的是寬鬆約束：不收成 min 高度，
              // ButtonRow 會撐滿整個畫面，把 body 擠成 0 高。
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ButtonRow(
                    left: AppButton(
                      label: '取消訂單',
                      // 破壞性動作仍用次要樣式（§4.5 R-23）。
                      kind: BtnKind.secondary,
                      onPressed: () async {
                        final ok = await showAppDialog(
                          context,
                          title: '取消這筆訂單？',
                          message: '取消後庫存立即釋放，已扣的金幣退回。此動作無法復原。',
                          confirmLabel: '取消訂單',
                          cancelLabel: '保留',
                          destructive: true,
                        );
                        if (ok != true || !context.mounted) return;
                        s.cancelOrder(cur);
                        showToast(context, '已取消，庫存與金幣已回補');
                        setState(() {});
                      },
                    ),
                    right: AppButton(
                      label: '前往付款',
                      onPressed: () async {
                        // 支付由第三方金流執行，本系統被動接收回呼。
                        final ok = await showAppDialog(
                          context,
                          title: '付款',
                          message: '此處模擬付款回呼結果。',
                          confirmLabel: '支付成功',
                          cancelLabel: '支付失敗',
                        );
                        if (!context.mounted) return;
                        if (ok == true) {
                          s.payOrder(cur);
                          showToast(context, '已付款');
                        } else if (ok == false) {
                          s.failPayment(cur, FailReason.other);
                          showToast(context, '支付失敗，庫存與金幣已回補');
                        } else {
                          return; // 點擊遮罩關閉，什麼都不做
                        }
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static Color _stateColor(OrderState s) => switch (s) {
    OrderState.pendingPayment => C.accentDeep,
    OrderState.paid || OrderState.delivered => C.statusSuccess,
    OrderState.failed => C.statusError,
    OrderState.cancelled => C.lineDivider,
  };
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  const _Line({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: T.body(color: C.textSecondary)),
      ),
      Text(value, style: T.numberS()),
    ],
  );
}
