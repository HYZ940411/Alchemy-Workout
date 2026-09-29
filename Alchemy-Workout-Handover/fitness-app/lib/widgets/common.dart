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
/// 小標籤。
///
/// ## 2026-09-29：`color` 以前是被丟掉的
///
/// 原本寫成 `borderColor: filled ? color : C.lineDivider` —— 也就是
/// **沒有 `filled: true` 的時候，傳進來的 `color` 完全不影響任何像素**。
///
/// 全 App 用了 57 次 `Pill`，其中 25 次傳了 `color` 而沒有 `filled`，
/// 那 25 個顏色一個都沒有畫出來。最明顯的後果是課表卡片上
/// 「適用經驗／適用目標裡**符合我的那一個**要染亮色」（`[QA-02l]`）——
/// 那段程式算得好好的，算完就被扔了，使用者 2026-09-29 的截圖裡
/// 一整排標籤全是灰的。
///
/// **為什麼不是一開始就改成 `filled`**：填色是實心底，一張卡片上三四個
/// 實心標籤會蓋過「推薦」本身。現在改成不填色時**邊框與文字都上色**，
/// 分得出來又不吵。
///
/// `color` 改為可空：**沒傳就跟以前一模一樣**（31 處），
/// 傳了才上色。而 `AppColors.textDim`／`textFaint` 本來就等於
/// `C.textSecondary`，所以那 13 處的外觀也不變 ——
/// 真正會變的是 accent／cool／bronze／blue 那 12 處，
/// 而那正是作者本來就想要的。
class Pill extends StatelessWidget {
  final String text;
  final Color? color;
  final bool filled;
  const Pill(this.text, {super.key, this.color, this.filled = false});

  @override
  Widget build(BuildContext context) => TagBadge(
        text,
        borderColor: filled ? (color ?? C.actionOutline) : color,
        fill: filled ? (color ?? C.actionOutline) : null,
        textColor: filled ? null : color,
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
