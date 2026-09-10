import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'membership_screen.dart';

/// Read Model：AI 點數頁
class AiCreditsScreen extends StatelessWidget {
  const AiCreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final now = appNow();
    final nextReset = DateTime(now.year, now.month + 1, 1, 4);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('AI 點數',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: '月度額度餘額',
                        value: '${s.aiMonthly}',
                        unit: s.isMember ? '/ $kMonthlyAiCredits' : null,
                        valueColor: AppColors.blue,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: '永久點數餘額',
                        value: '${s.aiPermanent}',
                        valueColor: AppColors.gold,
                      ),
                    ),
                  ],
                ),
                if (s.isMember) ...[
                  const SizedBox(height: 14),
                  Text(
                    '下次重置日：${nextReset.month}/${nextReset.day}（當地 04:00）',
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 11.5),
                  ),
                ],
                const Divider(height: 22, color: AppColors.line),
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppColors.textDim),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text('扣點順序：先扣月度額度、後扣永久點數',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 11.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionLabel('取得管道', trailing: '每次 AI 的成本'),
          _Channel(
            title: '訂閱會員',
            detail: '每月 20 點　·　190 元 ÷ 20 點 ＝ 每次 9.5 元',
            highlight: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MembershipScreen()),
            ),
          ),
          const _Channel(
            title: '金幣購買單次調整使用權限',
            detail: '150 金幣 ＝ 30 元',
          ),
          const _Channel(
            title: '法幣購買 AI 點數',
            detail: '依 SKU 定價，購得為永久點數，不重置、不過期',
          ),
          const SectionLabel('異動明細'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (final e in s.creditHistory) _Entry(entry: e),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Channel extends StatelessWidget {
  final String title;
  final String detail;
  final bool highlight;
  final VoidCallback? onTap;
  const _Channel({
    required this.title,
    required this.detail,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.all(14),
          color: highlight ? AppColors.accent.withValues(alpha: 0.05) : null,
          border: highlight ? AppColors.accent.withValues(alpha: 0.4) : null,
          child: InkWell(
            onTap: onTap,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(detail,
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 11.5)),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
      );
}

class _Entry extends StatelessWidget {
  final CreditEntry entry;
  const _Entry({required this.entry});

  @override
  Widget build(BuildContext context) {
    final positive = entry.delta > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  creditChangeNames[entry.kind]! +
                      (entry.source == null ? '' : '　${entry.source}'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.at.month}/${entry.at.day}　'
                  '餘額 月${entry.monthlyAfter} / 永${entry.permanentAfter}',
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${entry.delta}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: positive ? AppColors.accent : AppColors.bronze,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
