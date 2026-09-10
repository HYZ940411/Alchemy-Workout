import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// 底部導覽列（§7、§8.4）
///
/// 內容區高 60、總高 94（＝60 ＋ 安全區 34）、五格等分。
/// 中間「訓練」為 44px 填滿圓，**不突出**、**無下方文字**。
/// 【必須】選中態不得用 action/primary 表示（橘黃圖示在白底僅 2.03:1）。
class AppTabBarBottom extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const AppTabBarBottom({super.key, required this.index, required this.onTap});

  static const items = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home, '首頁'),
    (Icons.forum_outlined, Icons.forum, '社群'),
    (Icons.fitness_center, Icons.fitness_center, '訓練'), // 中央
    (Icons.storefront_outlined, Icons.storefront, '商店'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: C.bgSurface,
        // §5.8 浮動元件以頂部 1px 分隔線表達層次
        border: Border(top: BorderSide(color: C.lineDivider)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: Sz.tabBarContent,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: i == 2
                    ? _TrainButton(active: index == i, onTap: () => onTap(i))
                    : _Cell(
                        icon: index == i ? items[i].$2 : items[i].$1,
                        label: items[i].$3,
                        active: index == i,
                        onTap: () => onTap(i),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Cell({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 上留白 8 ＋ 圖示 24 ＋ 間距 4 ＋ 文字 16 → 結束於 52
    final color = active ? C.navActive : C.navInactive;
    return InkWell(
      onTap: onTap,
      highlightColor: C.press,
      splashColor: C.press,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: S.sm),
          Icon(icon, size: Sz.iconDefault, color: color),
          const SizedBox(height: S.xs),
          Text(
            label,
            style: T.caption(color: color).copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
        ],
      ),
    );
  }
}

/// 中間「訓練」鍵：圓形直徑 44、action/primary 填滿、圖示 text/on-accent、無文字。
/// 【必須】不得放大圓形，也不得讓它突出導覽列 ——
/// 44 是唯一能讓它與其他四格齊平（皆結束於 52）的直徑。
class _TrainButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _TrainButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: S.sm),
          Material(
            color: C.actionPrimary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              highlightColor: C.press,
              splashColor: C.press,
              child: const SizedBox(
                width: Sz.trainButtonDiameter,
                height: Sz.trainButtonDiameter,
                child: Icon(Icons.fitness_center,
                    size: Sz.iconDefault, color: C.textOnAccent),
              ),
            ),
          ),
        ],
      );
}
