import 'package:flutter/material.dart';

import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'order_detail_screen.dart';

/// Read Model：我的訂單頁
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {

  static Color _color(OrderState st) {
    switch (st) {
      case OrderState.pendingPayment:
        return AppColors.gold;
      case OrderState.paid:
      case OrderState.shipped:
        return AppColors.blue;
      case OrderState.delivered:
        return AppColors.accent;
      case OrderState.failed:
        return AppColors.bronze;
      default:
        return AppColors.textFaint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // 進頁先結算逾期的預扣，使用者看到的一定是已結算過的狀態。
    WidgetsBinding.instance.addPostFrameCallback((_) => s.releaseExpiredHolds());
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('我的訂單',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
        children: [
          if (s.orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: S.xl),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: '還沒有訂單',
                message: '在商城購買實體或虛擬商品後，訂單會出現在這裡。',
              ),
            ),
          for (final o in s.orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 出貨通知為 App 內通知類（不推播）：未查看者標紅點。
                        if (s.unreadShipped.contains(o.id)) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: C.statusError,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: S.sm),
                        ],
                        Expanded(
                          child: Text('${o.productName}　${o.spec}',
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Pill(orderStateNames[o.state]!, color: _color(o.state)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${o.kind == ProductKind.physical ? '實體' : '虛擬'}　·　'
                      '數量 ${o.qty}　·　'
                      '${o.placedAt.month}/${o.placedAt.day} 下單',
                      style: const TextStyle(
                          color: AppColors.textFaint, fontSize: 11.5),
                    ),
                    const Divider(height: 20, color: AppColors.line),
                    // 支付明細：金幣扣除數與法幣支付額分列
                    Row(
                      children: [
                        Expanded(
                          child: StatTile(
                              label: '金幣扣除', value: '${o.coinPaid}'),
                        ),
                        Expanded(
                          child: StatTile(
                              label: '法幣支付', value: 'NT\$${o.cashPaid}'),
                        ),
                      ],
                    ),
                    if (o.failReason != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '失敗原因：${failReasonNames[o.failReason]}',
                          style: const TextStyle(
                              color: AppColors.bronze, fontSize: 11.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: '查看訂單詳情',
                        kind: BtnKind.secondary,
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => OrderDetailScreen(order: o)));
                          if (context.mounted) setState(() {});
                        },
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
}
