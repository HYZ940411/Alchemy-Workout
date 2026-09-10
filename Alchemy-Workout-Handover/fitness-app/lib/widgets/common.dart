import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

export '../design/components.dart';
export '../design/overlays.dart';
export '../design/typography.dart' show T, ValueUnit;

/// 卡片（§5.2）—— 圓角 16、內距 16、底 bg/surface、單一陰影。
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? border;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.base),
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) =>
      AppCard(padding: padding, color: color, borderColor: border, child: child);
}

/// 小節標題（H3 17／24）
class SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => SectionTitle(text, trailing: trailing);
}

/// 統計欄位（§8.17）—— 標籤 Caption、數值 Number-M、單位間距 4px。
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.caption(), maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: S.xs),
          ValueUnit(
            value: value,
            unit: unit,
            style: T.numberM(color: valueColor),
          ),
        ],
      );
}

/// 進度條軌道（§8.7）。
/// 【必須】呼叫端必須在旁邊提供文字 —— 低對比豁免成立的唯一條件。
class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const ProgressBar({
    super.key,
    required this.value,
    this.color = C.statusSuccess,
    this.height = Sz.progressHeight,
  });

  @override
  Widget build(BuildContext context) =>
      BareProgress(value: value, color: color);
}

/// 文字標籤（§8.14）—— 圓角 8、內距 2／8、Caption、1px 外框。
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool filled;
  const Pill(this.text, {super.key, this.color = C.actionOutline, this.filled = false});

  @override
  Widget build(BuildContext context) => TagBadge(
        text,
        borderColor: filled ? color : C.lineDivider,
        fill: filled ? color : null,
      );
}

/// 停權說明條。停權時**擋住的 Command 都要說得出理由** ——
/// 靜靜地什麼都不發生，使用者只會以為是 App 壞了，
/// 而處罰的嚇阻力正來自他知道自己為什麼做不了這件事。
class SuspensionNotice extends StatelessWidget {
  final String reason;
  const SuspensionNotice(this.reason, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(S.md),
        decoration: BoxDecoration(
          color: C.statusError.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: C.statusError.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.block, size: Sz.iconDense, color: C.statusError),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(reason,
                  style: T.caption(color: C.statusError)),
            ),
          ],
        ),
      );
}
