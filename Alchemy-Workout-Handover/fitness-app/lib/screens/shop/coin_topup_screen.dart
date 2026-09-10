import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 金幣儲值（〈金幣儲值流程〉）
///
/// 走 App Store 應用內購買，支付與扣款由 App Store 執行，本系統被動接收其通知。
/// 金幣無有效期限（App Store 3.1.1）。
class CoinTopUpScreen extends StatefulWidget {
  const CoinTopUpScreen({super.key});
  @override
  State<CoinTopUpScreen> createState() => _CoinTopUpScreenState();
}

class _CoinTopUpScreenState extends State<CoinTopUpScreen> {
  int selected = 1;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final pack = kCoinPacks[selected];

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('金幣儲值')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.base, S.base, S.scrollBottom),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded,
                          size: Sz.iconEmphasis, color: C.actionPrimary),
                      const SizedBox(width: S.md),
                      Expanded(
                        child: StatField(
                            label: '目前金幣餘額', value: '${s.coins}'),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('選擇面額', trailing: '1 元 ＝ 5 金幣'),
                for (var i = 0; i < kCoinPacks.length; i++) ...[
                  PriceCard(
                    icon: '🪙',
                    title: '${kCoinPacks[i].coins} 金幣',
                    subtitle: kCoinPacks[i].bonus > 0
                        ? '基本 ${kCoinPacks[i].base} ＋ 贈送 ${kCoinPacks[i].bonus}'
                            '（+${kCoinPacks[i].bonusPercent}%）'
                        : '無加贈',
                    price: 'NT\$ ${kCoinPacks[i].price}',
                    badge: kCoinPacks[i].badge,
                    selected: i == selected,
                    onTap: () => setState(() => selected = i),
                  ),
                  const SizedBox(height: S.md),
                ],
                AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: Sz.iconDense, color: C.accentInfo),
                      const SizedBox(width: S.md),
                      Expanded(
                        child: Text(
                          '金幣無有效期限。付款由 App Store 處理，'
                          '完成後系統會收到通知並入帳。',
                          style: T.caption(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: C.bgSurface,
              border: Border(top: BorderSide(color: C.lineDivider)),
            ),
            padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
                MediaQuery.of(context).padding.bottom + S.base),
            child: AppButton(
              label: '購買　NT\$ ${pack.price}',
              onPressed: () async {
                final ok = await showAppDialog(
                  context,
                  title: '確認購買',
                  message: '將由 App Store 向你收取 NT\$ ${pack.price}，'
                      '完成後入帳 ${pack.coins} 金幣。',
                  confirmLabel: '購買',
                );
                if (ok != true || !context.mounted) return;
                s.topUpCoins(pack);
                showToast(context, '已入帳 ${pack.coins} 金幣');
              },
            ),
          ),
        ],
      ),
    );
  }
}
