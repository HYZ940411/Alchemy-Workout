import 'package:flutter/material.dart';

import '../../mock/mock_extra.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 訓練紀錄詳情 —— 〈Read Model：訓練歷史〉訓練清單檢視的「點入可看該次各動作各組明細」。
///
/// 兩條規則決定了這頁**不呈現**什麼：
/// 明細**排除已取消的組紀錄**（不實體刪除，但回顧時不呈現取消痕跡）；
/// **不含終止方式**（完成 / 提前結束 / 逾時中斷三者於回顧時皆不呈現）。
class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;
  const HistoryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        backgroundColor: C.bgPage,
        surfaceTintColor: Colors.transparent,
        title: Text(entry.planName, style: T.h3()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.scrollBottom),
        children: [
          Text(_fullDate(entry.date), style: T.body(color: C.textSecondary)),
          const SizedBox(height: S.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 總訓練量是一次訓練的頭條數字，且四位數在 393 寬與另兩欄
                // 並排會爆版（Number-M 放不下）—— 獨立一行。
                StatField(
                  label: '總訓練量',
                  // 【必須】四捨五入至整數呈現。
                  value: s.volumeDisplay(entry.volume).$1,
                  unit: s.volumeDisplay(entry.volume).$2,
                ),
                const SizedBox(height: S.md),
                const Divider(height: 1, color: C.lineDivider),
                const SizedBox(height: S.md),
                Row(
                  children: [
                    Expanded(
                      child: StatField(
                        label: '訓練時長',
                        value: '${entry.minutes}',
                        unit: '分',
                      ),
                    ),
                    Expanded(
                      child: StatField(
                        label: '消耗',
                        value: '${entry.calories}',
                        unit: '大卡',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: S.lg),
          SectionTitle('各動作各組明細　${entry.exercises.length} 動作 · '
              '${entry.totalSets} 組'),
          for (final e in entry.exercises) ...[
            _ExerciseBlock(exercise: e),
            const SizedBox(height: S.md),
          ],
          const SizedBox(height: S.xs),
          Builder(
            builder: (context) => AppButton(
              label: '另存為自訂訓練',
              kind: BtnKind.secondary,
              icon: Icons.bookmark_add_outlined,
              onPressed: () {
                final s = AppScope.of(context);
                final ok = s.saveHistoryAsPlan(entry);
                showToast(
                  context,
                  ok
                      ? '已另存為「${entry.planName}」，狀態為已儲存 —— 發布後才能選用'
                      : '自訂訓練名額已滿，請先刪除一份再試',
                );
              },
            ),
          ),
          const SizedBox(height: S.md),
        ],
      ),
    );
  }

  static String _fullDate(DateTime d) {
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return '${d.year} 年 ${d.month} 月 ${d.day} 日（${week[d.weekday - 1]}）';
  }
}

class _ExerciseBlock extends StatelessWidget {
  final HistoryExercise exercise;
  const _ExerciseBlock({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.sm),
              child: Row(
                children: [
                  Expanded(child: Text(exercise.name, style: T.h3())),
                  Text(
                    exercise.isTimed
                        ? '${exercise.sets.length} 組'
                        : '${exercise.sets.length} 組 · '
                            '${s.volumeDisplay(exercise.volume).$1} '
                            '${s.volumeDisplay(exercise.volume).$2}',
                    style: T.caption(),
                  ),
                ],
              ),
            ),
            for (final (i, set) in exercise.sets.indexed)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.base, vertical: S.sm),
                decoration: BoxDecoration(
                  border: i < exercise.sets.length - 1
                      ? const Border(bottom: BorderSide(color: C.lineDivider))
                      : null,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('第 ${i + 1} 組', style: T.caption()),
                    ),
                    Text(
                      exercise.isTimed
                          ? '${set.$2} 秒'
                          : '${s.loadText(set.$1)} × ${set.$2} 下',
                      style: T.body(),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: S.sm),
          ],
        ),
    );
  }
}
