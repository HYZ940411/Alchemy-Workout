import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/rewards.dart';
import '../state/app_state.dart';
import 'daily/periodic_ask.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 兩個 Read Model 各自一個分頁：簽到頁、每日任務清單。
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});
  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  @override
  void initState() {
    super.initState();
    // 每日任務重置由排程觸發；本專案於進入本頁時結算。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).resetDailyTasksIfDue();
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppColors.onAccent,
                unselectedLabelColor: AppColors.textDim,
                labelStyle:
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                tabs: const [Tab(text: '每日簽到'), Tab(text: '每日任務')],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [_CheckInTab(), _DailyTasksTab()],
              ),
            ),
          ],
        ),
      );
}

/// Read Model：簽到頁 —— 僅承載「今天要不要簽」這一個決策。
class _CheckInTab extends StatelessWidget {
  const _CheckInTab();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final done = s.checkedInToday;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
      children: [
        // 兩個週期詢問併入簽到畫面，而非另設打斷點 ——
        // 簽到本即為「打開 App 第一件事」，不需另造一個中斷。
        // 兩者皆可跳過，且都不擋簽到。
        const PeriodicAskCards(),
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
          child: Column(
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.event_available_outlined,
                size: 52,
                color: done ? AppColors.ok : AppColors.accent,
              ),
              const SizedBox(height: 14),
              Text(
                done ? '今日已簽到' : '今天還沒簽到',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                '簽到獎勵：經驗值 10 ＋ 金幣 10',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: AppButton(
  label: done ? '已簽到' : '簽到',
  onPressed: done ? null : s.checkIn,
  kind: BtnKind.primary,
),
              ),
            ],
          ),
        ),
        const SectionLabel('回顧'),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '連續天數',
                  value: '${s.checkInStreak}',
                  unit: '天',
                  valueColor: C.accentDeep,
                ),
              ),
              Expanded(
                child: StatTile(label: '累計天數', value: '${s.checkInTotal}', unit: '天'),
              ),
              Expanded(
                child: StatTile(
                    label: '歷史最長', value: '${s.checkInLongest}', unit: '天'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read Model：每日任務清單 —— 支撐的 Command 僅為「領取每日任務獎勵」。
class _DailyTasksTab extends StatelessWidget {
  const _DailyTasksTab();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final claimable = s.dailyTasks.where((t) => t.done && !t.claimed).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
      children: [
        for (final t in s.dailyTasks) _TaskCard(task: t, state: s),
        const SizedBox(height: 6),
        Panel(
          color: s.allTasksDone
              ? AppColors.accent.withValues(alpha: 0.10)
              : AppColors.surface,
          border: s.allTasksDone ? AppColors.accent : AppColors.line,
          child: Row(
            children: [
              Icon(
                s.allTasksDone ? Icons.stars_rounded : Icons.stars_outlined,
                color: s.allTasksDone ? AppColors.accent : AppColors.textFaint,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('全部完成加碼',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('排行榜分數 +$kDailyTaskAllBonusScore　金幣 +4',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: AppButton(
  label: claimable == 0 ? '沒有可領取的獎勵' : '領取全部（$claimable）',
  onPressed: claimable == 0 ? null : s.claimAllTasks,
  kind: BtnKind.primary,
),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DailyTask task;
  final AppState state;
  const _TaskCard({required this.task, required this.state});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(task.name,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                  if (task.claimed)
                    const Pill('已領取', color: AppColors.textFaint)
                  else if (task.done)
                    GestureDetector(
                      onTap: () => state.claimTask(task),
                      child: const Pill('領取', color: AppColors.accent, filled: true),
                    )
                  else
                    Text('${task.progress} / ${task.target}',
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        )),
                ],
              ),
              const SizedBox(height: 10),
              ProgressBar(
                value: task.target == 0 ? 0 : task.progress / task.target,
                color: task.done ? AppColors.ok : AppColors.accent,
                height: 6,
              ),
              const SizedBox(height: 8),
              // 原本寫「判定來源：」＋ task.sourceEvent —— 那是模型裡的
              // Event 名稱（例如「訓練已完成」），對使用者不是資訊。
              // 他要知道的是做完有什麼（`[QA-02m]`）。
              Text(
                '完成可得 $kDailyTaskScorePerItem 分排行榜分數',
                style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      );
}
