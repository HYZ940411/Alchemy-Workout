import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/models.dart';
import '../../mock/exercise_guides.dart';
import '../../mock/mock_exercise_stats.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 動作詳情 —— 合併兩個 Read Model 對「單一動作」的視角：
/// 〈動作庫〉的每筆項目欄位（名稱、所需器材、示範內容、累積練習次數），
/// 與〈訓練歷史〉動作趨勢檢視的「該動作歷來的重量與次數 ＋ 重量對時間的折線圖」。
///
/// 折線圖對全體使用者開放 —— 依〈免費看點，會員看線〉，
/// 單一動作的資料屬「看自己的紀錄」，付費牆放在跨時間的彙總分析。
class ExerciseDetailScreen extends StatelessWidget {
  final Exercise exercise;
  const ExerciseDetailScreen({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final stat = statOf(exercise.id);
    final rest = s.restSecondsFor(
      PlanExercise(exercise: exercise, planned: const []),
    );

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        backgroundColor: C.bgPage,
        surfaceTintColor: Colors.transparent,
        title: Text(exercise.name, style: T.h3()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.scrollBottom),
        children: [
          const _DemoBlock(),
          if (exercise.isCustom) ...[
            const SizedBox(height: S.md),
            const TagBadge('本動作不計入能力值',
                borderColor: C.statusWarning, fill: C.bgSurface),
          ],
          const SizedBox(height: S.md),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: StatField(
                    label: '主要肌群',
                    value: exercise.dim == null
                        ? '—'
                        : dimNames[exercise.dim]!,
                  ),
                ),
                Expanded(
                  child: StatField(
                    label: '累積練習',
                    value: '${stat.count}',
                    unit: '次',
                  ),
                ),
                Expanded(
                  child: StatField(
                    label: '預設休息',
                    value: '$rest',
                    unit: '秒',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.md),
          ListGroup(rows: [
            ListRow(
              title: '訓練部位',
              subtitle: exercise.parts.length > 1
                  ? '能力值只計入主要肌群，其餘部位供分頁與篩選'
                  : null,
              trailing: Text(
                exercise.tabs.isEmpty
                    ? '—'
                    : exercise.tabs.map((d) => dimNames[d]!).join('、'),
                style: T.body(color: C.textSecondary),
              ),
            ),
            ListRow(title: '所需器材', trailing: Text(exercise.equipment, style: T.body(color: C.textSecondary))),
            ListRow(
              title: '徒手動作',
              subtitle: exercise.isBodyweight
                  ? '估算 1RM 時以「體重 ＋ 負重」計算'
                  : null,
              trailing: Text(exercise.isBodyweight ? '是' : '否',
                  style: T.body(color: C.textSecondary)),
            ),
          ]),
          const SizedBox(height: S.lg),
          _GuideSection(exerciseId: exercise.id),
          const SectionTitle('重量走勢'),
          if (stat.trend.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.show_chart_rounded,
                title: '還沒有這個動作的紀錄',
                message: '練過一次之後，這裡會出現重量對時間的走勢，供你決定該不該加重。',
              ),
            )
          else ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('重量對時間', style: T.caption()),
                  const SizedBox(height: S.md),
                  SizedBox(
                    height: 170,
                    child: CustomPaint(
                      painter: TrendPainter(stat.trend),
                      size: Size.infinite,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.lg),
            const SectionTitle('逐次紀錄'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, p) in stat.trend.reversed.indexed)
                    _TrendRow(
                      point: p,
                      previous: _previousOf(stat.trend, p),
                      showDivider: i < stat.trend.length - 1,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.md),
        ],
      ),
    );
  }

  static TrendPoint? _previousOf(List<TrendPoint> all, TrendPoint p) {
    final i = all.indexOf(p);
    return i > 0 ? all[i - 1] : null;
  }
}

