import 'package:flutter/material.dart';

import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：補簽頁
/// 日曆涵蓋距今 1 至 N 天（N ＝ 回補範圍，初始 7），不含今日。
class MakeupScreen extends StatefulWidget {
  const MakeupScreen({super.key});
  @override
  State<MakeupScreen> createState() => _MakeupScreenState();
}

class _MakeupScreenState extends State<MakeupScreen> {
  MakeupDay? selected;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final days = s.makeupDaysInRange;
    final sel = selected;
    final canUse = sel != null && s.canMakeUp(sel);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('補簽',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          Panel(
            child: Row(
              children: [
                const Icon(Icons.confirmation_num_outlined,
                    size: 18, color: C.accentDeep),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('補簽券張數',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                Text('${s.makeupTickets}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: C.accentDeep,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
                Text(' / ${s.makeupTicketCap}', style: T.caption()),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.makeupTickets >= s.makeupTicketCap
                      ? '已達持有上限 ${s.makeupTicketCap} 張，用掉幾張才買得了。'
                      : '補簽券無有效期限，最多持有 ${s.makeupTicketCap} 張。',
                  style: T.caption(),
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: '以 ${s.makeupTicketPrice} 金幣購買一張',
                  kind: BtnKind.secondary,
                  onPressed: s.makeupTickets >= s.makeupTicketCap
                      ? null
                      : () {
                          final fail = s.buyMakeupTicket();
                          showToast(context, fail ?? '已購買一張補簽券');
                        },
                ),
              ],
            ),
          ),
          SectionLabel('最近 ${s.makeupRangeDays} 天', trailing: '不含今日'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            // 用 Wrap 而非 Row：回補範圍可由管理員調大，日數超過一列寬時
            // 換行而非溢位（375px 下一列最多容 7 格）。
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: S.sm,
              runSpacing: S.base,
              children: [
                for (final d in days)
                  _DayCell(
                    day: d,
                    selected: identical(d, sel),
                    canMakeUp: s.canMakeUp(d),
                    onTap: d.state == MakeupDayState.missed
                        ? () => setState(() => selected = d)
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              _Legend(
                  fill: C.statusSuccess, dashed: false, label: '已簽到'),
              const SizedBox(width: S.base),
              _Legend(
                  fill: C.statusSuccessTint, dashed: true, label: '可補簽'),
              const SizedBox(width: S.base),
              _Legend(fill: C.bgSurface, dashed: false, label: '不可補簽'),
            ],
          ),
          const SizedBox(height: S.md),
          if (sel != null)
            Panel(
              color: AppColors.accent.withValues(alpha: 0.06),
              border: AppColors.accent.withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '補 ${sel.date.month}/${sel.date.day}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '代價',
                          value: '1',
                          unit: '張補簽券',
                          valueColor: AppColors.bronze,
                        ),
                      ),
                      Expanded(
                        child: StatTile(
                          label: '補簽後可恢復的連續天數',
                          value: '${s.simulateStreakAfterMakeup(sel)}',
                          unit: '天',
                          valueColor: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
  // 按不下去時，鈕上就要寫得出為什麼 —— 一個灰掉又不解釋的鈕
  // 只會讓人以為是壞的。
  label: s.makeupBlockedReason(sel) ?? '使用補簽券',
  onPressed: canUse
                          ? () {
                              s.useMakeupTicket(sel);
                              setState(() => selected = null);
                            }
                          : null,
  kind: BtnKind.primary,
),
                  ),
                ],
              ),
            )
          else
            const Panel(
              child: Text('點選未簽到的日期以試算。',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color fill;
  final bool dashed;
  final String label;
  const _Legend(
      {required this.fill, required this.dashed, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(R.inset),
              border: dashed ? null : Border.all(color: C.lineDivider),
            ),
            foregroundDecoration: dashed
                ? const _DashedBorder(color: C.textSecondary, radius: R.inset)
                : null,
          ),
          const SizedBox(width: S.xs),
          Text(label, style: T.caption()),
        ],
      );
}

/// 日曆格（依設計稿）
///
/// 已簽到＝薄荷實心；**可補簽＝淺薄荷底 ＋ 虛線框**；超出回補範圍＝白底實線。
/// 淺薄荷對頁底僅 1.11:1，本身看不出邊界 —— 虛線框不是裝飾，
/// 是這一格能被辨認的唯一條件（與 §4.3 的低對比豁免同一套道理）。
class _DayCell extends StatelessWidget {
  final MakeupDay day;
  final bool selected;
  final bool canMakeUp;
  final VoidCallback? onTap;
  const _DayCell({
    required this.day,
    required this.selected,
    required this.canMakeUp,
    this.onTap,
  });

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final done = day.state != MakeupDayState.missed;
    final fill = done
        ? C.statusSuccess
        : (canMakeUp ? C.statusSuccessTint : C.bgSurface);
    // 文字一律用墨色 —— 三種底色上的對比都在 13 以上
    final fg = canMakeUp || done ? C.textOnAccent : C.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(_weekdays[day.date.weekday - 1], style: T.caption()),
          const SizedBox(height: S.sm),
          Container(
            width: 40,
            height: Sz.tapTarget,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(R.control),
              // 選中／今日：2px 實框；可補簽：虛線；其餘：細實線
              border: selected
                  ? Border.all(color: C.actionOutline, width: 2)
                  : (done || canMakeUp
                      ? null
                      : Border.all(color: C.lineDivider)),
            ),
            foregroundDecoration: (!selected && canMakeUp)
                ? const _DashedBorder(color: C.textSecondary, radius: R.control)
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${day.date.day}',
                    style: T.body(color: fg, weight: FontWeight.w700)),
                const SizedBox(height: 1),
                Icon(
                  switch (day.state) {
                    MakeupDayState.signed => Icons.check,
                    MakeupDayState.madeUp => Icons.restore,
                    MakeupDayState.missed =>
                      canMakeUp ? Icons.add : Icons.remove,
                  },
                  size: 11,
                  color: fg,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 虛線框。Flutter 的 Border 不支援虛線，故以 Decoration 自繪。
class _DashedBorder extends Decoration {
  final Color color;
  final double radius;
  const _DashedBorder({required this.color, required this.radius});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedPainter(color, radius);
}

class _DashedPainter extends BoxPainter {
  final Color color;
  final double radius;
  _DashedPainter(this.color, this.radius);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size!;
    final rect = offset & size;
    final rrect = RRect.fromRectAndRadius(
        rect.deflate(0.5), Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    // 4 實 4 虛，與設計稿的 stroke-dasharray="4 4" 一致
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 8;
      }
    }
  }
}
