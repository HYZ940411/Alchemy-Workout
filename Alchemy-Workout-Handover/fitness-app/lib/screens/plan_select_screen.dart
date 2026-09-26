import '../domain/clock.dart';
import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/plan_duration.dart';
import '../domain/registration.dart';
import '../domain/rewards.dart';
import '../design/skeleton.dart';
import '../state/app_state.dart';
import '../widgets/load_boundary.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'train/plan_detail_screen.dart';

/// Read Model：課表選擇頁
/// 支撐的 Command：選擇訓練課表、開始訓練、確認使用新訓練強度 / 拒絕調整
class PlanSelectScreen extends StatefulWidget {
  const PlanSelectScreen({super.key});

  @override
  State<PlanSelectScreen> createState() => _PlanSelectScreenState();
}

class _PlanSelectScreenState extends State<PlanSelectScreen> {
  /// 篩選條件。空值＝不限。
  ///
  /// **預設不限，不預先套用使用者自己的問卷答案。** 預先套用會讓他打開
  /// 這一頁就少看到一半的課表，而畫面上沒有任何東西說「有東西被藏起來了」。
  /// 註冊問卷的答案已經在用了 —— 那是訓練計畫推薦的依據。
  String? equipment;
  String? experience;

  /// 器材是**硬約束**：選健身房看得到全部，選居家看得到居家與徒手，
  /// 選徒手只看得到徒手。這個定義來自 `runnablePlanTiers`，
  /// 與訓練計畫推薦共用同一份 —— 不在這裡再寫一次。
  bool _matches(WorkoutPlan p) {
    final runnable = runnablePlanTiers(equipment);
    if (runnable != null && !runnable.contains(p.equipmentTier)) return false;
    // 適用經驗是空集合＝不限，與 recommendPlan 一致。
    if (experience != null &&
        p.suitableExperience.isNotEmpty &&
        !p.suitableExperience.contains(experience)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final plans = s.platformPlans.where(_matches).toList();
    // **篩選要一併作用在自訂訓練上。** 只篩官方課表的話，
    // 選了「徒手」還是會看到一整排要器械的自訂課表。
    final customs =
        s.selectableCustomPlans.where((c) => _matches(c.toWorkoutPlan())).toList();
    final filtered = equipment != null || experience != null;

    // B 卡片列表型骨架：首屏約兩張課表卡。
    return LoadBoundary(
      id: 'plan-select',
      kind: SkeletonKind.cardListB,
      rows: 2,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          _Header(rank: s.rank, streak: s.trainingStreakDays, coins: s.coins),
          _Filters(
            equipment: equipment,
            experience: experience,
            onEquipment: (v) => setState(() => equipment = v),
            onExperience: (v) => setState(() => experience = v),
          ),
          SectionLabel('選擇今天的課表',
              trailing: filtered
                  ? '${plans.length + customs.length} / '
                      '${s.platformPlans.length + s.selectableCustomPlans.length} 份'
                  : null),
          // 篩到沒有東西剩下時要說得出來，不可以只是一片空白 ——
          // 那看起來像課表全部不見了。
          if (plans.isEmpty && customs.isEmpty)
            AppCard(
              child: EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: '沒有符合的課表',
                message: '目前的條件篩不到任何一份。放寬器材或經驗再看看。',
                action: AppButton(
                  label: '清除篩選',
                  onPressed: () => setState(() {
                    equipment = null;
                    experience = null;
                  }),
                ),
              ),
            ),
          for (final p in plans) _PlanCard(plan: p, userRank: s.rank),
          // 自訂訓練與訓練計畫的課表內容結構完全一致，故同樣可選用於訓練。
          // 已儲存（未啟用）者不在此列 —— 要能練得先發布。
          if (customs.isNotEmpty) ...[
            const SectionLabel('自訂訓練', trailing: '自己發布的與他人開放的'),
            for (final c in customs)
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

/// 器材與經驗兩排篩選鍵。
///
/// 器材的值域字串很長（「居家器材（彈力繩、小啞鈴等）」），一排放不下三個，
/// 所以鍵面用短標、送出去的是完整值域字串 —— 值域不因為畫面排版而變形。
class _Filters extends StatelessWidget {
  final String? equipment;
  final String? experience;
  final ValueChanged<String?> onEquipment;
  final ValueChanged<String?> onExperience;
  const _Filters({
    required this.equipment,
    required this.experience,
    required this.onEquipment,
    required this.onExperience,
  });

  /// 鍵面短標 → 註冊問卷的值域字串。
  static final _equipmentShort = {
    for (final v in kEquipmentTiers) v.split('（').first: v,
  };
  static final _experienceShort = {
    for (final v in kExperience) v.split('（').first: v,
  };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: S.md),
        child: Panel(
          padding: const EdgeInsets.all(S.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('器材', _equipmentShort, equipment, onEquipment),
              const SizedBox(height: S.md),
              _row('經驗', _experienceShort, experience, onExperience),
            ],
          ),
        ),
      );

  Widget _row(String label, Map<String, String> options, String? picked,
          ValueChanged<String?> onPick) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(label, style: T.caption()),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                _chip('不限', picked == null, () => onPick(null)),
                for (final e in options.entries)
                  _chip(e.key, picked == e.value, () => onPick(e.value)),
              ],
            ),
          ),
        ],
      );

  Widget _chip(String text, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: on ? C.accentDeep : C.bgPage,
            borderRadius: BorderRadius.circular(R.control),
            border: Border.all(color: on ? C.accentDeep : C.lineDivider),
          ),
          child: Text(
            text,
            style: T.caption(
              color: on ? C.onFill(C.accentDeep) : C.textSecondary,
            ).copyWith(fontWeight: on ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      );
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
                        // 預估訓練時長 —— 挑課表時最常先看的東西之一，
                        // 而在此之前整個 App 只有課表詳情頁有，
                        // 且顯示的是 CSV 那一欄格式不一的原文。
                        if (s.estimatedDurationOf(plan) case final d?)
                          Pill(planDurationLabel(d), color: AppColors.cool),
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
                      Builder(builder: (_) {
                        final c = s.lastCompletionOf(plan);
                        return Text(
                          '上次訓練 ${_ago(at)}'
                          '${c == null ? '' : '　完成度 ${(c * 100).round()}%'}',
                          style: T.caption(color: C.textDisabled),
                        );
                      }),
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