/// 動作說明 —— 準備工作 / 動作要領 / 關鍵提示，來自匯入的資料庫。
/// 資產延遲載入，沒有這一筆就整段不出現（自建動作即無）。
class _GuideSection extends StatelessWidget {
  final String exerciseId;
  const _GuideSection({required this.exerciseId});

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, ExerciseGuide>>(
        future: loadGuides(),
        builder: (context, snap) {
          final g = snap.data?[exerciseId];
          if (g == null || g.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('動作說明'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (g.setup.isNotEmpty) _Part(title: '準備工作', body: g.setup),
                    if (g.howto.isNotEmpty) _Part(title: '動作要領', body: g.howto),
                    if (g.tips.isNotEmpty) _Part(title: '關鍵提示', body: g.tips),
                  ],
                ),
              ),
              const SizedBox(height: S.lg),
            ],
          );
        },
      );
}

class _Part extends StatelessWidget {
  final String title;
  final String body;
  const _Part({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: T.caption()),
            const SizedBox(height: S.xs),
            Text(body, style: T.body(color: C.textSecondary)),
          ],
        ),
      );
}

/// 示範內容 —— 動作庫的每筆項目欄位之一。Demo 以佔位塊呈現。
class _DemoBlock extends StatelessWidget {
  const _DemoBlock();

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: C.skeletonBase,
            borderRadius: BorderRadius.circular(R.card),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.play_circle_outline,
                  size: 40, color: C.textSecondary),
              const SizedBox(height: S.sm),
              Text('示範內容', style: T.caption()),
            ],
          ),
        ),
      );
}

class _TrendRow extends StatelessWidget {
  final TrendPoint point;
  final TrendPoint? previous;
  final bool showDivider;
  const _TrendRow({
    required this.point,
    required this.previous,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final delta = previous == null ? 0.0 : point.weight - previous!.weight;
    final s = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.base, vertical: S.md),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: C.lineDivider))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(point.date, style: T.caption()),
          ),
          Text(s.loadText(point.weight), style: T.numberS()),
          const SizedBox(width: S.sm),
          // 375 寬時「62.5 kg × 12 下 ＋2.5」剛好差 2px —— 讓次數吸收剩餘空間。
          Expanded(
            child: Text('× ${point.reps} 下',
                style: T.body(color: C.textSecondary)),
          ),
          if (delta > 0)
            Text('＋${_kg(delta)}',
                style: T.caption(color: C.statusSuccess)
                    .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// 重量對時間的折線圖。§8.20 未將折線圖列入「不抽成共用元件」的四樣，
/// 故留在本檔供動作詳情使用；目前也只有這裡用得到。
class TrendPainter extends CustomPainter {
  final List<TrendPoint> data;
  const TrendPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const padL = 36.0, padB = 22.0, padT = 8.0, padR = 8.0;
    final w = size.width - padL - padR;
    final h = size.height - padB - padT;

    final ws = data.map((e) => e.weight).toList();
    var lo = (ws.reduce(math.min) - 5).floorToDouble();
    var hi = (ws.reduce(math.max) + 5).ceilToDouble();
    if (hi == lo) hi = lo + 1;

    Offset at(int i) => Offset(
          padL + (data.length == 1 ? w / 2 : w * i / (data.length - 1)),
          padT + h - h * ((ws[i] - lo) / (hi - lo)),
        );

    // 格線與刻度 —— 座標軸為背景，維持低調。
    final grid = Paint()
      ..color = C.lineDivider
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var k = 0; k <= 3; k++) {
      final y = padT + h * k / 3;
      canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), grid);
      tp.text = TextSpan(
        text: (hi - (hi - lo) * k / 3).round().toString(),
        style: T.caption(color: C.textDisabled).copyWith(fontSize: 10),
      );
      tp.layout();
      tp.paint(canvas, Offset(padL - tp.width - 6, y - tp.height / 2));
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < data.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = C.accentDeep,
    );

    for (var i = 0; i < data.length; i++) {
      final o = at(i);
      // 底色描邊讓點在折線上仍看得出是獨立的一次紀錄。
      canvas.drawCircle(o, 4.5, Paint()..color = C.bgSurface);
      canvas.drawCircle(o, 3, Paint()..color = C.accentDeep);
    }

    // 只標頭尾兩個日期 —— 全部標會擠在一起。
    for (final i in {0, data.length - 1}) {
      tp.text = TextSpan(
        text: data[i].date,
        style: T.caption(color: C.textDisabled).copyWith(fontSize: 10),
      );
      tp.layout();
      final x = (at(i).dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(covariant TrendPainter old) => old.data != data;
}
