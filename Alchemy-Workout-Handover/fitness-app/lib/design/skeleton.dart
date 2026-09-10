import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// 骨架屏（§8.6）
///
/// 骨架形狀必須貼近真實內容的排版（R-18）：形狀差太多的話，
/// 載入完成時版面會大幅跳動，體感比轉圈更差。**故六種型態不共用同一份骨架。**
///
/// 掃光為由左至右、1.5 秒、linear、亮光寬約 30%，底 `skeleton/base`、
/// 亮 `skeleton/shine`（明度差 0.122）。動畫用重複播放的 AnimationController，
/// 因此**顯示骨架的畫面不可用 `pumpAndSettle`**，測試請用 `pump(duration)`。

const _shinePeriod = Duration(milliseconds: 1500);

/// 掃光。一頁共用一個控制器，六個型態都包在它底下。
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: _shinePeriod)..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            // 亮光寬度約骨架寬度的 30%；等速自左掃至右。
            final w = rect.width;
            final x = (c.value * (w * 1.6)) - w * 0.3;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                C.skeletonBase,
                C.skeletonShine,
                C.skeletonBase,
              ],
              stops: [
                ((x - w * 0.15) / w).clamp(0.0, 1.0),
                (x / w).clamp(0.0, 1.0),
                ((x + w * 0.15) / w).clamp(0.0, 1.0),
              ],
            ).createShader(rect);
          },
          child: child,
        ),
        child: widget.child,
      );
}

/// 文字條。內文 12／標題 16／輔助 8，圓角 4（[R.inset]）。
class SkeletonBar extends StatelessWidget {
  final double height;
  final double widthFactor;
  const SkeletonBar({super.key, this.height = 12, this.widthFactor = 1});

  const SkeletonBar.title({super.key, this.widthFactor = 0.6}) : height = 16;
  const SkeletonBar.body({super.key, this.widthFactor = 1}) : height = 12;
  const SkeletonBar.caption({super.key, this.widthFactor = 0.4}) : height = 8;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: C.skeletonBase,
            borderRadius: BorderRadius.circular(R.inset),
          ),
        ),
      );
}

class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, this.size = Sz.avatarList});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: C.skeletonBase,
          shape: BoxShape.circle,
        ),
      );
}

/// 圖片／卡片方塊。圓角比照該處元件。
class SkeletonBox extends StatelessWidget {
  final double? height;
  final double? width;
  final double radius;
  final double? aspectRatio;
  const SkeletonBox({
    super.key,
    this.height,
    this.width,
    this.radius = R.child,
    this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: C.skeletonBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    return aspectRatio == null
        ? box
        : AspectRatio(aspectRatio: aspectRatio!, child: box);
  }
}

/// 六種型態（§8.6）。段落的最後一條寬 60%，模擬段落結尾。
enum SkeletonKind { listA, cardListB, gridC, chatD, detailE, chartF }

const skeletonKindNames = <SkeletonKind, String>{
  SkeletonKind.listA: 'A 清單型',
  SkeletonKind.cardListB: 'B 卡片列表型',
  SkeletonKind.gridC: 'C 卡片格狀型',
  SkeletonKind.chatD: 'D 對話型',
  SkeletonKind.detailE: 'E 詳情型',
  SkeletonKind.chartF: 'F 圖表型',
};

/// 依型態畫出骨架。[rows] 為顯示列數 —— 規格要求「依該頁首屏可見的列數，
/// 不多不少」，故由呼叫端指定，不給一個放諸四海的預設值。
class Skeleton extends StatelessWidget {
  final SkeletonKind kind;
  final int rows;
  const Skeleton({super.key, required this.kind, required this.rows});

  @override
  Widget build(BuildContext context) => Shimmer(
        child: switch (kind) {
          SkeletonKind.listA => _ListA(rows: rows),
          SkeletonKind.cardListB => _CardListB(rows: rows),
          SkeletonKind.gridC => _GridC(rows: rows),
          SkeletonKind.chatD => _ChatD(rows: rows),
          SkeletonKind.detailE => _DetailE(rows: rows),
          SkeletonKind.chartF => _ChartF(rows: rows),
        },
      );
}

/// A 清單型：頭像圓 32 ＋ 兩行條（12／8）。
class _ListA extends StatelessWidget {
  final int rows;
  const _ListA({required this.rows});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < rows; i++)
            Container(
              height: Sz.listRowDouble,
              padding: const EdgeInsets.symmetric(horizontal: S.base),
              decoration: BoxDecoration(
                color: C.bgSurface,
                border: i == rows - 1
                    ? null
                    : const Border(bottom: BorderSide(color: C.lineDivider)),
              ),
              child: Row(
                children: [
                  const SkeletonCircle(),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        SkeletonBar.body(widthFactor: 0.7),
                        SizedBox(height: S.sm),
                        SkeletonBar.caption(widthFactor: 0.45),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

/// B 卡片列表型：16:9 圖 ＋ 標題條 16 ＋ 副標條 12 ＋ 標籤。
class _CardListB extends StatelessWidget {
  final int rows;
  const _CardListB({required this.rows});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < rows; i++)
            Container(
              margin: const EdgeInsets.only(bottom: S.md),
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: C.bgSurface,
                borderRadius: BorderRadius.circular(R.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(aspectRatio: 16 / 9),
                  SizedBox(height: S.md),
                  SkeletonBar.title(widthFactor: 0.7),
                  SizedBox(height: S.sm),
                  SkeletonBar.body(widthFactor: 0.9),
                  SizedBox(height: S.sm),
                  Row(children: [
                    SizedBox(width: 56, child: SkeletonBar(height: 20)),
                    SizedBox(width: S.sm),
                    SizedBox(width: 48, child: SkeletonBar(height: 20)),
                  ]),
                ],
              ),
            ),
        ],
      );
}

