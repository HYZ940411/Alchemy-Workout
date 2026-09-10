import 'package:flutter/material.dart';

import '../../domain/custom_plan.dart';
import '../../state/app_state.dart';
import 'custom_plan_edit_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：自訂訓練管理頁
class CustomPlansScreen extends StatelessWidget {
  const CustomPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final quota = s.customPlanQuota;
    final mine = s.customPlans.where((p) => p.isMine).toList();
    final full = quota < 999 && mine.length >= quota;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('自訂訓練',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          Panel(
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('名額使用量',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                Text(
                  quota >= 999 ? '${mine.length} / 無限' : '${mine.length} / $quota',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (full) ...[
            const SizedBox(height: 10),
            Panel(
              color: AppColors.gold.withValues(alpha: 0.10),
              border: AppColors.gold,
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 17, color: AppColors.bronze),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '名額已滿。刪除自訂訓練為釋放名額的唯一手段；'
                      '名額滿時 AI 調整改走快照。',
                      style: TextStyle(fontSize: 11.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          AppButton(
            label: '新增自訂訓練',
            icon: Icons.add_rounded,
            onPressed: full ? null : () => _edit(context, s),
          ),
          const SectionLabel('我的課表'),
          for (final p in mine)
            _PlanRow(
              plan: p,
              state: s,
              onEdit: () => _edit(context, s, existing: p),
              onDelete: () => _delete(context, s, p),
            ),
        ],
      ),
    );
  }

  /// 草稿 → 已儲存。新建與修改共用同一頁。
  Future<void> _edit(BuildContext context, AppState s,
      {CustomPlan? existing}) async {
    final result = await Navigator.of(context).push<SavedPlan>(
      MaterialPageRoute(
        builder: (_) => CustomPlanEditScreen(initial: existing),
      ),
    );
    if (result == null) return;
    if (existing == null) {
      s.addPlan(result.name, result.exercises);
    } else {
      s.editPlan(existing, name: result.name, exercises: result.exercises);
    }
  }

  /// 刪除為釋放名額的唯一手段，且已刪除為終止狀態 —— 不可復原，故須確認。
  Future<void> _delete(BuildContext context, AppState s, CustomPlan p) async {
    final ok = await showAppDialog(
      context,
      title: '刪除「${p.name}」？',
      message: '已刪除為終止狀態，不會再出現於本頁，也無法復原。刪除後釋放一個名額。',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (ok != true) return;
    s.deletePlan(p);
  }
}

class _PlanRow extends StatelessWidget {
  final CustomPlan plan;
  final AppState state;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PlanRow({
    required this.plan,
    required this.state,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _stateColor => switch (plan.state) {
        CustomPlanState.public => AppColors.accent,
        CustomPlanState.pendingPublic => AppColors.blue,
        CustomPlanState.rejected => AppColors.bronze,
        _ => AppColors.textDim,
      };

  void _run(BuildContext context, String action) {
    switch (action) {
      case '發布':
        if (state.planQuotaLocked(plan)) {
          showToast(context, '這份課表超出名額已鎖定，不可啟用。');
          return;
        }
        state.publishPlan(plan);
      case '取消發布':
        state.unpublishPlan(plan);
      case '申請公開':
        state.applyPublic(plan);
        showToast(context, '已送出，審核時限 $kPublicPlanReviewDays 天');
      case '下架':
        state.takeDownPlan(plan);
      case '退回已發布':
        state.resumePublished(plan);
      case '刪除':
        onDelete();
      default:
        onEdit();
    }
  }

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
                    child: Text(plan.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  if (state.planQuotaLocked(plan)) ...[
                    const Pill('已鎖定', color: AppColors.bronze),
                    const SizedBox(width: 6),
                  ],
                  Pill(customPlanStateNames[plan.state]!, color: _stateColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${plan.exerciseCount} 個動作　·　我的使用次數 ${plan.myUses}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
              if (state.planQuotaLocked(plan)) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 13, color: AppColors.bronze),
                    const SizedBox(width: 5),
                    // 「鎖定但不刪除」—— 使用者第一個念頭會是「我的課表被刪了」，
                    // 所以要先講資料還在。
                    Expanded(
                      child: Text(
                        '超出目前名額（${state.myPlanCount} / ${state.customPlanQuota}），'
                        '暫時不可選用於訓練。資料完整保留，'
                        '訂閱會員或升階後即回復可用。',
                        style: T.caption(color: AppColors.bronze),
                      ),
                    ),
                  ],
                ),
              ],
              if (plan.state == CustomPlanState.pendingPublic) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      plan.reviewOverdue
                          ? Icons.report_gmailerrorred_outlined
                          : Icons.hourglass_top_rounded,
                      size: 13,
                      color:
                          plan.reviewOverdue ? AppColors.hot : AppColors.blue,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      plan.reviewOverdue
                          ? '審核已逾期，仍在等待管理員處理'
                          : '審核中，剩 ${plan.reviewDaysLeft} 天',
                      style: TextStyle(
                          color: plan.reviewOverdue
                              ? AppColors.hot
                              : AppColors.blue,
                          fontSize: 11.5),
                    ),
                  ],
                ),
              ],
              if (plan.rejectReason != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.report_gmailerrorred_outlined,
                          size: 14, color: AppColors.bronze),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text('駁回理由：${plan.rejectReason}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.5,
                                color: AppColors.bronze)),
                      ),
                    ],
                  ),
                ),
              ],
              if (plan.canToggleVisibility) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child:
                          Text('對關注者可見', style: TextStyle(fontSize: 12.5)),
                    ),
                    AppSwitch(
                      value: plan.visibleToFollowers,
                      onChanged: (v) => state.setVisibleToFollowers(plan, v),
                    ),
                  ],
                ),
              ] else if (plan.state == CustomPlanState.public) ...[
                const SizedBox(height: 8),
                const Text('對關注者可見開關不生效（全平台已涵蓋）',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 11)),
              ],
              const Divider(height: 20, color: AppColors.line),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in plan.actions)
                    AppButton(
                      label: a,
                      kind: BtnKind.secondary,
                      onPressed: () => _run(context, a),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}
