import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

// ---------------------------------------------------------------------------
// 按鈕（§5.1）
// ---------------------------------------------------------------------------

enum BtnKind {
  /// 底 action/primary、文字 text/on-accent。真正的 CTA。
  primary,

  /// 底 bg/surface、1px 外框與文字 action/outline。
  /// 【必須】破壞性動作同次要按鈕（§4.5 R-23）——危險動作不給最顯眼的樣式。
  secondary,
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final IconData? icon;
  final bool loading;
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = BtnKind.primary,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final isPrimary = kind == BtnKind.primary;

    final bg = isPrimary
        ? (enabled ? C.actionPrimary : C.actionPrimaryDisabled)
        : C.bgSurface;
    final fg = isPrimary
        ? C.textOnAccent
        : (enabled ? C.actionOutline : C.textDisabled);

    return Opacity(
      // 停用態：整體不透明度 40%（§4.4）
      opacity: enabled || isPrimary ? 1.0 : 0.4,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.control),
          side: isPrimary
              ? BorderSide.none
              : BorderSide(color: enabled ? C.actionOutline : C.lineDivider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          // 按下：疊一層 rgba(28,28,30,0.08)
          highlightColor: C.press,
          splashColor: C.press,
          child: Container(
            // 【必須】最小高度 48px，非固定高度 —— 字級放大時必須能長高
            constraints: const BoxConstraints(minHeight: Sz.buttonMinHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: S.base,
              vertical: S.md,
            ),
            // **`heightFactor: 1` 不可省。**
            //
            // 這裡原本是 `Container` 的 `alignment: Alignment.center`，
            // 而**帶 alignment 的 Container 在「有界但寬鬆」的約束下會把
            // 自己撐到最大**（它內部就是一個 widthFactor／heightFactor
            // 皆為空的 `Align`）。
            //
            // 在 `Column`／`Row`／`ListView` 裡看不出來 —— 那些給的是
            // 無界主軸，`Align` 會縮到子項大小。但放進 `Center`、或
            // `Scaffold.bottomNavigationBar` 就會撐滿整個畫面。
            //
            // 2026-09-28 使用者實測教官測驗：交卷鍵佔了 16,16→377,836，
            // 而題目清單的高度是 **0** —— 二十三題一題都畫不出來，
            // 他只看到一整片橘色。
            //
            // `heightFactor: 1` 讓它依子項決定高度；寬度仍然吃滿，
            // 所以既有版面（全寬按鈕）不變。
            child: Align(
              alignment: Alignment.center,
              heightFactor: 1,
              child: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: Sz.iconDense, color: fg),
                          const SizedBox(width: S.sm),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: T.button(color: fg),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 兩顆並排：等寬平分、間距 12px。
/// 【必須】任一按鈕文字需換行時自動改為上下堆疊（§5.1）。
class ButtonRow extends StatelessWidget {
  final AppButton left;
  final AppButton right;
  const ButtonRow({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final half = (c.maxWidth - S.md) / 2;
      final stack =
          _needsWrap(left.label, half) || _needsWrap(right.label, half);
      if (stack) {
        return Column(
          children: [
            SizedBox(width: double.infinity, child: left),
            const SizedBox(height: S.md),
            SizedBox(width: double.infinity, child: right),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: S.md),
          Expanded(child: right),
        ],
      );
    },
  );

  static bool _needsWrap(String label, double width) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: T.button()),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width > width - S.base * 2;
  }
}

// ---------------------------------------------------------------------------
// 卡片（§5.2）
// ---------------------------------------------------------------------------

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(S.base),
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(R.card),
      boxShadow: C.shadow,
    ),
    child: Material(
      color: color ?? C.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.card),
        side: BorderSide(
          color: borderColor ?? C.lineDivider,
          width: borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        highlightColor: C.press,
        splashColor: C.press,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 清單列（§8.1）—— 全案最高頻元件
// ---------------------------------------------------------------------------

class ListRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  final bool showDivider;
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    // 分隔線左側起點：無頭像 16px、有頭像 60px（＝16 ＋ 32 ＋ 12）
    final indent = leading == null ? S.base : 60.0;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          highlightColor: C.press,
          splashColor: C.press,
          child: Container(
            constraints: BoxConstraints(
              minHeight: subtitle == null ? Sz.listRowSingle : Sz.listRowDouble,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: S.base,
              vertical: S.base,
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: S.md)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 【必須】主文字過長時截斷加省略號，不可推擠右側元素
                      Text(
                        title,
                        style: T.body(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: T.caption(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // 【必須】右側元素與主文字之間至少 12px
                if (trailing != null) ...[
                  const SizedBox(width: S.md),
                  trailing!,
                ],
                if (chevron) ...[
                  const SizedBox(width: S.md),
                  const Icon(
                    Icons.chevron_right,
                    size: Sz.iconDense,
                    color: C.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
        // 【必須】分隔線畫在列的下緣，最後一列不畫
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(left: indent),
            child: const Divider(height: 1, thickness: 1, color: C.lineDivider),
          ),
      ],
    );
  }
}

/// 一組清單列，自動處理「最後一列不畫分隔線」。
class ListGroup extends StatelessWidget {
  final List<ListRow> rows;
  const ListGroup({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          ListRow(
            title: rows[i].title,
            subtitle: rows[i].subtitle,
            leading: rows[i].leading,
            trailing: rows[i].trailing,
            chevron: rows[i].chevron,
            onTap: rows[i].onTap,
            showDivider: i != rows.length - 1,
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// 進度條（§8.7）
// ---------------------------------------------------------------------------

/// 【必須】每一條進度條旁都要有文字 —— 這是低對比豁免成立的唯一條件（§4.3）。
/// 薄荷綠對軌道只有 1.41:1，沒有數字就等於看不出進度。
class AppProgress extends StatelessWidget {
  /// 必填，強制符合規範。格式擇一：`3 / 5 組`、`68%`、`已完成`。
  final String label;
  final double value;
  final String? trailingLabel;
  const AppProgress({
    super.key,
    required this.value,
    required this.label,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: T.body())),
          if (trailingLabel != null) Text(trailingLabel!, style: T.numberS()),
        ],
      ),
      const SizedBox(height: S.sm),
      ClipRRect(
        borderRadius: BorderRadius.circular(R.inset),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: kAnimProgress,
          curve: Curves.easeOut,
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: Sz.progressHeight,
            backgroundColor: C.lineTrack,
            valueColor: const AlwaysStoppedAnimation(C.statusSuccess),
          ),
        ),
      ),
    ],
  );
}

