import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'ai_credits_screen.dart';
import 'membership_screen.dart';
import 'orders_screen.dart';
import 'coin_topup_screen.dart';
import 'shop_screen.dart';

/// 商店 —— 五格著陸頁之一。
/// R-07 結案理由：畫面盤點後確認商店有 9 個畫面，值得單獨佔一格。
class ShopHubScreen extends StatelessWidget {
  const ShopHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    void go(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: StatField(label: '金幣餘額', value: '${s.coins}'),
              ),
              Expanded(
                child: StatField(
                    label: 'AI 點數', value: '${s.aiTotal}', unit: '點'),
              ),
            ],
          ),
        ),
        const SectionTitle('購買'),
        ListGroup(rows: [
          ListRow(
            title: '商城',
            subtitle: '實體商品與虛擬商品',
            chevron: true,
            onTap: () => go(const ShopScreen()),
          ),
          ListRow(
            title: '金幣儲值',
            subtitle: '4 檔面額　1 元 ＝ 5 金幣',
            chevron: true,
            onTap: () => go(const CoinTopUpScreen()),
          ),
          ListRow(
            title: 'AI 點數',
            subtitle: '月度 ${s.aiMonthly} ＋ 永久 ${s.aiPermanent}',
            chevron: true,
            onTap: () => go(const AiCreditsScreen()),
          ),
          ListRow(
            title: '會員訂閱',
            subtitle: s.isMember ? '生效中' : 'NT\$190 / 月',
            chevron: true,
            onTap: () => go(const MembershipScreen()),
          ),
        ]),
        const SectionTitle('紀錄'),
        ListGroup(rows: [
          ListRow(
            title: '我的訂單',
            subtitle: '${s.orders.length} 筆',
            chevron: true,
            onTap: () => go(const OrdersScreen()),
          ),
        ]),
      ],
    );
  }
}
