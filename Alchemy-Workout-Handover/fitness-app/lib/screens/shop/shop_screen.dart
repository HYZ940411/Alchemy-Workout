import 'package:flutter/material.dart';

import '../../design/image_library.dart';
import '../../domain/commerce.dart';
import '../../design/skeleton.dart';
import '../../state/app_state.dart';
import '../../widgets/load_boundary.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'product_detail_screen.dart';

/// Read Model：商品頁
class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '商城',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.monetization_on_rounded,
                    size: 15,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${s.coins}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // C 卡片格狀型骨架：首屏約三列，一列兩張。
      body: LoadBoundary(
        id: 'shop',
        kind: SkeletonKind.gridC,
        rows: 3,
        builder: (context) => _Grid(items: s.products),
      ),
    );
  }
}

/// 兩欄格狀（§8.6 C 型）。
///
/// **兩欄而非單欄的判準來自規格書**：「只有圖 ＋ 一行標題」的內容才撐得起
/// 半個版面，商品正是這一類；成就卡有標題＋說明＋進度＋獎勵，故走整版寬。
///
/// 一列兩張、間距 12px、**同列等高** —— 品名一行與兩行的卡若不等高，
/// 兩張卡的底緣會錯開，整片格狀看起來像沒對齊。
class _Grid extends StatelessWidget {
  final List<Product> items;
  const _Grid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.storefront_outlined,
        title: '還沒有商品',
        message: '上架後就會出現在這裡。',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.scrollBottom),
      children: [
        for (var i = 0; i < items.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: S.md),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _ProductCard(product: items[i])),
                  const SizedBox(width: S.md),
                  // 奇數張時最後一列只有一張，**不讓它撐成滿版** ——
                  // 撐開會讓最後一張看起來是另一種卡片。
                  Expanded(
                    child: i + 1 < items.length
                        ? _ProductCard(product: items[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 格狀卡：只呈現「這是什麼、多少錢、有沒有貨」。
/// 選規格與數量在商品詳情頁 —— 那才是「使用者已選擇尺寸與數量」的所在。
///
/// 版面對齊 C 型骨架（方塊 92 高 ＋ 兩行條），骨架換成真內容時不會跳版。
class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final prices = p.specs.map((x) => x.coinPrice).toList()..sort();
    final anyStock = p.specs.any((x) => x.inStock);

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 92,
            width: double.infinity,
            child: p.images.isNotEmpty
                ? AppImageView(
                    id: p.images.first,
                    size: 92,
                    width: double.infinity,
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: C.bgPage,
                      borderRadius: BorderRadius.circular(R.child),
                    ),
                    alignment: Alignment.center,
                    child: Text(p.emoji, style: const TextStyle(fontSize: 40)),
                  ),
          ),
          const SizedBox(height: S.md),
          // 品名可能長到兩行（「單次 AI 調整使用權」），留兩行再截斷。
          Text(
            p.name,
            style: T.body(weight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: S.xs),
          if (!anyStock)
            const TagBadge('暫無庫存', borderColor: C.statusError)
          else
            Row(
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  size: 14,
                  color: AppColors.gold,
                ),
                const SizedBox(width: S.xs),
                Flexible(
                  child: Text(
                    prices.first == prices.last
                        ? '${prices.first}'
                        : '${prices.first}–${prices.last}',
                    style: T.numberS(color: AppColors.gold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (p.note != null) ...[
            const SizedBox(height: S.xs),
            Text(
              p.note!,
              style: T.caption(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
