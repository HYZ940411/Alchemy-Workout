import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/novice.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'preferred_times_screen.dart';

/// 新手任務進行頁
///
/// 形似一次訓練，但**不是一次訓練**：不走訓練紀錄流程，不產生訓練紀錄與訓練量，
/// 不計入排行榜分數、累積訓練次數與連續訓練天數，也沒有組間休息與逾時中斷判定。
///
/// 三選一而非三項待辦：目的是讓使用者完整走過一次
/// 「選擇 → 執行 → 完成 → 領獎」，做三次只是重複同一段引導。
class NoviceTaskScreen extends StatefulWidget {
  const NoviceTaskScreen({super.key});

  @override
  State<NoviceTaskScreen> createState() => _NoviceTaskScreenState();
}

class _NoviceTaskScreenState extends State<NoviceTaskScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final picked = s.noviceSelectedItem;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('新手任務')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          Text('挑一個動作試試看', style: T.h2()),
          const SizedBox(height: S.xs),
          Text(
            s.noviceChecked
                ? '已勾選完成。要改選的話先取消勾選。'
                : '選定之後、還沒勾完成之前都可以改選',
            style: T.body(color: C.textSecondary),
          ),
          const SizedBox(height: S.base),

          for (final c in s.noviceCandidates) ...[
            _Candidate(
              item: c,
              selected: s.noviceSelected == c.id,
              // 勾選後鎖住改選 —— 勾的是「所選的那一項已完成」，
              // 若還能改選，這個勾就指向了另一件事。
              enabled: !s.noviceChecked,
              onTap: () {
                s.selectNovice(c.id);
                setState(() {});
              },
            ),
            const SizedBox(height: S.md),
          ],

          if (picked != null) ...[
            const SectionTitle('這一組', trailing: '單一動作、單一組'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppCheckbox(
                        value: s.noviceChecked,
                        onChanged: (_) {
                          s.toggleNoviceCheck();
                          setState(() {});
                        },
                      ),
                      const SizedBox(width: S.md),
                      Expanded(
                        child: Text(
                          '${picked.name}　'
                          '${picked.target} ${picked.inSeconds ? '秒' : '次'}',
                          style: T.body(weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.sm),
                  Text(
                    '目標次數由範本給定，不可調整；系統也不驗證你實際做了幾下 ——'
                    '新手任務是引導，不是考核。勾錯了可以取消。',
                    style: T.caption(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
            MediaQuery.of(context).padding.bottom + S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!s.noviceChecked)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Text(
                  picked == null ? '先挑一個動作。' : '做完後勾選上面那一組，才能按完成。',
                  style: T.caption(),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: '完成這項任務',
                // 手動按完成，非勾選後自動發生 ——
                // 勾選與完成是兩個決定，中間留一個可反悔的位置。
                onPressed: s.noviceChecked
                    ? () {
                        s.finishNovice();
                        Navigator.of(context).pop();
                        // 引導收尾接在完成之後：此時使用者已實際體驗過一次訓練，
                        // 對自己想幾點練才有判斷依據。可跳過。
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                const PreferredTimesScreen(fromGuide: true)));
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Candidate extends StatelessWidget {
  final NoviceTaskItem item;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _Candidate({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(R.card),
        child: Container(
          padding: const EdgeInsets.all(S.base),
          decoration: BoxDecoration(
            color: C.bgSurface,
            borderRadius: BorderRadius.circular(R.card),
            // §4.4：選取態為 2px 外框，不是換底色。
            border: Border.all(
              color: selected ? C.actionOutline : C.lineDivider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: T.body(
                            weight: FontWeight.w700,
                            color: enabled ? null : C.textDisabled)),
                    const SizedBox(height: S.xs),
                    Text(item.summary, style: T.caption()),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    size: Sz.iconDefault, color: C.actionOutline),
            ],
          ),
        ),
      );
}
