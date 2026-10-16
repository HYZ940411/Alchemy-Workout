import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/community.dart';
import '../../domain/workout_card.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 貼文上的訓練成果。
///
/// 新貼文畫完整的成果卡（完成度、時間、動作、階級提升…）；
/// 舊貼文只有一行摘要，照舊畫那一行 —— 雲端既有的貼文不會壞掉。
class PostWorkoutAttachment extends StatelessWidget {
  final Post post;
  const PostWorkoutAttachment({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final card = post.workoutCard;
    if (card != null) return WorkoutCardView(card: card);
    final line = post.attachedWorkout;
    if (line == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: C.bgPage,
        borderRadius: BorderRadius.circular(R.child),
      ),
      child: Row(
        children: [
          const Icon(Icons.fitness_center,
              size: Sz.iconDense, color: C.textSecondary),
          const SizedBox(width: S.sm),
          Expanded(child: Text(line, style: T.caption())),
        ],
      ),
    );
  }
}

class WorkoutCardView extends StatelessWidget {
  final WorkoutCard card;
  const WorkoutCardView({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final pct = card.completionPercent;
    final stats = <String>[
      '總重量 ${card.volumeKg.round()} kg',
      pct == null
          ? '完成 ${card.doneSets} 組'
          : '完成 ${card.doneSets} / ${card.plannedSets} 組（$pct%）',
      if (card.durationMinutes > 0) '訓練 ${card.durationMinutes} 分鐘',
      if (card.streakDays > 0) '連續訓練 ${card.streakDays} 天',
    ];
    return Container(
      key: const ValueKey('workout-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: C.bgPage,
        borderRadius: BorderRadius.circular(R.child),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center,
                  size: Sz.iconDense, color: C.textSecondary),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text(card.planName,
                    style: T.body(weight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          Wrap(
            spacing: S.md,
            runSpacing: S.xs,
            children: [for (final s in stats) Text(s, style: T.caption())],
          ),
          if (card.exercises.isNotEmpty) ...[
            const SizedBox(height: S.sm),
            Text(
              [for (final e in card.exercises) '${e.name} × ${e.sets}'].join('　'),
              style: T.caption(),
            ),
          ],
          if (card.rankedUp) ...[
            const SizedBox(height: S.sm),
            Row(
              children: [
                const Icon(Icons.trending_up_rounded,
                    size: Sz.iconDense, color: C.accentDeep),
                const SizedBox(width: S.xs),
                Text('階級提升  ${card.rankFrom} → ${card.rankTo} 階',
                    style: T.caption(color: C.accentDeep)),
              ],
            ),
          ],
          if (card.abilityGains.isNotEmpty) ...[
            const SizedBox(height: S.xs),
            Text(
              '能力值  ${[
                for (final d in Dim.values)
                  if (card.abilityGains[d] != null)
                    '${dimNames[d]} +${card.abilityGains[d]}'
              ].join('　')}',
              style: T.caption(),
            ),
          ],
          if (card.achievements.isNotEmpty) ...[
            const SizedBox(height: S.xs),
            Text('解鎖  ${card.achievements.join('、')}', style: T.caption()),
          ],
        ],
      ),
    );
  }
}
