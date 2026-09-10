import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// 內建圖庫
///
/// 商品與貼文的「圖片」欄位在模型裡是圖片集合。真機上這裡會接系統相簿，
/// 但本專案零外部套件、也不打包點陣圖 —— 故以一組**程式繪製**的圖片代替：
/// 每張圖是「符號 ＋ 專屬底色」，有 ID、能被選取、能被儲存、能被畫出來。
/// 它是相簿的替身，不是佔位符：選了就真的存進 Aggregate，畫面也真的變了。
class AppImage {
  final String id;
  final String label;
  final String glyph;
  final String group;

  /// 底色的色相（0–360）。同一張圖永遠是同一個顏色。
  final double hue;

  const AppImage({
    required this.id,
    required this.label,
    required this.glyph,
    required this.group,
    required this.hue,
  });
}

const kImageLibrary = <AppImage>[
  AppImage(id: 'im_tee', label: '訓練上衣', glyph: '👕', group: '商品', hue: 210),
  AppImage(id: 'im_strap', label: '助力帶', glyph: '🧤', group: '商品', hue: 28),
  AppImage(id: 'im_shaker', label: '搖搖杯', glyph: '🥤', group: '商品', hue: 168),
  AppImage(id: 'im_bottle', label: '水壺', glyph: '🍶', group: '商品', hue: 196),
  AppImage(id: 'im_ticket', label: '補簽券', glyph: '🎫', group: '虛擬', hue: 46),
  AppImage(id: 'im_plan', label: '訓練計畫', glyph: '📋', group: '虛擬', hue: 262),
  AppImage(id: 'im_badge', label: '徽章', glyph: '🏅', group: '虛擬', hue: 38),
  AppImage(id: 'im_barbell', label: '槓鈴', glyph: '🏋️', group: '訓練', hue: 220),
  AppImage(id: 'im_dumbbell', label: '啞鈴', glyph: '💪', group: '訓練', hue: 8),
  AppImage(id: 'im_run', label: '有氧', glyph: '🏃', group: '訓練', hue: 140),
  AppImage(id: 'im_chart', label: '數據', glyph: '📈', group: '訓練', hue: 186),
  AppImage(id: 'im_fire', label: '連續達成', glyph: '🔥', group: '訓練', hue: 16),
];

AppImage? imageOf(String id) {
  for (final i in kImageLibrary) {
    if (i.id == id) return i;
  }
  return null;
}

/// 一張圖。找不到 ID 時畫成破圖，而非默默留白 ——
/// 圖片被刪掉是要看得出來的。
class AppImageView extends StatelessWidget {
  final String id;
  final double size;
  final double radius;

  /// 寬度。空值為正方形（寬 ＝ [size]）。
  /// 兩欄格狀的商品圖為滿欄寬 × 固定高，非正方形。
  final double? width;

  const AppImageView({
    super.key,
    required this.id,
    this.size = 64,
    this.radius = R.child,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final img = imageOf(id);
    if (img == null) {
      return Container(
        width: width ?? size,
        height: size,
        decoration: BoxDecoration(
          color: C.bgPage,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: C.lineDivider),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined,
            size: Sz.iconDense, color: C.textSecondary),
      );
    }
    final base = HSLColor.fromAHSL(1, img.hue, 0.42, 0.90).toColor();
    final deep = HSLColor.fromAHSL(1, img.hue, 0.38, 0.76).toColor();
    return Container(
      width: width ?? size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, deep],
        ),
      ),
      alignment: Alignment.center,
      child: Text(img.glyph, style: TextStyle(fontSize: size * 0.44)),
    );
  }
}

/// 圖片列。空集合時呈現「尚未加入圖片」，不留下一塊看不出意義的空白。
class AppImageStrip extends StatelessWidget {
  final List<String> ids;
  final double size;
  final void Function(String id)? onRemove;
  const AppImageStrip({
    super.key,
    required this.ids,
    this.size = 64,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return Text('尚未加入圖片', style: T.caption());
    }
    return Wrap(
      spacing: S.md,
      runSpacing: S.md,
      children: [
        for (final id in ids)
          Stack(
            clipBehavior: Clip.none,
            children: [
              AppImageView(id: id, size: size),
              if (onRemove != null)
                Positioned(
                  top: -6,
                  right: -6,
                  child: GestureDetector(
                    onTap: () => onRemove!(id),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: C.bgSurface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded,
                          size: 14, color: C.textSecondary),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
