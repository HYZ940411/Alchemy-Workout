import 'package:flutter/material.dart';

import '../domain/ability.dart';
import '../domain/rank.dart';
import '../domain/rewards.dart';
import '../domain/novice_wrapup.dart';
import '../domain/platform_config.dart';
import '../state/app_state.dart';
import 'train/rate_experience_screen.dart';
import '../design/tokens.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Read Model：訓練結算頁
/// 版面分為固定核心與條件式亮點兩層。
class SettlementScreen extends StatelessWidget {
  const SettlementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final r = s.lastSettlement;
    if (r == null) return const Scaffold(body: SizedBox.shrink());

    final rp = rankProgressOf(s.totalExp);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text('訓練結算',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '分享訓練成果',
            onPressed: () => _share(context, s, r),
            icon: const Icon(Icons.ios_share_rounded, size: 20),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 50),
        children: [
          // ---------- 主角：六維能力值增量 ----------
          const SectionLabel('六維能力值'),
          _AbilityGains(result: r),

          // ---------- 核心區塊 ----------
          const SectionLabel('實績摘要'),
          Panel(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: '總訓練量',
                        value: s.volumeDisplay(r.volume).$1,
                        unit: s.volumeDisplay(r.volume).$2,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: '訓練時長',
                        value: '${r.duration.inMinutes}',
                        unit: '分',
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: '已完成組數',
                        value: '${r.doneSets}',
                        unit: '/ ${r.plannedSets}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: '消耗大卡（估計值）',
                        value: '約 ${r.calories}',
                        unit: '大卡',
                        valueColor: C.accentDeep,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: '連續訓練天數',
                        value: '${r.streakDays}',
                        unit: '天',
                        valueColor: C.accentDeep,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SectionLabel('經驗值與獎勵'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('階級 ',
                        style: T.caption()),
                    Text('${rp.rank}',
                        // 階級是數值 —— 用數值樣式才有等寬對齊。
                        style: T.numberS()),
                    const Spacer(),
                    if (r.rewards.exp > 0)
                      Text('經驗值 +${r.rewards.exp}',
                          style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800))
                    else
                      Text('經驗值當日已發放', style: T.caption()),
                  ],
                ),
                const SizedBox(height: 10),
                ProgressBar(value: rp.ratio),
                const SizedBox(height: 6),
                Text(
                  rp.isMax ? '已滿等' : '距 ${rp.rank + 1} 階還差 ${rp.toNext} 經驗值',
                  style: T.caption(),
                ),
                const Divider(height: 28, color: AppColors.line),
                _RewardRow(
                  icon: Icons.monetization_on_outlined,
                  color: AppColors.warn,
                  label: '金幣獎勵',
                  value: '+${r.rewards.coins}',
                  // 每日只發一次、以當日最高完成度為準。今天已經拿過的部分不會再發，
                  // 只補差額 —— 沒說清楚的話，同一天第二場看到 +0 會像是壞掉了。
                  detail: r.rewards.coinsCapped
                      ? '本場應得 ${r.rewards.coinsEntitled}，今日已發 '
                          '${r.rewards.coinsEntitled - r.rewards.coins}，'
                          '${r.rewards.coins == 0 ? '訓練獎勵每日只發一次' : '補發差額'}'
                      : '基底 $kTrainingCoinBase'
                          ' × 完成度 ${(r.rewards.completion * 100).round()}%'
                          '${r.rewards.bonusRate > 0 ? ' × 連續加成 ${(r.rewards.bonusRate * 100).round()}%' : ''}',
                ),
                const SizedBox(height: 14),
                if (r.rewards.leaderboardScore != null)
                  _RewardRow(
                    icon: Icons.leaderboard_outlined,
                    color: AppColors.cool,
                    label: '個人排行榜分數',
                    value: '+${r.rewards.leaderboardScore}',
                    detail: r.rewards.scoreCapped
                        ? '本場應得 ${r.rewards.leaderboardScoreEntitled}，今日已計 '
                            '${r.rewards.leaderboardScoreEntitled! - r.rewards.leaderboardScore!}，'
                            '${r.rewards.leaderboardScore == 0 ? '每日取最高一次' : '補發差額'}'
                        : '基準分 $kLeaderboardBase'
                            ' × 完成度 ${(r.rewards.completion * 100).round()}%'
                            ' × 課表來源 ${((planSourceFactor(r.plan.source) ?? 0) * 100).round()}%',
                  )
                else
                  const _RewardRow(
                    icon: Icons.leaderboard_outlined,
                    color: AppColors.textFaint,
                    label: '個人排行榜分數',
                    value: '—',
                    detail: '空白課表不計入個人排行榜分數',
                  ),
              ],
            ),
          ),

          // ---------- 亮點區塊：僅於發生時呈現 ----------
          if (r.rankAfter > r.rankBefore) ...[
            const SectionLabel('亮點'),
            _Highlight(
              icon: Icons.military_tech_outlined,
              color: AppColors.accent,
              title: '階級提升！',
              sub: '${r.rankBefore} 階 → ${r.rankAfter} 階',
            ),
          ],
          if (r.newlyUnlocked.isNotEmpty) ...[
            if (r.rankAfter <= r.rankBefore) const SectionLabel('亮點'),
            for (final a in r.newlyUnlocked.take(4))
              _Highlight(
                icon: Icons.emoji_events_outlined,
                color: C.accentDeep,
                title: '成就解鎖：${a.name}',
                sub: '${a.category}類　獎勵 金幣 ${a.rewardCoins} ＋ 經驗值 ${a.rewardExp}',
              ),
          ],

          // 評分訓練體驗。**可跳過，不阻擋獎勵發放** ——
          // 被擋住去路的人會隨手點一個把它關掉，拿到的是筆數不是品質訊號。
          // 每人每份計畫終身一次（受詢問頻率因此降為每換一份計畫一次），可修改。
          if (s.ratingFor(RatingTarget.trainingPlan, r.plan.id) == null) ...[
            const SizedBox(height: 20),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('「${r.plan.name}」做起來如何？',
                      style: T.body(weight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  // 多行段落用 Body —— 規格 §2.2 明訂 Caption 僅供單行。
                  Text('這份評分是給平台改課表用的，不連動任何人的聲望或獎勵。可以跳過。',
                      style: T.body(color: C.textSecondary)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: '評分這份課表',
                      kind: BtnKind.secondary,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RateExperienceScreen(
                            target: RatingTarget.trainingPlan,
                            targetId: r.plan.id,
                            targetName: r.plan.name,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 26),
          ButtonRow(
            left: AppButton(
              label: '分享成果',
              kind: BtnKind.secondary,
              onPressed: () => _share(context, s, r),
            ),
            right: AppButton(
              label: '完成',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 發文者已分享訓練成果 —— 真的產生一則帶訓練成果的貼文，
/// 不是一個 toast。分享獎勵每日上限 3 次，超過仍可分享，只是不再發經驗值。
Future<void> _share(
    BuildContext context, AppState s, SettlementResult r) async {
  final ctrl = TextEditingController();
  final ok = await showAppDialog(
    context,
    title: '分享這次訓練',
    size: DialogSize.medium,
    confirmLabel: '發布',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '會附上「${r.plan.name} · ${r.volume.round()} kg · ${r.doneSets} 組」。'
          '今日分享獎勵已發 ${s.interactionsToday('Share')} / '
          '${platformConfig.i('reward', 'capShare')} 次 ——'
          '超過上限照樣分享得出去，只是不再發經驗值。',
          style: T.caption(),
        ),
        const SizedBox(height: S.md),
        TextField(
          controller: ctrl,
          style: T.body(),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: '想說點什麼？',
            hintStyle: T.body(color: C.textDisabled),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.control),
            ),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final result = s.shareWorkout(r, ctrl.text);
  ctrl.dispose();
  if (result == null) {
    showToast(context, '內容有明顯違規，已擋下');
    return;
  }
  showToast(
      context,
      result.exp > 0
          ? '已分享至動態牆，經驗值 +${result.exp}'
          : '已分享至動態牆。今日分享獎勵已達上限。');
}

class _AbilityGains extends StatelessWidget {
  final SettlementResult result;
  const _AbilityGains({required this.result});

  @override
  Widget build(BuildContext context) {
    final gained = Dim.values.where((d) => (result.gains[d] ?? 0) > 0).toList();
    final rest = Dim.values.where((d) => (result.gains[d] ?? 0) == 0).toList();

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gained.isEmpty) ...[
            Text(
              '本次訓練未推進任何維度 —— 點數只在超越自身紀錄時上升。',
              style: T.body(color: C.textSecondary),
            ),
            // **講出差多少**。只說「未推進」，畫面看起來就是沒反應，
            // 使用者無從判斷自己是差一點還是差很遠。
            for (final d in Dim.values)
              if (result.measured[d] != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(dimNames[d]!,
                        style: T.body(weight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Text(
                      '本次實測 ${result.measured[d]}　·　目前 ${result.pointsAfter[d]} 點',
                      // 等寬數字由 T 統一提供，不必每處自己指定。
                      style: T.caption(),
                    ),
                  ],
                ),
              ],
          ],
          for (final d in gained) _GainRow(dim: d, result: result, big: true),
          if (rest.isNotEmpty && gained.isNotEmpty) ...[
            const Divider(height: 26, color: AppColors.line),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in rest)
                  Pill(
                    '${dimNames[d]} ${majorGradeOf(result.pointsAfter[d]!)}',
                    color: AppColors.textFaint,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GainRow extends StatelessWidget {
  final Dim dim;
  final SettlementResult result;
  final bool big;
  const _GainRow({required this.dim, required this.result, this.big = false});

  @override
  Widget build(BuildContext context) {
    final after = result.pointsAfter[dim]!;
    final delta = result.gains[dim] ?? 0;
    final np = nodeProgressOf(after);
    final node = nodeOf(after);
    // 顏色依等級，不依部位
    final color = C.gradeFill(node.major);
    final within = node.upper > node.lower
        ? (after - node.lower) / (node.upper - node.lower)
        : 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 4,
                height: 26,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                dimNames[dim]!,
                style: T.body(weight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Text(
                '+$delta',
                // 增益點數是這一列的主角 —— 用數值樣式，大小依是否為
                // 本次最大增益切換。等寬與行高由 T 統一。
                style: big ? T.numberL(color: color) : T.numberM(color: color),
              ),
              const Spacer(),
              Text(
                '$after 點',
                style: T.caption(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(value: within, color: color),
          const SizedBox(height: 6),
          // 呈現格式：主階 ＋ 本節點累積 ＋ 距下一節點
          Text(
            np.display,
            style: T.caption(),
          ),
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String detail;
  const _RewardRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: T.body(weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detail, style: T.caption()),
              ],
            ),
          ),
          Text(
            value,
            // 獎勵數額 —— 數值樣式。
            style: T.numberS(color: color),
          ),
        ],
      );
}

class _Highlight extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  const _Highlight({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          color: color.withValues(alpha: 0.10),
          border: color.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: T.body(color: color, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: T.caption()),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
