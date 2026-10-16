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
          const Icon(
            Icons.fitness_center,
            size: Sz.iconDense,
            color: C.textSecondary,
          ),
          const SizedBox(width: S.sm),
          Expanded(child: Text(line, style: T.caption())),
        ],
      ),
    );
  }
}

/// 分享用的成果卡 —— 品牌深藍底、金色強調，一眼看得出「這場練得怎麼樣」。
///
/// 底色固定是品牌深藍，不跟著淺色／深色主題換：它是要被分享出去的一張卡片，
/// 在誰的畫面上都該長得一樣。顏色一律取語意色票，不直接寫色碼。
class WorkoutCardView extends StatelessWidget {
  final WorkoutCard card;
  const WorkoutCardView({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final pct = card.completionPercent;
    final gold = C.actionPrimary;
    final soft = C.textOnDark.withValues(alpha: 0.72);
    final tileBg = C.textOnDark.withValues(alpha: 0.10);
    return Container(
      key: const ValueKey('workout-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(S.base),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [C.accentDeep, Color.lerp(C.accentDeep, Colors.black, 0.45)!],
        ),
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 品牌列：左邊品牌，右邊（有升階時）金色的升階徽章。
          // 用 Wrap：窄螢幕上放不下就讓徽章換到下一行，不爆版。
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: S.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fitness_center, size: Sz.iconDense, color: gold),
                  const SizedBox(width: S.xs),
                  Text('健金術', style: T.caption(color: gold)),
                ],
              ),
              if (card.rankedUp)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: S.sm,
                    vertical: S.xs,
                  ),
                  decoration: BoxDecoration(
                    color: gold,
                    borderRadius: BorderRadius.circular(R.child),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.trending_up_rounded,
                        size: Sz.iconDense,
                        color: C.textOnAccent,
                      ),
                      const SizedBox(width: S.xs),
                      Text(
                        '階級提升　${card.rankFrom} → ${card.rankTo} 階',
                        style: T.caption(color: C.textOnAccent),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.md),
          Text(card.planName, style: T.h3(color: C.textOnDark)),
          const SizedBox(height: S.md),
          // 完成度：一條金色的進度條，下面一行字。
          ClipRRect(
            borderRadius: BorderRadius.circular(R.child),
            child: LinearProgressIndicator(
              value: card.plannedSets == 0
                  ? 1
                  : (card.doneSets / card.plannedSets).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: C.textOnDark.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(gold),
            ),
          ),
          const SizedBox(height: S.xs),
          Text(
            pct == null
                ? '完成 ${card.doneSets} 組'
                : '完成 ${card.doneSets} / ${card.plannedSets} 組（$pct%）',
            style: T.caption(color: soft),
          ),
          const SizedBox(height: S.md),
          // 三個數字磚：總重量、訓練時間、連續訓練天數。
          Row(
            children: [
              _StatTile(
                label: '總重量',
                value: '${card.volumeKg.round()}',
                unit: 'kg',
                bg: tileBg,
              ),
              if (card.durationMinutes > 0) ...[
                const SizedBox(width: S.sm),
                _StatTile(
                  label: '訓練時間',
                  value: '${card.durationMinutes}',
                  unit: '分鐘',
                  bg: tileBg,
                ),
              ],
              if (card.streakDays > 0) ...[
                const SizedBox(width: S.sm),
                _StatTile(
                  label: '連續訓練',
                  value: '${card.streakDays}',
                  unit: '天',
                  bg: tileBg,
                ),
              ],
            ],
          ),
          if (card.exercises.isNotEmpty) ...[
            const SizedBox(height: S.md),
            Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                for (final e in card.exercises)
                  _Chip(
                    '${e.name} × ${e.sets}',
                    bg: tileBg,
                    color: C.textOnDark,
                  ),
              ],
            ),
          ],
          if (card.abilityGains.isNotEmpty) ...[
            const SizedBox(height: S.md),
            Row(
              children: [
                Text('能力值', style: T.caption(color: soft)),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Wrap(
                    spacing: S.sm,
                    runSpacing: S.sm,
                    children: [
                      for (final d in Dim.values)
                        if (card.abilityGains[d] != null)
                          _Chip(
                            '${dimNames[d]} +${card.abilityGains[d]}',
                            bg: gold.withValues(alpha: 0.22),
                            color: gold,
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (card.achievements.isNotEmpty) ...[
            const SizedBox(height: S.md),
            Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: Sz.iconDense,
                  color: gold,
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text(
                    '解鎖　${card.achievements.join('、')}',
                    style: T.caption(color: C.textOnDark),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color bg;
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.child),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: T.caption(color: C.textOnDark.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: S.xs),
          // 窄螢幕上數字磚只有 90 多像素寬，數字長（例如 12345 kg）就縮小，不爆版。
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ValueUnit(
              value: value,
              unit: unit,
              style: T.numberM(color: C.textOnDark),
              unitStyle:
                  T.caption(color: C.textOnDark.withValues(alpha: 0.72)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color color;
  const _Chip(this.text, {required this.bg, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(R.child),
    ),
    child: Text(text, style: T.caption(color: color)),
  );
}
