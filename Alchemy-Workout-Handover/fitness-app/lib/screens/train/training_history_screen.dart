import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/exercise_stats.dart';
import '../../mock/mock_data.dart';
import '../../mock/mock_extra.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'exercise_detail_screen.dart';
import 'history_detail_screen.dart';

/// Read Model：訓練歷史 —— 兩種檢視並存。
/// 訓練清單回答「我上週練了什麼」；動作趨勢回答「該不該加重」。
class TrainingHistoryScreen extends StatelessWidget {
  const TrainingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            surfaceTintColor: Colors.transparent,
            title: const Text('訓練歷史',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            bottom: const TabBar(
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textDim,
              labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: [Tab(text: '訓練清單'), Tab(text: '動作趨勢')],
            ),
          ),
          body: const TabBarView(children: [_WorkoutList(), _ExerciseTrend()]),
        ),
      );
}

// ---------------------------------------------------------------------------
// 檢視一：訓練清單 —— 以一次訓練為單位
// ---------------------------------------------------------------------------

class _WorkoutList extends StatelessWidget {
  const _WorkoutList();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
      children: [
        for (final h in s.history) _HistoryCard(entry: h),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(R.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.card),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => HistoryDetailScreen(entry: entry),
              )),
              child: Padding(
                padding: const EdgeInsets.all(S.base),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.planName, style: T.h3()),
                          const SizedBox(height: S.xs),
                          Text(
                            '${entry.date.month}/${entry.date.day}　'
                            // 【必須】總訓練量四捨五入至整數呈現。
                            '總訓練量 ${entry.volume.round()} kg　'
                            '${entry.minutes} 分　約 ${entry.calories} 大卡',
                            style: T.caption(),
                          ),
                          const SizedBox(height: S.xs),
                          Text(
                            '${entry.exercises.length} 動作 · ${entry.totalSets} 組',
                            style: T.caption(color: C.textDisabled),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// 檢視二：動作趨勢 —— 以一個動作為單位
// ---------------------------------------------------------------------------

class _ExerciseTrend extends StatefulWidget {
  const _ExerciseTrend();

  @override
  State<_ExerciseTrend> createState() => _ExerciseTrendState();
}

class _ExerciseTrendState extends State<_ExerciseTrend> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 統計由訓練紀錄即時推導，這裡取一次就好 ——
    // 每一列各取一次等於把整份訓練紀錄掃 527 遍。
    final stats = AppScope.of(context).exerciseStats;
    int countOf(String id) => stats[id]?.count ?? 0;
    // 預設排序為累積練習次數由多到少。沒練過的動作照樣列出
    // （搜尋涵蓋整個動作庫），只是累積 0 次、沒有走勢。
    final all = [...kAllExercises]
      ..sort((a, b) => countOf(b.id).compareTo(countOf(a.id)));
    final q = _search.text.trim();
    // 名稱搜尋涵蓋平台動作庫與自建動作。
    final items = q.isEmpty
        ? all
        : all.where((e) => e.name.contains(q)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SearchField(
            controller: _search,
            hint: '搜尋動作名稱',
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(S.base),
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '找不到這個動作',
                    message: '搜尋涵蓋平台動作庫與自建動作，換個關鍵字試試。',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
                  children: [
                    for (final e in items)
                      _TrendRow(
                        exercise: e,
                        stat: stats[e.id] ?? const ExerciseStat(count: 0),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TrendRow extends StatelessWidget {
  final Exercise exercise;
  final ExerciseStat stat;
  const _TrendRow({required this.exercise, required this.stat});

  @override
  Widget build(BuildContext context) {
    final last = stat.trend.isEmpty ? null : stat.trend.last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(R.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.card),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ExerciseDetailScreen(exercise: exercise),
            )),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercise.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          last == null
                              ? '尚無紀錄　·　累積 ${stat.count} 次'
                              : '上次 ${_kg(last.weight)} kg × ${last.reps} 下'
                                  '　·　累積 ${stat.count} 次',
                          style: const TextStyle(
                              color: AppColors.textFaint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textFaint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
