import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：獎勵信箱頁
class MailboxScreen extends StatelessWidget {
  const MailboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('獎勵信箱',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          Panel(
            child: Row(
              children: [
                const Icon(Icons.markunread_mailbox_outlined,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('未領取筆數',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                Text('${s.unclaimedMail}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: AppButton(
  label: '一鍵全部領取',
  onPressed: s.unclaimedMail == 0 ? null : s.claimAllMail,
  kind: BtnKind.primary,
),
          ),
          const SectionLabel('獎勵清單'),
          if (s.mailbox.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: S.xl),
              child: EmptyState(
                icon: Icons.markunread_mailbox_outlined,
                title: '信箱是空的',
                message: '每日任務、排行獎勵、補簽與限時任務的未領獎勵會補發到這裡。',
              ),
            ),
          for (final m in s.mailbox)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.all(14),
                child: Opacity(
                  opacity: m.claimed ? 0.45 : 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.content,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              '${m.source}　·　'
                              '${m.at.month}/${m.at.day}',
                              style: const TextStyle(
                                  color: AppColors.textFaint, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      m.claimed
                          ? const Pill('已領取', color: AppColors.textFaint)
                          : GestureDetector(
                              onTap: () => s.claimMail(m),
                              child: const Pill('領取',
                                  color: AppColors.accent, filled: true),
                            ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
