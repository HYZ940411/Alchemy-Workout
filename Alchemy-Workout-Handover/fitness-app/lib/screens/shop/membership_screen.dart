import 'package:flutter/material.dart';

import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：會員訂閱頁 —— 權益逐條對照使用者現況。
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});
  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  bool yearly = true;

  /// 已取消待到期者要看得出自己還剩幾天 —— 沒有這一行，
  /// 他跟正常訂閱者看到的東西一模一樣。
  static String _expiryLine(AppState s) {
    final d = s.membershipExpiry!;
    final date = '${d.year}/${d.month}/${d.day}';
    switch (s.membership) {
      case MembershipState.cancelledPending:
        return '已取消，權益將於 $date 結束。在那之前全部權益照常。';
      case MembershipState.expired:
        return '已於 $date 到期。重新訂閱即沿用同一筆會員權益。';
      default:
        return '到期日：$date';
    }
  }

  @override
  void initState() {
    super.initState();
    // 真實系統由 App Store 的到期通知觸發；本專案於進入本頁時結算，
    // 效果相同 —— 使用者看到的一定是已經結算過的狀態。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).expireMembershipIfDue();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final unlockedPlans =
        s.platformPlans.where((p) => !s.planUnlocked(p)).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('會員訂閱',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
        children: [
          Panel(
            child: Row(
              children: [
                const Expanded(
                  child: Text('權益生效狀態',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                Pill(
                  membershipStateNames[s.membership]!,
                  color: s.isMember ? AppColors.accent : AppColors.textDim,
                  filled: s.isMember,
                ),
              ],
            ),
          ),
          if (s.membershipExpiry != null) ...[
            const SizedBox(height: 8),
            Panel(
              padding: const EdgeInsets.all(13),
              child: Text(
                _expiryLine(s),
                style: const TextStyle(fontSize: 12.5, color: AppColors.textDim),
              ),
            ),
          ],
          if (s.membership == MembershipState.expired &&
              s.membershipLockedPlanIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Panel(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '權益到期時鎖回了 ${s.membershipLockedPlanIds.length} 份進階計畫',
                    style: T.body(weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  // 僅改變可選用性，不刪除任何資料。
                  Text(
                    '只是不能選來練，資料一筆都沒刪 —— 訓練紀錄、快照與統計'
                    '全部保留，續訂後回復原狀，不是從零開始。'
                    '以階級達標或金幣購買取得的計畫不受影響。',
                    style: T.caption(),
                  ),
                ],
              ),
            ),
          ],
          const SectionLabel('權益', trailing: '對照你的現況'),
          // 這一段本來有三處**寫死的假資料**（「你目前 5 / 5」「你這個月
          // 用了 6 次，花了 900 金幣」），而且最後一條會**整頁當掉** ——
          // `snapshots.keys.reduce(...)` 對空集合丟 StateError，
          // 而新帳號一份能力值快照都沒有。使用者回報「會員頁是灰色的，
          // 無法顯示任何資料」就是它（2026-09-28）。
          //
          // 「權益逐條對照使用者現況」是這一頁的用途 —— 對照的若是假的，
          // 這一頁就沒有存在的理由。
          _Benefit(
            title: '無限自訂訓練',
            current: s.isMember
                ? '你目前 ${s.myPlanCount} 份，會員不限數量'
                : '你目前 ${s.myPlanCount} / ${s.customPlanQuota} 份',
          ),
          _Benefit(
            title: '每月 $kMonthlyAiCredits 點 AI 點數',
            current: s.isMember
                ? '本月剩餘 ${s.aiMonthly} 點（另有永久點數 ${s.aiPermanent} 點）'
                : '你目前只有永久點數 ${s.aiPermanent} 點，沒有每月配發',
          ),
          _Benefit(
            title: '解鎖全部進階訓練計畫',
            current: unlockedPlans == 0
                ? '你已經解鎖全部計畫'
                : '還有 $unlockedPlans 個計畫你尚未解鎖',
          ),
          _Benefit(
            title: '訓練歷史的跨時間彙總',
            // **空集合不能 reduce。** 沒有快照時講實話，不要硬湊一個數字。
            current: s.snapshots.isEmpty
                ? '你還沒有能力值歷史 —— 練過幾次之後就會開始累積'
                : '你已累積 ${s.snapshots.length} 天的能力值歷史',
          ),
          const _Benefit(
            title: '免費 AI 自動優化 ＋ 月報 AI 分析',
            current: null,
          ),
          const SectionLabel('方案'),
          Row(
            children: [
              Expanded(
                child: _PlanTile(
                  title: '月繳',
                  price: 'NT\$$kMonthlyPrice',
                  sub: '每月',
                  selected: !yearly,
                  onTap: () => setState(() => yearly = false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PlanTile(
                  title: '年繳',
                  price: 'NT\$$kYearlyPrice',
                  sub: '約 8 折',
                  selected: yearly,
                  onTap: () => setState(() => yearly = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: AppButton(
  label: s.isMember ? '已訂閱' : '訂閱會員',
  onPressed: s.isMember ? null : () => s.subscribe(yearly: yearly),
  kind: BtnKind.primary,
),
          ),
          if (s.membership == MembershipState.active) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: AppButton(
  label: '取消訂閱（維持至到期）',
  onPressed: s.cancelSubscription,
  kind: BtnKind.secondary,
),
            ),
          ],
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final String title;
  final String? current;
  const _Benefit({required this.title, this.current});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 17, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    if (current != null) ...[
                      const SizedBox(height: 4),
                      Text(current!,
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PlanTile extends StatelessWidget {
  final String title;
  final String price;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  const _PlanTile({
    required this.title,
    required this.price,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppColors.accent : AppColors.line),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: [
              Text(title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.onAccent : AppColors.textDim,
                  )),
              const SizedBox(height: 6),
              Text(price,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: selected ? AppColors.onAccent : AppColors.text,
                  )),
              const SizedBox(height: 3),
              Text(sub,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: selected
                        ? AppColors.onAccent.withValues(alpha: 0.75)
                        : AppColors.textFaint,
                  )),
            ],
          ),
        ),
      );
}