/// 只有一條軌道、由呼叫端自行負責旁邊的文字（用於已含數值的複合版面）。
class BareProgress extends StatelessWidget {
  final double value;
  final Color color;
  const BareProgress({
    super.key,
    required this.value,
    this.color = C.statusSuccess,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(R.inset),
    child: LinearProgressIndicator(
      value: value.clamp(0.0, 1.0),
      minHeight: Sz.progressHeight,
      backgroundColor: C.lineTrack,
      valueColor: AlwaysStoppedAnimation(color),
    ),
  );
}

// ---------------------------------------------------------------------------
// 統計卡（§8.17）
// ---------------------------------------------------------------------------

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: T.caption(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: S.xs),
        ValueUnit(value: value, unit: unit, style: T.numberM()),
      ],
    ),
  );
}

/// 卡片內的統計欄位（不自帶卡片外框）。
class StatField extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const StatField({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: T.caption(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: S.xs),
      ValueUnit(value: value, unit: unit, style: T.numberM()),
    ],
  );
}

// ---------------------------------------------------------------------------
// 徽章／標籤（§8.14）
// ---------------------------------------------------------------------------

class TagBadge extends StatelessWidget {
  final String text;
  final Color? borderColor;
  final Color? fill;

  /// 不填色時的字色。空值時沿用 `C.textSecondary`。
  ///
  /// **2026-09-29 新增。** 在此之前只有邊框上得了色，而只染邊框在一排
  /// 徽章裡幾乎看不出來 —— 課表卡片上「符合我的那一個」就是這樣從頭到尾
  /// 沒有被看見過（見 `Pill` 的說明）。
  final Color? textColor;

