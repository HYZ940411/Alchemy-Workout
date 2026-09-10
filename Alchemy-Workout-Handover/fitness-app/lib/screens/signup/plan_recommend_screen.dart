import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/models.dart';
import '../../domain/rewards.dart';
import '../../domain/registration.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 訓練計畫推薦頁（〈註冊流程〉：訓練計畫已推薦）
///
/// 比對維度三項：器材 → 經驗 → 常見目標，依「違反後果的嚴重程度」排序；
/// 動機類不參與比對。同分者取建立時間最早，不隨機取一 ——
/// 同樣條件的兩個使用者要拿到同一份計畫，否則無法重現與除錯。
///
/// **推薦為單向指派，使用者不可拒絕**：故本頁只有一顆「開始使用」，
/// 沒有「稍後再選」。其餘計畫列在下方僅供預覽，日後於課表選擇頁可自由更換。
class PlanRecommendPane extends StatelessWidget {
  final SignUpDraft draft;
  final VoidCallback onStart;
  const PlanRecommendPane({
    super.key,
    required this.draft,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // 空白課表不是「推薦」的候選 —— 它是自由訓練的入口，不對應任何條件。
    final pool = s.platformPlans
        .where((p) => p.source == PlanSource.official)
        .toList();
    final picked = recommendPlan<WorkoutPlan>(
      pool,
      equipment: draft.equipment.isEmpty ? null : draft.equipment.first,
      experience: draft.experience,
      commonGoal: draft.commonGoal,
      tierOf: (p) => p.equipmentTier,
      experienceOf: (p) => p.suitableExperience,
      goalsOf: (p) => p.suitableGoals,
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                S.base, S.base, S.base, S.scrollBottom),
            children: [
              Text('為你推薦', style: T.h1()),
              const SizedBox(height: S.sm),
              Text('依你的器材、經驗與目標挑選。之後隨時可以換。',
                  style: T.body(color: C.textSecondary)),
              const SizedBox(height: S.lg),

              if (picked == null)
                const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '目前沒有可推薦的計畫',
                  message: '平台計畫都還沒設定適用條件。你仍可到課表選擇頁自行挑一份。',
                )
              else ...[
                _PlanCard(plan: picked, recommended: true, draft: draft),
                if (pool.length > 1) ...[
                  const SectionTitle('其他計畫', trailing: '之後可自由更換'),
                  for (final p in pool.where((x) => x.id != picked.id))
                    _PlanCard(plan: p, recommended: false, draft: draft),
                ],
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.base),
          child: AppButton(
            label: picked == null ? '先去課表選擇頁' : '開始使用',
            onPressed: onStart,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final WorkoutPlan plan;
  final bool recommended;
  final SignUpDraft draft;
  const _PlanCard({
    required this.plan,
    required this.recommended,
    required this.draft,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: AppCard(
          borderColor: recommended ? C.actionOutline : C.lineDivider,
          borderWidth: recommended ? 2 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(plan.name, style: T.h3())),
                  if (recommended)
                    TagBadge('最推薦',
                        borderColor: C.actionOutline, fill: C.actionOutline),
                ],
              ),
              const SizedBox(height: S.sm),
              Text(
                '${plan.exercises.length} 動作 · ${plan.totalSets} 組　·　'
                '器材：${plan.equipmentTier}',
                style: T.caption(),
              ),
              const SizedBox(height: S.md),
              Wrap(
                spacing: S.sm,
                runSpacing: S.sm,
                children: [
                  for (final e in plan.suitableExperience)
                    TagBadge(
                      e,
                      // 符合的條件加深藍框，讓「為什麼推這份」看得出來。
                      borderColor: e == draft.experience
                          ? C.actionOutline
                          : C.lineDivider,
                    ),
                  for (final g in plan.suitableGoals)
                    TagBadge(
                      g,
                      borderColor: g == draft.commonGoal
                          ? C.actionOutline
                          : C.lineDivider,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}
