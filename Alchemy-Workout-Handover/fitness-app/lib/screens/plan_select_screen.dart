import '../domain/clock.dart';
import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/rewards.dart';
import '../design/skeleton.dart';
import '../state/app_state.dart';
import '../widgets/load_boundary.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'train/plan_detail_screen.dart';

/// Read Model：課表選擇頁
/// 支撐的 Command：選擇訓練課表、開始訓練、確認使用新訓練強度 / 拒絕調整
class PlanSelectScreen extends StatelessWidget {
  const PlanSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // B 卡片列表型骨架：首屏約兩張課表卡。
    return LoadBoundary(
      id: 'plan-select',
      kind: SkeletonKind.cardListB,
      rows: 2,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          _Header(rank: s.rank, streak: s.trainingStreakDays, coins: s.coins),
          const SectionLabel('選擇今天的課表'),
          for (final p in s.platformPlans) _PlanCard(plan: p, userRank: s.rank),
          // 自訂訓練與訓練計畫的課表內容結構完全一致，故同樣可選用於訓練。
          // 已儲存（未啟用）者不在此列 —— 要能練得先發布。
          if (s.selectableCustomPlans.isNotEmpty) ...[
            const SectionLabel('自訂訓練', trailing: '自己發布的與他人開放的'),
            for (final c in s.selectableCustomPlans)
              _PlanCard(
                plan: c.toWorkoutPlan(),
                userRank: s.rank,
                author: c.isMine ? null : c.author,
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int rank;
  final int streak;
  final int coins;
  const _Header({
    required this.rank,
    required this.streak,
    required this.coins,
  });

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '健金術',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.accent,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'ALCHEMY WORKOUT',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const Divider(height: 20, color: AppColors.line),
        Row(
          children: [
            Expanded(
              child: StatTile(label: '階級', value: '$rank', unit: '/ 99'),
            ),
            Expanded(
              child: StatTile(
                label: '連續訓練',
                value: '$streak',
                unit: '天',
                valueColor: AppColors.gold,
              ),
            ),
            Expanded(
              child: StatTile(
                label: '金幣',
                value: '$coins',
                valueColor: C.accentDeep,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PlanCard extends StatelessWidget {
  final WorkoutPlan plan;
  final int userRank;

  /// 他人的自訂訓練才有值 —— 課表選擇頁要講得出這份是誰做的。
  final String? author;
  const _PlanCard({required this.plan, required this.userRank, this.author});

  @override
  Widget build(BuildContext context) {
    // 三種解鎖方式為 OR 關係 —— 只看階級會讓已付金幣解鎖的計畫仍顯示為鎖住。
    final s = AppScope.of(context);
    final locked = !s.planUnlocked(plan);
    final sets = plan.totalSets;
    final srcFactor = planSourceFactor(plan.source);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: Panel(
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(R.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.card),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PlanDetailScreen(plan: plan)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(S.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(plan.name, style: T.h3())),
                        if (plan.hasOptimizationSuggestion)
                          const Pill('新的優化建議', color: AppColors.cool),
                        const SizedBox(width: S.xs),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.textFaint,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(
                          planSourceNames[plan.source]!,
                          color: AppColors.textDim,
                        ),
                        if (author != null)
                          Pill('由 $author 建立', color: AppColors.textDim),
                        if (plan.source != PlanSource.blank)
                          Pill(
                            '${plan.exercises.length} 動作 · $sets 組',
                            color: AppColors.textDim,
                          ),
                        Pill(
                          '器材：${plan.equipmentTier}',
                          color: AppColors.textDim,
                        ),
                        // 適用經驗與適用目標（`[QA-02l]`）。這兩欄原本是空集合，
                        // 而 recommendPlan 把空集合視為「全部符合」——
                        // 於是每一份課表都宣稱適合所有人，卡片上也無從標示。
                        for (final e in plan.suitableExperience)
                          Pill(e, color: AppColors.textDim),
                        for (final g in plan.suitableGoals)
                          Pill(g, color: AppColors.accentSoft),
                        if (plan.disclaimer != null)
                          const Pill('使用者提供', color: AppColors.textDim),
                        if (srcFactor != null)
                          Pill(
                            '排行係數 ${(srcFactor * 100).round()}%',
                            color: AppColors.accentSoft,
                          )
                        else
                          const Pill('不計入排行榜', color: AppColors.textFaint),
                      ],
                    ),
                    // 來源免責標示。自訂訓練（含已公開者）須呈現 ——
                    // 平台不為使用者做的課表擔保，這句話要在選課表時就看得到，
                    // 不能等到點進詳情頁。
                    if (plan.disclaimer != null) ...[
                      const SizedBox(height: 10),
                      Text(plan.disclaimer!, style: T.caption()),
                    ],
                    // **依訓練歷史推導，不讀課表上的欄位。**
                    // 官方課表是平台目錄，「我上次練它是什麼時候」
                    // 是每個人各自不同的東西。
                    if (s.lastTrainedOf(plan) case final at?) ...[
                      const SizedBox(height: 10),
                      Text(
                        '上次訓練 ${_ago(at)}'
                        '${plan.lastCompletion != null ? '　完成度 ${(plan.lastCompletion! * 100).round()}%' : ''}',
                        style: T.caption(color: C.textDisabled),
                      ),
                    ],
                    if (locked) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: AppColors.textDim,
                          ),
                          const SizedBox(width: 6),
                          // 兩條解鎖路徑一起寫，375 寬放不下一行，須能換行。
                          Expanded(
                            child: Text(
                              plan.unlockCoins == null
                                  ? '解鎖條件：達到 ${plan.requiredRank} 階'
                                  : '解鎖條件：達到 ${plan.requiredRank} 階，'
                                      '或 ${plan.unlockCoins} 金幣提前購買',
                              style: T.caption(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final n = appNow().difference(d).inDays;
    return n == 0 ? '今天' : '$n 天前';
  }
}
