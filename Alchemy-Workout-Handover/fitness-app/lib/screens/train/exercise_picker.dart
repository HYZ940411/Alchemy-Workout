import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/models.dart';
import '../../mock/mock_equipment.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/equipment_filter.dart';

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


class _ExercisePicker extends StatefulWidget {
  final List<Exercise> myExercises;
  final bool allowCreate;
  const _ExercisePicker({required this.myExercises, required this.allowCreate});

  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  final _search = TextEditingController();

  /// 器材篩選。空集合代表不篩。
  ///
  /// **預設不篩，與動作庫刻意不同。**
  ///
  /// 動作庫預設帶入使用者的持有器材明細，那是個瀏覽介面 ——
  /// 要回答的是「我做得到什麼」。這裡是個動作介面，藏起一個選項的代價
  /// 高得多：第一版我照動作庫的做法預設帶入可用器材，
  /// 結果自訂課表編輯器裡的「划船機」直接消失（既有測試當場紅掉）——
  /// 而編輯課表的人可能正在為別的場地寫課表。
  ///
  /// 「有篩選可以用」不等於「預設就篩掉一半」。要篩的人按一下就有。
  ///
  /// 使用者按「可用器材」那顆時取 `equipmentForFiltering`，
  /// 它已經把「本次訓練已解鎖器材」算進去了 ——
  /// 解鎖了卻還被自己的設定擋住，等於沒解鎖。
  final Set<String> _equipment = {};

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
    final s = AppScope.of(context);
    final owned = _equipment;
    final q = _search.text.trim();

    // 判準與器材篩選條都取自共用的那一份（`exerciseMatchesFilter`
    // 與 `EquipmentFilterBar`）—— 動作庫與這裡篩出來的結果必須一致，
    // 各寫一份遲早有一邊漏掉新規則。
    List<Exercise> pick(List<Exercise> src) => src
        .where((e) => exerciseMatchesFilter(
            (name: e.name, equipment: e.equipment),
            owned: owned,
            query: q))
        .toList();

    final groups = <String, List<Exercise>>{
      for (final d in Dim.values)
        dimNames[d]!:
            pick(s.platformExercises.where((e) => e.dim == d).toList()),
      '有氧': pick(s.cardioExercises),
      '我的動作': pick(widget.myExercises),
    };
    final nothing = groups.values.every((v) => v.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.allowCreate) ...[
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
        SearchField(controller: _search, hint: '搜尋動作名稱'),
        const SizedBox(height: S.md),
        EquipmentFilterBar(
          selected: owned,
          onToggle: (item) => setState(() {
            owned.contains(item) ? owned.remove(item) : owned.add(item);
          }),
          onClear: owned.isEmpty ? null : () => setState(owned.clear),
        ),
        const SizedBox(height: S.sm),
        // 一鍵帶入自己的器材。預設不篩（見 [_equipment]），但「只看我做得到
        // 的」是最常見的那一次篩選 —— 逐顆點八個品項才做得到，太貴。
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: '只看我的器材做得到的',
            kind: BtnKind.secondary,
            icon: Icons.check_circle_outline_rounded,
            onPressed: () => setState(() {
              owned
                ..clear()
                ..addAll(s.equipmentForFiltering);
            }),
          ),
        ),
        const SizedBox(height: S.base),
        // 篩到沒有東西剩下時要說得出來 —— 一片空白看起來像動作庫壞了。
        if (nothing)
          AppCard(
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: '沒有符合的動作',
              message: '換個關鍵字，或放寬器材篩選。',
              action: AppButton(
                label: '清除篩選',
                kind: BtnKind.secondary,
                onPressed: () => setState(() {
                  _search.clear();
                  owned.clear();
                }),
              ),
            ),
          ),
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

