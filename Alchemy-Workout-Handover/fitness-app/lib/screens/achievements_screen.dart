import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../mock/mock_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Read Model：成就頁 —— 依 9 類成就分組呈現。
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  /// 互動成就為 4 種 × 9 門檻，故此處是 12 個區塊而非 9 個 ——
  /// 「9 類」講的是成就的類別，不是畫面上的區塊數。
  static const _order = [
    '連簽', '累簽', '連續訓練', '累積訓練', '新手任務',
    ...kInteractionKinds,
    '粉絲', '能力值', '階級',
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final claimable = s.achievements.where((a) => a.unlocked && !a.claimed).length;
    final unlocked = s.achievements.where((a) => a.unlocked).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
      children: [
        Panel(
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '已解鎖',
                  value: '$unlocked',
                  unit: '/ ${s.achievements.length}',
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '可領取',
                  value: '$claimable',
                  valueColor: claimable > 0 ? AppColors.accent : null,
                ),
              ),
              SizedBox(
                width: 108,
                child: AppButton(
  label: '一鍵領取',
  onPressed: claimable == 0 ? null : s.claimAllAchievements,
  kind: BtnKind.primary,
),
              ),
            ],
          ),
        ),
        for (final cat in _order) _CategoryBlock(category: cat, state: s),
      ],
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  final String category;
  final AppState state;
  const _CategoryBlock({required this.category, required this.state});

  @override
  Widget build(BuildContext context) {
    final items = state.achievements.where((a) => a.category == category).toList();
    final progress = state.currentProgressFor(category);
    final next = items.where((a) => !a.unlocked).toList();
    final toNext = next.isEmpty ? null : next.first.threshold - progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          category,
          trailing: toNext == null
              ? '全數解鎖　當前 $progress'
              : '當前 $progress　距下一門檻還差 $toNext',
        ),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final a in items) _AchievementRow(a: a, state: state),
            ],
          ),
        ),
      ],
    );
  }
}

class _AchievementRow extends StatelessWidget {
  final Achievement a;
  final AppState state;
  const _AchievementRow({required this.a, required this.state});

  @override
  Widget build(BuildContext context) {
    final locked = !a.unlocked;
    return Opacity(
      opacity: locked ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(
              locked ? Icons.lock_outline : Icons.emoji_events_rounded,
              size: 18,
              color: locked ? C.textSecondary : C.accentDeep,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    // 階級成就不給經驗值 —— 寫「經驗值 0」看起來像壞掉了。
                    a.rewardExp == 0
                        ? '金幣 ${a.rewardCoins}'
                        : '金幣 ${a.rewardCoins} ＋ 經驗值 ${a.rewardExp}',
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (!locked)
              a.claimed
                  ? const Pill('已領取', color: AppColors.textFaint)
                  : GestureDetector(
                      onTap: () => state.claimAchievement(a),
                      child: const Pill('領取',
                          color: AppColors.accent, filled: true),
                    ),
          ],
        ),
      ),
    );
  }
}
