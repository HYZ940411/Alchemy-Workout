import 'package:flutter/material.dart';
import 'tokens.dart';

/// 字級與行高（§2.2）
///
/// 【必須】下列 10 級為固定值，不得使用區間，不得手動調整字級。
/// 字級全部不重複：12／15／16／17／18／20／24／28／32／64。
/// 行高全部是 4 的倍數，與間距系統對得齊。
class T {
  static const _f = 'NotoSansTC';

  static TextStyle _s(double size, double lineHeight, FontWeight w,
          {Color? color}) =>
      TextStyle(
        fontFamily: _f,
        fontSize: size,
        height: lineHeight / size,
        fontWeight: w,
        color: color ?? C.textPrimary,
        // 數字一律等寬，避免跳動
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle h1({Color? color}) => _s(28, 40, FontWeight.w700, color: color);
  static TextStyle h2({Color? color}) => _s(20, 28, FontWeight.w700, color: color);

  /// 【必須】H3 為 17px 是為了避開 Button 的 16px，不得為求整齊改回 16。
  static TextStyle h3({Color? color}) => _s(17, 24, FontWeight.w600, color: color);

  static TextStyle body({Color? color, FontWeight? weight}) =>
      _s(15, 24, weight ?? FontWeight.w400, color: color);
  static TextStyle button({Color? color}) => _s(16, 24, FontWeight.w600, color: color);

  /// 【必須】Caption 的行高比例為 1.33，僅供單行使用，不得用於多行段落。
  static TextStyle caption({Color? color}) =>
      _s(12, 16, FontWeight.w400, color: color ?? C.textSecondary);

  static TextStyle numberL({Color? color}) => _s(32, 36, FontWeight.w700, color: color);
  static TextStyle numberM({Color? color}) => _s(24, 28, FontWeight.w700, color: color);
  static TextStyle numberS({Color? color}) => _s(18, 24, FontWeight.w700, color: color);

  /// 【必須】Display 僅用於全屏倒數（組間休息）。全 App 唯一例外。
  static TextStyle display({Color? color}) => _s(64, 72, FontWeight.w700, color: color);
}

/// 數值與單位的間距 —— 全 App 通則（§8.19）
///
/// 【必須】數值與其單位之間固定 4px，一律用間距屬性控制，不得用空白字元。
class ValueUnit extends StatelessWidget {
  final String value;
  final String? unit;
  final TextStyle style;
  final TextStyle? unitStyle;
  final CrossAxisAlignment align;
  const ValueUnit({
    super.key,
    required this.value,
    required this.style,
    this.unit,
    this.unitStyle,
    this.align = CrossAxisAlignment.baseline,
  });

  @override
  Widget build(BuildContext context) {
    if (unit == null) return Text(value, style: style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: style),
        const SizedBox(width: S.xs), // 固定 4px
        // 單位放不下時截斷。數值本身永遠完整 —— 截掉數值等於騙人，
        // 截掉單位只是少一個「/ 100」的分母。
        Flexible(
          child: Text(
            unit!,
            style: unitStyle ?? T.caption(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
