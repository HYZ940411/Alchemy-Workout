import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/models.dart';
import '../../mock/mock_data.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 挑到這一項代表「先去建一個新動作」——
/// 呼叫端負責導去建立自訂動作頁，本抽屜不認識那一頁。
const kCreateNewExerciseId = '__create__';

/// 動作選擇抽屜。自訂訓練編輯與訓練進行中「加入動作」共用同一個 ——
/// 兩者要選的東西完全一樣。
Future<Exercise?> pickExercise(
  BuildContext context, {
  required List<Exercise> myExercises,
  bool allowCreate = true,
}) =>
    showAppSheet<Exercise>(
      context,
      title: '加入動作',
      child: _ExercisePicker(
        myExercises: myExercises,
        allowCreate: allowCreate,
      ),
    );


class _ExercisePicker extends StatelessWidget {
  final List<Exercise> myExercises;
  final bool allowCreate;
  const _ExercisePicker({required this.myExercises, required this.allowCreate});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final groups = <String, List<Exercise>>{
      for (final d in Dim.values)
        dimNames[d]!: s.platformExercises.where((e) => e.dim == d).toList(),
      '有氧': kCardioExercises,
      '我的動作': myExercises,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allowCreate) ...[
          AppButton(
            label: '建立新的自訂動作',
            kind: BtnKind.secondary,
            icon: Icons.add_rounded,
            onPressed: () => Navigator.of(context).pop(
              const Exercise(
                  id: kCreateNewExerciseId,
                  name: '',
                  dim: null,
                  relativeIntensity: 0),
            ),
          ),
          const SizedBox(height: S.lg),
        ],
        for (final entry in groups.entries) ...[
          if (entry.value.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: S.sm),
              child: Text(entry.key, style: T.caption()),
            ),
            Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                for (final e in entry.value)
                  ActionChip(
                    label: Text(e.name, style: T.body()),
                    backgroundColor: C.bgSurface,
                    side: const BorderSide(color: C.lineDivider),
                    onPressed: () => Navigator.of(context).pop(e),
                  ),
              ],
            ),
            const SizedBox(height: S.base),
          ],
        ],
      ],
    );
  }
}