  const TagBadge(this.text,
      {super.key, this.borderColor, this.fill, this.textColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: 2),
    decoration: BoxDecoration(
      color: fill ?? Colors.transparent,
      borderRadius: BorderRadius.circular(R.child),
      border: Border.all(color: borderColor ?? C.lineDivider),
    ),
    child: Text(
      text,
      // 填色可能是深藍也可能是橘黃，前景依實測對比擇一 ——
      // 一律用墨字會讓深底徽章整個看不見。
      style: T.caption(
          color: fill != null
              ? C.onFill(fill!)
              : (textColor ?? C.textSecondary)),
    ),
  );
}

/// 數字徽章（未讀數）：圓形，最小 20×20，底 status/error、字 text/on-dark。
class CountBadge extends StatelessWidget {
  final int count;
  const CountBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: const BoxDecoration(
      color: C.statusError,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      count > 99 ? '99+' : '$count',
      style: T.caption(color: C.textOnDark),
    ),
  );
}

// ---------------------------------------------------------------------------
// 開關（§8.15）
// ---------------------------------------------------------------------------

/// 核取方塊。開關切換的是「設定」，核取確認的是「這一件事」——
/// 兩者語意不同，故不共用 [AppSwitch]。
///
/// 方塊本身 24×24，外面補到 44×44 的可點區（【必須】≥ 44）。
class AppCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppCheckbox({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onChanged == null ? null : () => onChanged!(!value),
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: Sz.tapTarget,
      height: Sz.tapTarget,
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: value ? C.actionOutline : Colors.transparent,
            borderRadius: BorderRadius.circular(R.child),
            border: Border.all(
              color: onChanged == null
                  ? C.textDisabled
                  : (value ? C.actionOutline : C.lineDivider),
              width: 2,
            ),
          ),
          child: value
              ? Icon(Icons.check, size: 16, color: C.onFill(C.actionOutline))
              : null,
        ),
      ),
    ),
  );
}

class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const AppSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: kAnim,
      width: Sz.switchW,
      height: Sz.switchH,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        // 位置 ＋ 明度兩種訊號
        color: value ? C.actionOutline : C.lineDivider,
        borderRadius: BorderRadius.circular(R.switchTrack),
      ),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: C.bgSurface,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// 選項卡片（§8.8）
// ---------------------------------------------------------------------------

class OptionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;

  /// 單選＝圓形底＋勾；多選＝方形底＋勾。
  final bool multiSelect;
  final VoidCallback onTap;
  const OptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.multiSelect = false,
  });

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      AppCard(
        onTap: onTap,
        // 選中＝2px action/outline，不用顏色區分
        borderColor: selected ? C.actionOutline : C.lineDivider,
        borderWidth: selected ? 2 : 1,
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.xl + S.base,
          S.base,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: subtitle == null ? 24 : 0),
              child: Text(title, style: T.body(weight: FontWeight.w600)),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: S.xs),
              Text(subtitle!, style: T.caption()),
            ],
          ],
        ),
      ),
      if (selected)
        Positioned(
          top: S.md,
          right: S.md,
          child: Container(
            width: Sz.iconDense,
            height: Sz.iconDense,
            decoration: BoxDecoration(
              color: C.actionOutline,
              shape: multiSelect ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: multiSelect ? BorderRadius.circular(R.inset) : null,
            ),
            child: const Icon(Icons.check, size: 14, color: C.textOnDark),
          ),
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// 分頁籤（§8.13）
// ---------------------------------------------------------------------------

class AppTabBar extends StatelessWidget {
  final List<String> tabs;
  final bool scrollable;
  const AppTabBar({super.key, required this.tabs, this.scrollable = false});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: C.bgSurface,
      border: Border(bottom: BorderSide(color: C.lineDivider)),
    ),
    child: TabBar(
      isScrollable: scrollable || tabs.length > 4,
      tabAlignment: (scrollable || tabs.length > 4) ? TabAlignment.start : null,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(width: 2, color: C.actionOutline),
      ),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelColor: C.textPrimary,
      unselectedLabelColor: C.textSecondary,
      labelStyle: T.body(weight: FontWeight.w600),
      unselectedLabelStyle: T.body(),
      overlayColor: WidgetStateProperty.all(C.press),
      tabs: [for (final t in tabs) Tab(height: Sz.tapTarget, text: t)],
    ),
  );
}

// ---------------------------------------------------------------------------
// 等級徽章（§4.1a）
// ---------------------------------------------------------------------------

