import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../domain/ability.dart';
import '../domain/rank.dart';
import '../state/app_state.dart';
import 'train/plan_detail_screen.dart';
import '../widgets/common.dart';
import '../widgets/radar_chart.dart';
import 'daily/mailbox_screen.dart';
import 'daily/makeup_screen.dart';
import 'leaderboard_screen.dart';
import 'radar_screen.dart';
import 'train/tasks_screen.dart';

/// 首頁 —— 五格著陸頁之一。彙整今天要做的事。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final rp = rankProgressOf(s.totalExp);
    final claimable = s.dailyTasks.where((t) => t.done && !t.claimed).length;
    // 今天要練的那一份：沿用推薦邏輯的第一順位（官方課表）。
    // 今天要練的那一份：取解得開的第一份官方課表。
    final todayPlan = s.currentPlan ??
        s.platformPlans
            .firstWhere(s.planUnlocked, orElse: () => s.platformPlans.first);

    return ListView(
      // 【必須】捲動區底部預留 50px（R-34）
      padding: const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        // --- 身分列 ---
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 中文名與英文名並排。字級放大時英文名先截斷 ——
              // 375 寬 ＋ 1.3 倍字級剛好放不下，而截掉的是副標不是主標。
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('健金術', style: T.h2()),
                  const SizedBox(width: S.sm),
                  Flexible(
                    child: Text(
                      'ALCHEMY WORKOUT',
                      style: T.caption(color: C.actionPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.base),
              Row(
                children: [
                  Expanded(
                    child: StatField(
                        label: '階級', value: '${s.rank}', unit: '/ 99'),
                  ),
                  Expanded(
                    child: StatField(
                        label: '連續訓練',
                        value: '${s.trainingStreakDays}',
                        unit: '天'),
                  ),
                  Expanded(
                    child: StatField(label: '金幣', value: '${s.coins}'),
                  ),
                ],
              ),
              const SizedBox(height: S.base),
              AppProgress(
                value: rp.ratio,
                label: rp.isMax ? '已滿等' : '距 ${rp.rank + 1} 階',
                trailingLabel: rp.isMax ? '滿等' : '還差 ${rp.toNext}',
              ),
            ],
          ),
        ),

        // --- 今日簽到 ---
        const SectionTitle('今天'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    s.checkedInToday
                        ? Icons.check_circle
                        : Icons.event_available_outlined,
                    size: Sz.iconDefault,
                    color: s.checkedInToday ? C.statusSuccess : C.textSecondary,
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.checkedInToday ? '今日已簽到' : '今天還沒簽到',
                            style: T.body(weight: FontWeight.w600)),
                        Text('連續 ${s.checkInStreak} 天　累計 ${s.checkInTotal} 天',
                            style: T.caption()),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.base),
              AppButton(
                label: s.checkedInToday ? '已簽到' : '簽到　經驗值 10 ＋ 金幣 10',
                onPressed: s.checkedInToday ? null : s.checkIn,
              ),
            ],
          ),
        ),

        // --- 今天的訓練 ---
        //
        // 首頁的主 CTA 是「開始訓練」，不是簽到 —— 這個 App 的目的是讓人去練，
        // 把唯一的訓練入口藏在另一個分頁，等於每天都要多繞一次。
        const SectionTitle('今天的訓練'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(todayPlan.name, style: T.h3()),
              const SizedBox(height: S.xs),
              Text(
                '${todayPlan.exercises.length} 個動作　·　'
                '${todayPlan.totalSets} 組',
                style: T.caption(),
              ),
              const SizedBox(height: S.base),
              AppButton(
                label: '開始訓練',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => PlanDetailScreen(plan: todayPlan)),
                ),
              ),
            ],
          ),
        ),

        // --- 每日任務 ---
        const SizedBox(height: S.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < s.dailyTasks.length; i++)
                _TaskRow(
                  task: s.dailyTasks[i],
                  last: i == s.dailyTasks.length - 1,
                ),
            ],
          ),
        ),
        if (claimable > 0) ...[
          const SizedBox(height: S.md),
          AppButton(
            label: '領取每日任務獎勵（$claimable）',
            onPressed: s.claimAllTasks,
          ),
        ],

        // --- 快速入口 ---
        const SectionTitle('快速入口'),
        ListGroup(rows: [
          ListRow(
            title: '補簽',
            subtitle: '補簽券 ${s.makeupTickets} 張',
            chevron: true,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MakeupScreen())),
          ),
          ListRow(
            title: '獎勵信箱',
            subtitle: '${s.unclaimedMail} 筆未領取',
            trailing:
                s.unclaimedMail > 0 ? CountBadge(s.unclaimedMail) : null,
            chevron: true,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MailboxScreen())),
          ),
          ListRow(
            title: '新手 / 回歸任務',
            subtitle: s.returnTaskAssigned ? '有一項回歸任務待完成' : '無進行中的任務',
            chevron: true,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TasksScreen())),
          ),
        ]),

        // --- 排行榜 ---
        //
        // `[QA-02j]`：原本只掛在「我的」選單的第 11 項，等於沒有入口。
        //
        // 卡片上的**分數是真的**（本機就算得出來），需要後端的只有「名次」。
        // 所以即使排行榜本身還等著 `[BE-07]`，這張卡仍然說得出真話 ——
        // 點進去才會看到「尚未開放」，而那也是實話。
        const SectionTitle('排行榜', trailing: '組別依階級，每 10 階一組'),
        AppCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: C.bgPage,
              appBar: AppBar(title: Text('個人排行榜', style: T.h3())),
              body: const LeaderboardScreen(),
            ),
          )),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatField(
                        label: '本週分數', value: '${s.weeklyScore}'),
                  ),
                  Expanded(
                    child: StatField(
                        label: '本月分數', value: '${s.monthlyScore}'),
                  ),
                ],
              ),
              const SizedBox(height: S.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('查看名次與本期獎勵', style: T.caption()),
                  const SizedBox(width: S.xs),
                  const Icon(Icons.chevron_right,
                      size: 14, color: C.textSecondary),
                ],
              ),
            ],
          ),
        ),

        // --- 能力值摘要 ---
        const SectionTitle('六維能力值'),
        AppCard(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: C.bgPage,
              appBar: AppBar(title: Text('六維能力值', style: T.h3())),
              body: const RadarScreen(),
            ),
          )),
          child: Column(
            children: [
              // 綜合能力等級放在圖表上方，不放中央（§8.12）
              Text('綜合能力等級', style: T.caption()),
              const SizedBox(height: S.xs),
              Text(overallGrade(s.points), style: T.numberM()),
              const SizedBox(height: S.sm),
              Center(child: RadarChart(points: s.points)),
              const SizedBox(height: S.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('查看各維明細與耐力值', style: T.caption()),
                  const SizedBox(width: S.xs),
                  const Icon(Icons.chevron_right,
                      size: 14, color: C.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  final dynamic task;
  final bool last;
  const _TaskRow({required this.task, required this.last});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListRow(
      title: task.name as String,
      subtitle: '${task.progress} / ${task.target}',
      showDivider: !last,
      trailing: task.claimed as bool
          ? const TagBadge('已領取')
          : (task.done as bool)
              ? GestureDetector(
                  onTap: () => s.claimTask(task),
                  child: const TagBadge('領取',
                      borderColor: C.actionPrimary, fill: C.actionPrimary),
                )
              : SizedBox(
                  width: 72,
                  child: BareProgress(
                    value: (task.progress as int) / (task.target as int),
                  ),
                ),
    );
  }
}