/// C 卡片格狀型：**兩欄**方塊 92 高 ＋ 兩行條。
class _GridC extends StatelessWidget {
  final int rows; // 列數，一列兩張
  const _GridC({required this.rows});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: Row(
                children: [
                  for (var j = 0; j < 2; j++) ...[
                    if (j > 0) const SizedBox(width: S.md),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(S.md),
                        decoration: BoxDecoration(
                          color: C.bgSurface,
                          borderRadius: BorderRadius.circular(R.card),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBox(height: 92),
                            SizedBox(height: S.md),
                            SkeletonBar.body(widthFactor: 0.8),
                            SizedBox(height: S.sm),
                            SkeletonBar.caption(widthFactor: 0.5),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
}

/// D 對話型：泡泡左右交錯。
class _ChatD extends StatelessWidget {
  final int rows;
  const _ChatD({required this.rows});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: Row(
                mainAxisAlignment: i.isEven
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.end,
                children: [
                  if (i.isEven) ...[
                    const SkeletonCircle(size: 28),
                    const SizedBox(width: S.sm),
                  ],
                  SkeletonBox(
                    width: i.isEven ? 220 : 160,
                    height: 56 - (i % 3) * 8,
                    radius: R.card,
                  ),
                ],
              ),
            ),
        ],
      );
}

/// E 詳情型：大圖 184 ＋ 段落條 ＋ 清單條。詳情頁一定有資料，故無空狀態。
class _DetailE extends StatelessWidget {
  final int rows; // 大圖下方的清單列數
  const _DetailE({required this.rows});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 184, radius: R.card),
          const SizedBox(height: S.base),
          const SkeletonBar.title(widthFactor: 0.55),
          const SizedBox(height: S.md),
          const SkeletonBar.body(),
          const SizedBox(height: S.sm),
          const SkeletonBar.body(),
          const SizedBox(height: S.sm),
          // 段落最後一條 60%，模擬段落結尾。
          const SkeletonBar.body(widthFactor: 0.6),
          const SizedBox(height: S.lg),
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBar.body(widthFactor: 0.8),
                  SizedBox(height: S.sm),
                  SkeletonBar.caption(widthFactor: 0.35),
                ],
              ),
            ),
        ],
      );
}

/// F 圖表型：六邊形實心 ＋ 數值列。新使用者有初始值，故無空狀態。
class _ChartF extends StatelessWidget {
  final int rows; // 數值列數
  const _ChartF({required this.rows});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SkeletonBox(height: 44, radius: R.control),
          const SizedBox(height: S.lg),
          const SizedBox(
            height: 200,
            child: Center(
              child: CustomPaint(
                size: Size(200, 200),
                painter: _HexPainter(),
              ),
            ),
          ),
          const SizedBox(height: S.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: S.base),
            decoration: BoxDecoration(
              color: C.bgSurface,
              borderRadius: BorderRadius.circular(R.card),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows; i++)
                  Container(
                    height: Sz.listRowSingle,
                    decoration: i == rows - 1
                        ? null
                        : const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: C.lineDivider))),
                    child: Row(
                      children: const [
                        SizedBox(width: 72, child: SkeletonBar.body()),
                        Spacer(),
                        SizedBox(width: 56, child: SkeletonBar.body()),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}

class _HexPainter extends CustomPainter {
  const _HexPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      // 自正上方起算，每 60 度一個頂點 —— 與雷達圖的六維同構。
      final a = -1.5707963 + i * 1.0471976;
      final p = Offset(c.dx + r * _cos(a), c.dy + r * _sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = C.skeletonBase);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

double _cos(double x) => math.cos(x);
double _sin(double x) => math.sin(x);