/// 等級徽章 —— 全 App 呈現能力等級的唯一元件。
///
/// 【必須】字母永遠與顏色同時出現。等級色階的色盲分離為 5.0，
/// 低於 6.0 底線，**字母是這個豁免成立的唯一條件**，不得只留顏色。
///
/// 對 bg/page 對比不足 3.0 的階（目前為 B）自動補 1px 細框，
/// 否則色塊本身的邊界看不出來。
class GradeBadge extends StatelessWidget {
  final String grade;
  final bool large;
  const GradeBadge(this.grade, {super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    final fill = C.gradeFill(grade);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? S.md : S.sm,
        vertical: large ? 3 : 1,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(R.child),
        border: C.gradeNeedsOutline(grade)
            ? Border.all(color: C.lineDivider)
            : null,
      ),
      child: Text(
        grade,
        style: large
            ? T.numberM(color: C.gradeOn(grade))
            : T.numberS(color: C.gradeOn(grade)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 價目卡（§8.18）—— 整排一個
// ---------------------------------------------------------------------------

/// 金幣面額與 AI 點數不是商品，是價目表。
///
/// 不用兩欄格狀：只有「數量 ＋ 贈送 ＋ 價格」三個純文字欄位、沒有圖片，
/// 塞進半個版面會留一大片空白，且價格無法橫向對齊比較。
/// 整排一個之後，各面額的價格全部靠右對齊，一眼就能比價。
class PriceCard extends StatelessWidget {
  final String icon;
  final String title;
  final String? subtitle;
  final String price;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  const PriceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.price,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    borderColor: selected ? C.actionOutline : C.lineDivider,
    borderWidth: selected ? 2 : 1,
    // 選中時內距 15 ＋ 2px 邊框，維持總寬不變
    padding: EdgeInsets.all(selected ? S.base - 1 : S.base),
    child: Row(
      children: [
        // 圖示方塊 56 × 56，圓角 12
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: C.bgPage,
            borderRadius: BorderRadius.circular(R.control),
          ),
          alignment: Alignment.center,
          child: Text(icon, style: const TextStyle(fontSize: 26)),
        ),
        const SizedBox(width: S.base),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: T.h3(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: S.sm),
                    TagBadge(badge!, borderColor: C.accentInfo),
                  ],
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: T.caption()),
              ],
            ],
          ),
        ),
        const SizedBox(width: S.md),
        // 價格靠右，Number-S
        Text(price, style: T.numberS()),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// 空狀態（§8.5）
// ---------------------------------------------------------------------------

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final AppButton? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: C.textSecondary),
          const SizedBox(height: S.lg),
          Text(title, style: T.h3(), textAlign: TextAlign.center),
          const SizedBox(height: S.sm),
          Text(
            message,
            style: T.body(color: C.textSecondary),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          if (action != null) ...[
            const SizedBox(height: S.lg),
            // 【必須】行動按鈕寬度依內容，最小 120（§8.5）——
            // 拉滿整列會讓它看起來像頁面的主 CTA。
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120),
              child: IntrinsicWidth(child: action!),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 小節標題
class SectionTitle extends StatelessWidget {
  final String text;
  final String? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: S.lg, bottom: S.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(text, style: T.h3())),
        // 補充說明的長度不受控（「當前 143　距下一門檻還差 107」），
        // 放不下時截斷，不要爆版。標題至少留得住一半寬度。
        if (trailing != null)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: S.sm),
              child: Text(
                trailing!,
                style: T.caption(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ),
      ],
    ),
  );
}

/// 搜尋框。動作庫與訓練歷史的動作趨勢共用 —— 兩處的行為完全一樣。
class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const SearchField({super.key, required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: T.body(),
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: T.body(color: C.textDisabled),
      prefixIcon: const Icon(
        Icons.search_rounded,
        size: Sz.iconDense,
        color: C.textSecondary,
      ),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.close_rounded, size: Sz.iconDense),
              color: C.textSecondary,
              onPressed: () => controller.clear(),
            ),
      filled: true,
      fillColor: C.bgSurface,
      contentPadding: const EdgeInsets.symmetric(vertical: S.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.control),
        borderSide: const BorderSide(color: C.lineDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.control),
        borderSide: const BorderSide(color: C.lineDivider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.control),
        borderSide: const BorderSide(color: C.actionOutline, width: 2),
      ),
    ),
  );
}
