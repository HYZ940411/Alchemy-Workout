import 'package:flutter/material.dart';

import '../domain/ability.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/radar_chart.dart';

/// Read Model：六維能力值雷達圖
/// 「現在」維度為即時；歷史維度為日粒度（來自能力值日快照）。
class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final pts = s.displayedPoints;
    final overall = overallPoints(pts);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
      children: [
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          child: Column(
            children: [
              // 時間維度：使用者於圖表上方切換
              _TimeSwitch(
                options: s.snapshotOptions,
                current: s.snapshotDaysAgo,
                onChanged: s.setSnapshot,
              ),
              const SizedBox(height: 12),
              Center(
                // §8.12【必須】單一輪廓 —— 不畫對照輪廓
                child: RadarChart(points: pts),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('綜合能力等級　',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  Text(
                    overallGrade(pts),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                      height: 1,
                    ),
                  ),
                  Text('　$overall 點',
                      style: const TextStyle(
                          color: AppColors.textFaint, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        const SectionLabel('各維明細'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < Dim.values.length; i++)
                _DimRow(dim: Dim.values[i], points: pts[Dim.values[i]]!),
            ],
          ),
        ),
        const SectionLabel('耐力值'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < Dim.values.length; i++)
                    _EnduranceChip(
                      name: dimNames[Dim.values[i]]!,
                      value: _endurance(pts[Dim.values[i]]!, i),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 耐力值為衍生值，由組紀錄與該動作的歷史最佳估算 1RM 即時計算。
  /// 此處為假資料；換算為與能力值同一尺度（0–999），故可套用同一組六階門檻。
  static int? _endurance(int pts, int i) {
    if (pts <= kInitialPoints + 5) return null; // 無可靠最佳 1RM 者不推測
    return (pts * (0.72 + (i % 3) * 0.11)).round().clamp(0, kMaxPoints);
  }
}

class _TimeSwitch extends StatelessWidget {
  /// 可選的檔位，值為快照的**實際**年齡（天）。0 為現在。
  ///
  /// 寫死 30／90 是不行的：快照的鍵會隨著日子往前漂，查不到就退回現在，
  /// 於是三個檔位長得一模一樣。標籤跟著資料走。
  final List<int> options;
  final int current;
  final ValueChanged<int> onChanged;
  const _TimeSwitch({
    required this.options,
    required this.current,
    required this.onChanged,
  });

  static String _label(int daysAgo) => daysAgo == 0 ? '現在' : '$daysAgo 天前';

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            for (final v in options)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: current == v ? AppColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _label(v),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: current == v ? AppColors.onAccent : AppColors.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _DimRow extends StatelessWidget {
  final Dim dim;
  final int points;
  const _DimRow({required this.dim, required this.points});

  @override
  Widget build(BuildContext context) {
    final np = nodeProgressOf(points);
    final node = nodeOf(points);
    // 顏色依等級，不依部位
    final color = C.gradeFill(node.major);
    final within = node.upper > node.lower
        ? (points - node.lower) / (node.upper - node.lower)
        : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 34,
                child: Text(dimNames[dim]!,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Text(
                node.label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                '$points',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Text(' 點',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          ProgressBar(value: within, color: color, height: 5),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              np.display,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnduranceChip extends StatelessWidget {
  final String name;
  final int? value;
  const _EnduranceChip({required this.name, this.value});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final grade = v == null ? null : majorGradeOf(v);
    return Container(
      width: (MediaQuery.of(context).size.width - 32 - 32 - 20) / 3,
      padding: const EdgeInsets.symmetric(vertical: S.md),
      decoration: BoxDecoration(
        color: C.bgPage,
        borderRadius: BorderRadius.circular(R.child),
      ),
      child: Column(
        children: [
          Text(name, style: T.caption()),
          const SizedBox(height: S.xs),
          if (grade == null)
            // 無可靠最佳 1RM 者呈現為「—」，不以 0 表示（模型明訂）
            Text('—', style: T.numberS(color: C.textSecondary))
          else
            GradeBadge(grade),
          const SizedBox(height: S.xs),
          Text(v == null ? '' : '$v', style: T.caption()),
        ],
      ),
    );
  }
}
