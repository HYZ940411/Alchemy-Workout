import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../domain/ability.dart';

/// 雷達圖（UI 設計規格書 §8.12）
///
/// 正六邊形、直徑 240px、刻度網格 3 圈、**單一輪廓**、**中央留空**。
/// 軸標籤在六個軸的外圍，格式「肌群名 ＋ 等級」，Caption 12／16。
/// 綜合能力等級放在圖表上方（本元件之外），不放中央 ——
/// 能力值低者輪廓小，中央正是輪廓最密集處，數字會疊在一起。
class RadarChart extends StatelessWidget {
  final Map<Dim, int> points;
  final double diameter;
  const RadarChart({super.key, required this.points, this.diameter = 240});

  @override
  Widget build(BuildContext context) {
    // 直徑 240 置中於 361 內容區，左右各留 60px 給軸標籤 ＝ 360px。
    // 但 375 最窄機型的內容區只有 343px，故依可用寬度縮小，
    // 以符合 §1.1【必須】在 375 下不爆版。
    const labelGutter = 60.0;
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : diameter + labelGutter * 2;
        final d = math.min(diameter, maxW - labelGutter * 2);
        return SizedBox(
          width: d + labelGutter * 2,
          height: d + labelGutter,
          child: CustomPaint(painter: _RadarPainter(points, d)),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  final Map<Dim, int> points;
  final double diameter;
  _RadarPainter(this.points, this.diameter);

  Offset _pt(Offset c, double r, int i) {
    final a = -math.pi / 2 + i * math.pi / 3;
    return Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
  }

  Path _hex(Offset c, double radius, List<double> ratios) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final o = _pt(c, radius * ratios[i].clamp(0.0, 1.0), i);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;

    // 刻度網格：3 圈，line/divider
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.lineDivider;
    for (final f in [1 / 3, 2 / 3, 1.0]) {
      canvas.drawPath(_hex(c, radius, List.filled(6, f)), grid);
    }
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(c, _pt(c, radius, i), grid);
    }

    final ratios =
        Dim.values.map((d) => (points[d] ?? kInitialPoints) / kMaxPoints).toList();

    // 單一輪廓，顏色取**綜合能力等級**的色階（§4.1a）
    final overall = C.gradeFill(overallGrade(points));
    final path = _hex(c, radius, ratios);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = overall.withValues(alpha: 0.26),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = overall,
    );

    // 頂點依**該維自己的等級**著色（輪廓維持單一色，§8.12）
    for (var i = 0; i < 6; i++) {
      final d = Dim.values[i];
      final o = _pt(c, radius * ratios[i].clamp(0.0, 1.0), i);
      canvas.drawCircle(o, 5.5, Paint()..color = C.bgSurface);
      canvas.drawCircle(
          o, 4, Paint()..color = C.gradeFill(majorGradeOf(points[d] ?? kInitialPoints)));
    }

    // 軸標籤：「肌群名 ＋ 等級」，例：胸 A
    for (var i = 0; i < 6; i++) {
      final d = Dim.values[i];
      final p = points[d] ?? kInitialPoints;
      final tp = TextPainter(
        text: TextSpan(
          text: '${dimNames[d]} ${majorGradeOf(p)}',
          // 軸標籤維持墨色 —— 色階的淺階（E/D）當文字對比不足，
          // 等級由該軸的頂點顏色與標籤上的字母共同表達
          style: T.caption(color: C.textPrimary)
              .copyWith(fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final anchor = _pt(c, radius + 20, i);
      tp.paint(canvas, anchor - Offset(tp.width / 2, tp.height / 2));
    }
    // 中央留空 —— 不畫任何東西
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.points != points;
}
