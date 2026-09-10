import 'package:flutter/material.dart';

import 'design/tokens.dart';
import 'design/typography.dart';

export 'design/tokens.dart';

/// 舊畫面沿用的名稱，一律轉接到語意色票（UI 設計規格書 §4.1）。
/// 【必須】畫面不直接寫色碼 —— 這裡是唯一的對照層。
class AppColors {
  static const bg = C.bgPage;
  static const surface = C.bgSurface;
  static const surfaceAlt = C.bgPage;
  static const line = C.lineDivider;

  static const text = C.textPrimary;
  static const textDim = C.textSecondary;
  static const textFaint = C.textSecondary;

  static const accent = C.actionPrimary;
  static const accentSoft = C.actionOutline;
  static const onAccent = C.textOnAccent;

  static const gold = C.actionPrimary;
  static const goldSoft = C.actionPrimary;
  static const bronze = C.statusError;

  /// v0.8：資訊回歸中性色（§4.2 復原）。
  static const blue = C.accentInfo;
  static const blueSoft = C.accentInfo;
  static const cool = C.accentInfo;

  static const hot = C.actionPrimary;
  static const warn = C.actionPrimary;
  static const ok = C.statusSuccess;

  /// v0.6：六維不再依部位配色，改依**等級**配色（§4.1a 等級色階）。
  /// 舊的 dims 已移除；呼叫端改用 C.gradeFill(majorGradeOf(points))。

  static const cardShadow = C.shadow;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    surface: C.bgSurface,
    primary: C.actionPrimary,
    secondary: C.actionOutline,
    onPrimary: C.textOnAccent,
    onSurface: C.textPrimary,
    error: C.statusError,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bgPage,
    fontFamily: 'NotoSansTC',
    textTheme: TextTheme(
      displayLarge: T.display(),
      headlineLarge: T.h1(),
      headlineMedium: T.h2(),
      titleMedium: T.h3(),
      bodyMedium: T.body(),
      bodySmall: T.caption(),
      labelLarge: T.button(),
    ),
    dividerColor: C.lineDivider,
    dividerTheme: const DividerThemeData(
      color: C.lineDivider,
      thickness: 1,
      space: 1,
    ),
    // §8.3 所有可點擊元件的感應範圍一律 ≥ 44×44
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    highlightColor: C.press,
    appBarTheme: AppBarTheme(
      backgroundColor: C.bgSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true, // §8.3 標題水平與垂直皆置中
      toolbarHeight: Sz.navBarHeight,
      titleTextStyle: T.h3(),
      iconTheme: const IconThemeData(color: C.textPrimary, size: Sz.iconDense),
      shape: const Border(bottom: BorderSide(color: C.lineDivider)),
    ),
  );
}
