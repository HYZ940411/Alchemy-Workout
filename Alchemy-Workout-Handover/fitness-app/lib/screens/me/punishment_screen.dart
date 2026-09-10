import 'package:flutter/material.dart';

import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：我的處罰與申訴頁
class PunishmentScreen extends StatelessWidget {
  const PunishmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = s.punishment;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('處罰與申訴',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
        children: [
          if (p == null)
            Panel(
              child: Row(
                children: const [
                  Icon(Icons.verified_user_outlined,
                      size: 20, color: AppColors.accent),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text('目前處罰狀態：無　·　累計違規次數 0',
                        style: TextStyle(fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
            )
          else ...[
            Panel(
              color: AppColors.gold.withValues(alpha: 0.08),
              border: AppColors.gold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.gavel_rounded,
                          size: 19, color: AppColors.bronze),
                      const SizedBox(width: 10),
                      Text(punishmentKindNames[p.kind]!,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (p.expiresAt != null)
                        Text(
                          '至 ${p.expiresAt!.month}/${p.expiresAt!.day}',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 12),
                        )
                      else
                        const Pill('無到期', color: AppColors.bronze),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('處罰原因：${p.reason}',
                      style: const TextStyle(fontSize: 12.5, height: 1.6)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('依據內容：${p.evidence}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.6,
                            color: AppColors.textDim)),
                  ),
                ],
              ),
            ),
            const SectionLabel('違規累計'),
            Panel(
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                        label: '累計違規次數', value: '${p.violationCount}'),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('下一級的後果',
                            style: TextStyle(
                                color: AppColors.textFaint, fontSize: 11)),
                        const SizedBox(height: 4),
                        Text(p.nextConsequence,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('申訴'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('申訴期限倒數',
                            style: TextStyle(fontSize: 13)),
                      ),
                      Text('${p.appealDaysLeftAt(s.now)} 天',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: p.appealDaysLeftAt(s.now) > 7
                                ? AppColors.accent
                                : AppColors.bronze,
                          )),
                    ],
                  ),
                  if (p.appealed) ...[
                    const Divider(height: 22, color: AppColors.line),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('申訴進度',
                              style: TextStyle(fontSize: 13)),
                        ),
                        Pill(appealStateNames[p.appealState]!,
                            color: AppColors.blue),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text('管理員的審核時限為 72 小時',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 11)),
                  ] else ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
  label: p.canAppealAt(s.now) ? '申訴處罰' : '已逾申訴期限',
  onPressed: p.canAppealAt(s.now) ? () => _appeal(context, s) : null,
  kind: BtnKind.primary,
),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 申訴須附理由。同一處罰限申訴一次，不論成立與否。
  Future<void> _appeal(BuildContext context, AppState s) async {
    final controller = TextEditingController();
    final ok = await showAppDialog(
      context,
      title: '申訴這次處罰',
      confirmLabel: '送出申訴',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('同一處罰只能申訴一次，不論成立與否。送出後由管理員審視。',
              style: T.body(color: C.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: S.md),
          TextField(
            controller: controller,
            style: T.body(),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '說明為什麼你認為這次處罰不成立',
              hintStyle: T.body(color: C.textDisabled),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final reason = controller.text.trim();
    s.fileAppeal(reason.isEmpty ? '（未填理由）' : reason);
  }
}