import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/novice_wrapup.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 引導收尾①：選擇偏好訓練時段
///
/// 問的是「**你哪時候有空可以練**」，不是「你慣常幾點練」——
/// 新手還沒形成訓練習慣，答不出後者，但答得出前者。
///
/// **可跳過**，跳過不阻擋任何後續 Command。跳過者七天皆空，
/// 在累積足夠訓練紀錄前收不到訓練提醒 —— 這是明示接受的代價：
/// 猜一個預設時段（如平日 19:00）猜錯時，提醒會發在他不可能訓練的時間，
/// 而推播額度只有 3 則／日，錯的提醒會排擠掉真正有用的通知。
class PreferredTimesScreen extends StatefulWidget {
  /// 從引導收尾進來的才有「稍後再選」；設定頁補填時沒有。
  final bool fromGuide;
  const PreferredTimesScreen({super.key, this.fromGuide = false});

  @override
  State<PreferredTimesScreen> createState() => _PreferredTimesScreenState();
}

class _PreferredTimesScreenState extends State<PreferredTimesScreen> {
  late PreferredTimes draft;
  bool loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loaded) return;
    draft = AppScope.of(context).preferredTimes;
    loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: const Text('偏好訓練時段'),
        automaticallyImplyLeading: !widget.fromGuide,
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('哪些時候你有空可以訓練？', style: T.h3()),
                const SizedBox(height: S.sm),
                Text(
                  '問的是有空，不是你平常幾點練 —— 剛開始練的人多半還沒有固定時間，'
                  '但答得出自己哪時候有空。以 $kSlotMinutes 分鐘為單位，區間不跨日。',
                  style: T.caption(),
                ),
              ],
            ),
          ),
          const SectionTitle('一週七天', trailing: '沒填的那天不發提醒'),
          for (var d = 0; d < 7; d++) _day(context, d),

          const SizedBox(height: S.base),
          AppCard(
            child: Text(
              draft.isEmpty
                  ? '目前七天都是空的。這樣不會收到訓練提醒，'
                    '直到你最近 4 週累積滿 $kReminderInferMinWorkouts 筆訓練紀錄，'
                    '系統改依你的訓練時戳推算。'
                  : '已填 ${draft.filledDays} 天。訓練提醒只會發在你有空的時段。',
              style: T.caption(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
            MediaQuery.of(context).padding.bottom + S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ButtonRow(
              // 可跳過：這一步位於引導收尾，強制填寫會擋在獎勵領取之前。
              left: widget.fromGuide
                  ? AppButton(
                      label: '稍後再選',
                      kind: BtnKind.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : AppButton(
                      label: '全部清空',
                      kind: BtnKind.secondary,
                      onPressed: draft.isEmpty
                          ? null
                          : () => setState(() => draft = PreferredTimes.empty()),
                    ),
              right: AppButton(
                label: '完成',
                onPressed: () {
                  s.setPreferredTimes(draft);
                  showToast(
                      context,
                      draft.isEmpty
                          ? '七天皆空，目前不發送訓練提醒'
                          : '已儲存 ${draft.filledDays} 天');
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _day(BuildContext context, int d) {
    final ranges = draft.byDay[d];
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('星期${weekdayNames[d]}',
                      style: T.body(weight: FontWeight.w700)),
                ),
                GestureDetector(
                  onTap: () => _add(context, d),
                  child: const TagBadge('＋ 新增區間'),
                ),
              ],
            ),
            const SizedBox(height: S.sm),
            if (ranges.isEmpty)
              Text('這天沒有空 —— 不發提醒。', style: T.caption())
            else
              Wrap(
                spacing: S.sm,
                runSpacing: S.sm,
                children: [
                  for (final r in ranges)
                    GestureDetector(
                      onTap: () =>
                          setState(() => draft = draft.withoutRange(d, r)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.md, vertical: S.sm),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(R.control),
                          border: Border.all(color: C.actionOutline, width: 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(r.label,
                                style: T.body(color: C.actionOutline)),
                            const SizedBox(width: S.xs),
                            const Icon(Icons.close,
                                size: 14, color: C.actionOutline),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, int d) async {
    var start = 19 * 60;
    var end = 21 * 60;
    final ok = await showAppDialog(
      context,
      title: '星期${weekdayNames[d]} 新增區間',
      confirmLabel: '加入',
      content: StatefulBuilder(
        builder: (context, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Stepper(
              label: '開始',
              value: start,
              onChanged: (v) => setInner(() {
                start = v;
                if (end <= start) end = start + kSlotMinutes;
              }),
            ),
            const SizedBox(height: S.md),
            _Stepper(
              label: '結束',
              value: end,
              // 區間不得跨日，故結束最多到 24:00。
              max: kMinutesPerDay,
              onChanged: (v) => setInner(() {
                end = v;
                if (end <= start) start = end - kSlotMinutes;
              }),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => draft = draft.withRange(d, TimeRange(start, end)));
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = kMinutesPerDay,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(label, style: T.body())),
          IconButton(
            onPressed: value - kSlotMinutes >= 0
                ? () => onChanged(value - kSlotMinutes)
                : null,
            icon: const Icon(Icons.remove, size: Sz.iconDense),
            constraints: const BoxConstraints(minWidth: Sz.tapTarget),
          ),
          SizedBox(
            width: 64,
            child: Text(TimeRange(value, value + kSlotMinutes).label.split('–')[0],
                textAlign: TextAlign.center, style: T.numberS()),
          ),
          IconButton(
            onPressed: value + kSlotMinutes <= max
                ? () => onChanged(value + kSlotMinutes)
                : null,
            icon: const Icon(Icons.add, size: Sz.iconDense),
            constraints: const BoxConstraints(minWidth: Sz.tapTarget),
          ),
        ],
      );
}
