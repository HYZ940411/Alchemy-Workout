import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// 註冊問卷的選項格
///
/// 原本每個選項都是一整列的 OptionCard：只有文字、高度隨字數變動，
/// 一排一個看起來像設定頁而不像問卷。改成**等寬等高的方格 ＋ 示意圖示**：
/// 同一題的選項在視覺上等重，掃一眼就看得完。
class ChoiceOption {
  final String value;

  /// 主標。與 [value] 不同時，代表值域字串太長被拆過（例：新手（未滿 6 個月））。
  final String title;
  final String? subtitle;
  final IconData icon;
  const ChoiceOption({
    required this.value,
    required this.title,
    required this.icon,
    this.subtitle,
  });

  /// 把「新手（未滿 6 個月）」這種值域字串拆成主標與副標 ——
  /// 括號內的說明擠在同一行會把方格撐得忽高忽低。
  factory ChoiceOption.split(String value, IconData icon) {
    final m = RegExp(r'^(.*?)（(.*)）$').firstMatch(value);
    return m == null
        ? ChoiceOption(value: value, title: value, icon: icon)
        : ChoiceOption(
            value: value,
            title: m.group(1)!,
            subtitle: m.group(2),
            icon: icon,
          );
  }
}

/// 等寬等高的選項格。
///
/// 高度由 [tileHeight] 固定而非交給內容決定 —— 交給內容，
/// 有副標的格子就會比沒副標的高，同一題看起來參差不齊。
class ChoiceGrid extends StatelessWidget {
  final List<ChoiceOption> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  final int columns;
  final double tileHeight;

  const ChoiceGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onTap,
    this.columns = 2,
    this.tileHeight = 112,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          // 自行算寬度而非用 GridView：本頁的選項最多 7 個，
          // 用 Wrap 就夠，且不必再套一層可捲動的東西。
          final w = (c.maxWidth - S.md * (columns - 1)) / columns;
          return Wrap(
            spacing: S.md,
            runSpacing: S.md,
            children: [
              for (final o in options)
                SizedBox(
                  width: w,
                  height: tileHeight,
                  child: _Tile(
                    option: o,
                    selected: selected.contains(o.value),
                    onTap: () => onTap(o.value),
                  ),
                ),
            ],
          );
        },
      );
}

class _Tile extends StatelessWidget {
  final ChoiceOption option;
  final bool selected;
  final VoidCallback onTap;
  const _Tile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        // 選中＝2px action/outline，不用顏色區分（§4.4）
        borderColor: selected ? C.actionOutline : C.lineDivider,
        borderWidth: selected ? 2 : 1,
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              option.icon,
              size: 28,
              color: selected ? C.actionOutline : C.textSecondary,
            ),
            const SizedBox(height: S.sm),
            Text(
              option.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(weight: selected ? FontWeight.w700 : null),
            ),
            if (option.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                option.subtitle!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.caption(),
              ),
            ],
          ],
        ),
      );
}

/// 一排等寬的小格 —— 每週天數這種「1 到 7 選一個」用它，
/// 步進器要按六次才到得了 7。
class ChipRow extends StatelessWidget {
  final List<String> labels;
  final String? selected;
  final ValueChanged<int> onTap;
  const ChipRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - S.sm * (labels.length - 1)) / labels.length;
          return Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: S.sm),
                SizedBox(
                  width: w,
                  height: Sz.tapTarget + S.sm,
                  child: AppCard(
                    onTap: () => onTap(i),
                    borderColor: labels[i] == selected
                        ? C.actionOutline
                        : C.lineDivider,
                    borderWidth: labels[i] == selected ? 2 : 1,
                    padding: EdgeInsets.zero,
                    child: Center(
                      child: Text(
                        labels[i],
                        style: T.numberS(
                          color: labels[i] == selected
                              ? C.actionOutline
                              : C.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      );
}
