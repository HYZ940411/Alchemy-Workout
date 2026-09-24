import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Read Model：管理員評分彙總
///
/// 無直接支撐的 Command —— 用途為平台優化自身提供的內容。
/// 採延遲更新：本 Read Model 為分析用途，不支撐任何即時決策。
class AdminRatingsScreen extends StatelessWidget {
  const AdminRatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final rows = s.ratingSummaries;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('評分彙總')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          if (rows.isEmpty)
            // **說實話比留一張空表好。** 使用者的評分目前存在他自己的
            // `users/{uid}` 底下，而那棵樹依安全規則只有本人讀得到 ——
            // 不是「還沒有人評分」，是這條路根本還沒接。
            // 在此之前這裡畫的是一張編出來的假彙總表，而這張表的用途
            // 正是回答「哪一份訓練計畫該改」。
            Panel(
              color: C.statusWarning.withValues(alpha: 0.08),
              border: C.statusWarning,
              child: Text(
                '評分尚未接上後台。\n'
                '使用者的評分目前存在各自的帳號資料裡，管理端讀不到 ——'
                '這裡不會有資料，直到評分獨立成自己的集合（BE-18）。',
                style: T.caption(),
              ),
            )
          else ...[
            Row(
              children: [
                const Icon(Icons.schedule,
                    size: Sz.iconDense, color: C.textSecondary),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text('延遲更新　·　資料更新於 2 小時前', style: T.caption()),
                ),
              ],
            ),
            const SizedBox(height: S.md),
            // 兩種評分對象類型共用同一張彙總表，新手任務為其中一列
            for (final r in rows) _SummaryCard(r: r),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final RatingSummary r;
  const _SummaryCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final maxCount = r.distribution.reduce((a, b) => a > b ? a : b);
    final low = r.average < 3.5;

    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(S.base, S.sm, S.base, S.sm),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            iconColor: C.textSecondary,
            collapsedIconColor: C.textSecondary,
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: T.h3()),
                      const SizedBox(height: 2),
                      Text(ratingTargetNames[r.target]!, style: T.caption()),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      r.average.toStringAsFixed(1),
                      style: T.numberM(
                          color: low ? C.statusError : C.textPrimary),
                    ),
                    Text('${r.count} 則', style: T.caption()),
                  ],
                ),
              ],
            ),
            children: [
              const SizedBox(height: S.sm),
              // 星等分布
              for (var i = 4; i >= 0; i--)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.sm),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 28, child: Text('${i + 1}★', style: T.caption())),
                      Expanded(
                        child: BareProgress(
                          value: maxCount == 0
                              ? 0
                              : r.distribution[i] / maxCount,
                          color: i >= 3 ? C.statusSuccess : C.gradeC,
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text('${r.distribution[i]}',
                            textAlign: TextAlign.end, style: T.caption()),
                      ),
                    ],
                  ),
                ),
              const Divider(height: S.lg, color: C.lineDivider),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('逐筆評分', style: T.caption()),
              ),
              const SizedBox(height: S.sm),
              for (final (stars, text, at) in r.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text('$stars★',
                            style: T.body(weight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 文字回饋為選填，可為空
                            Text(text ?? '（未留下文字回饋）',
                                style: T.body(
                                    color: text == null
                                        ? C.textSecondary
                                        : C.textPrimary)),
                            const SizedBox(height: 2),
                            Text('${at.month}/${at.day}', style: T.caption()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
