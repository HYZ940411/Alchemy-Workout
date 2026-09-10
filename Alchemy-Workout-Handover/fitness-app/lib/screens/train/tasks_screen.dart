import '../../domain/rewards.dart';
import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/decay.dart';
import '../../domain/novice.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../domain/novice_wrapup.dart';
import 'novice_task_screen.dart';
import 'preferred_times_screen.dart';
import 'rate_experience_screen.dart';

/// 新手任務清單與回歸任務卡 —— 兩份 Read Model 不合併：
/// 更新觸發源與生命週期完全不同。
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('新手 / 回歸任務',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          const SectionLabel('新手任務', trailing: '一次性，無完成期限'),
          _NoviceCard(state: s),
          const SectionLabel('回歸任務', trailing: '能力值退步後指派'),
          _ReturnCard(state: s),
        ],
      ),
    );
  }
}

class _NoviceCard extends StatelessWidget {
  final AppState state;
  const _NoviceCard({required this.state});

  @override
  Widget build(BuildContext context) {
    // 已完成但未領取者一直掛在本頁 —— 新手任務無完成期限，
    // 獎勵不進獎勵信箱。
    if (state.noviceFinished) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新手任務已完成',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '腿與核心的初始值已拉高至 $kNoviceLegCoreInitial（地板，非點數紀錄），'
              '兩維由 E 變 E+；社群互動功能也一併解鎖了。',
              style: const TextStyle(
                  fontSize: 12.5, height: 1.6, color: AppColors.textDim),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: '領取獎勵　'
                    '$kNoviceExp EXP · $kNoviceCoin 金幣 · AI $kNoviceAiCredits 點',
                kind: BtnKind.primary,
                onPressed: state.noviceRewardClaimed
                    ? null
                    : () {
                        final r = state.claimNoviceReward()!;
                        showToast(context,
                            '已領取：${r.exp} EXP、${r.coins} 金幣、'
                            'AI 永久點數 ${r.ai} 點');
                      },
              ),
            ),
            const Divider(height: 26, color: AppColors.line),
            const Text('引導收尾',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('兩步都可以跳過，不擋你領獎勵，之後也隨時能補。',
                style: TextStyle(
                    color: AppColors.textDim, fontSize: 11.5, height: 1.5)),
            const SizedBox(height: 10),
            _WrapUpRow(
              label: '偏好訓練時段',
              value: state.preferredTimes.isEmpty
                  ? '未填 —— 目前不發訓練提醒'
                  : '已填 ${state.preferredTimes.filledDays} 天',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PreferredTimesScreen())),
            ),
            _WrapUpRow(
              label: '新手任務體驗評分',
              value: state.noviceRating == null
                  ? '未評分'
                  : '${state.noviceRating!.stars} 星　·　可修改',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RateExperienceScreen(
                        target: RatingTarget.noviceTask,
                        targetId: kNoviceTaskId,
                        targetName: '新手任務',
                      ))),
            ),
          ],
        ),
      );
    }

    // 「新手任務已指派」與「使用者已開始新手任務」是兩個 Event ——
    // 由使用者主動點擊開始，非系統自動觸發。
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.noviceStarted
                ? '任務進行中。挑一個動作做完，回來按完成。'
                : '三個候選動作三選一，完整走過一次「選擇 → 執行 → 完成 → 領獎」。',
            style: const TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: state.noviceStarted ? '繼續新手任務' : '開始新手任務',
              kind: BtnKind.primary,
              onPressed: () {
                state.startNovice();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NoviceTaskScreen()));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WrapUpRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _WrapUpRow(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 12)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textFaint),
            ],
          ),
        ),
      );
}

class _ReturnCard extends StatelessWidget {
  final AppState state;
  const _ReturnCard({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.returnTaskAssigned) {
      return Panel(
        child: Text(
          state.returnTaskOverdueStreak >= 3
              ? '連續 3 次逾期後停止指派，直到你再次訓練為止。'
              : '目前沒有回歸任務。',
          style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
        ),
      );
    }
    final left = state.returnTaskDaysLeft;
    final d = state.returnTaskDim;
    final cum = d == null ? 0 : state.decayTimers[d]!.cumulative;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.replay_circle_filled_outlined,
                  size: 19, color: C.accentDeep),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('回歸任務',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Pill(state.returnTaskDone ? '已完成' : '已指派',
                  color: state.returnTaskDone ? C.statusSuccess : C.accentDeep),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            d == null
                ? '完成一次訓練，即可部分回復退步的點數。'
                : '你的${dimNames[d]}已超過 ${kDecayIntervalHours ~/ 24} 天未訓練並發生退步'
                    '${cum > 0 ? '（累積 $cum 點）' : ''}。'
                    '完成回歸任務即可回復六維各自累積退步量的 '
                    '${(kRecoverRatio * 100).round()}%。',
            style: const TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.textDim),
          ),
          const SizedBox(height: 12),
          if (left == null)
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: '查看回歸任務',
                onPressed: state.viewReturnTask,
                kind: BtnKind.primary,
              ),
            )
          else ...[
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 14, color: AppColors.blue),
                const SizedBox(width: 6),
                Text('剩餘時限 $left 天',
                    style: const TextStyle(color: AppColors.blue, fontSize: 12.5)),
              ],
            ),
            if (!state.returnTaskDone) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: '完成回歸任務',
                  kind: BtnKind.primary,
                  onPressed: () => _complete(context),
                ),
              ),
            ],
            // 獎勵不於完成時自動發放，須主動點擊領取 ——
            // 領取的點擊本身即為回饋體驗的一環。
            if (state.returnRewardClaimable) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: '領取獎勵　經驗值 $kReturnTaskExp ＋ 金幣 '
                      '$kReturnTaskCoin ＋ AI 點數 $kReturnTaskCredit',
                  kind: BtnKind.primary,
                  onPressed: () => _claim(context),
                ),
              ),
            ] else if (state.returnTaskDone) ...[
              const SizedBox(height: 12),
              Text('獎勵已領取。', style: T.caption()),
            ],
          ],
        ],
      ),
    );
  }

  void _claim(BuildContext context) {
    final r = state.claimReturnReward();
    if (r == null) return;
    showToast(context,
        '已領取：經驗值 ${r.exp} ＋ 金幣 ${r.coins} ＋ AI 點數 ${r.credit}');
  }

  void _complete(BuildContext context) {
    final rec = state.completeReturnTask();
    final text = rec.isEmpty
        // 從未訓練者的累積退步量恆為 0，回復 0 點 —— 文案不能寫「回復退步的能力值」。
        ? '回歸任務已完成。本次中斷沒有累積退步量，無點數可回復。'
        : '能力值已部分回復：'
            '${rec.entries.map((e) => '${dimNames[e.key]} +${e.value}').join('、')}';
    showToast(context, text);
  }
}
