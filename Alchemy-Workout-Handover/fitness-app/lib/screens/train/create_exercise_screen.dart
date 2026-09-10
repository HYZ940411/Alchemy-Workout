import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/models.dart';
import '../../mock/mock_equipment.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 建立自訂動作 —— Command「建立自訂動作」，Actor：使用者。
///
/// 三條 Postcondition 決定了這頁的定位：
/// 自建動作**僅建立者本人可選用、不進入平台動作庫、不計入能力值計算**。
///
/// 必填規則與平台動作庫不同：所屬肌群**必填**（理由不是能力值歸屬，
/// 而是動作庫的依肌群篩選與訓練歷史的部位統計 —— 留空會變成無法歸類的孤兒項）；
/// 所需器材**選填**（自建動作不參與推薦比對，留空無後果）。
class CreateExerciseScreen extends StatefulWidget {
  const CreateExerciseScreen({super.key});

  @override
  State<CreateExerciseScreen> createState() => _CreateExerciseScreenState();
}

class _CreateExerciseScreenState extends State<CreateExerciseScreen> {
  final _name = TextEditingController();
  ExerciseType _type = ExerciseType.strength;
  Dim? _dim;
  final Set<String> _equipment = {};
  int _restSeconds = 90;
  double _met = 7.0;
  bool _bodyweight = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_name.text.trim().isEmpty) return false;
    // 所屬肌群必填；動作類型為有氧者為空值，不需填。
    if (_type == ExerciseType.strength && _dim == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final venues = venuesFor(_equipment);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        backgroundColor: C.bgPage,
        surfaceTintColor: Colors.transparent,
        title: Text('建立自訂動作', style: T.h3()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.scrollBottom),
        children: [
          const SectionTitle('名稱'),
          AppCard(
            child: TextField(
              controller: _name,
              style: T.body(),
              maxLength: 20,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                counterText: '',
                hintText: '例：彈力帶側走',
                hintStyle: T.body(color: C.textDisabled),
              ),
            ),
          ),
          const SizedBox(height: S.lg),
          const SectionTitle('動作類型'),
          Row(
            children: [
              for (final t in ExerciseType.values) ...[
                Expanded(
                  child: OptionCard(
                    title: exerciseTypeNames[t]!,
                    subtitle: t == ExerciseType.cardio
                        ? '不進六維能力值'
                        : '依所屬肌群提升該維',
                    selected: _type == t,
                    onTap: () => setState(() {
                      _type = t;
                      // 動作類型為有氧者，所屬肌群為空值。
                      if (t == ExerciseType.cardio) _dim = null;
                      if (t == ExerciseType.cardio) _bodyweight = false;
                    }),
                  ),
                ),
                if (t != ExerciseType.values.last) const SizedBox(width: S.md),
              ],
            ],
          ),
          if (_type == ExerciseType.strength) ...[
            const SizedBox(height: S.lg),
            const SectionTitle('所屬肌群', trailing: '必填'),
            Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                for (final d in Dim.values)
                  _Choice(
                    label: dimNames[d]!,
                    selected: _dim == d,
                    onTap: () => setState(() => _dim = d),
                  ),
              ],
            ),
            const SizedBox(height: S.md),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text('徒手動作（以自身體重為負荷）', style: T.body()),
                  ),
                  AppSwitch(
                    value: _bodyweight,
                    onChanged: (v) => setState(() => _bodyweight = v),
                  ),
                ],
              ),
            ),
          ],
          if (_type == ExerciseType.cardio) ...[
            const SizedBox(height: S.lg),
            const SectionTitle('MET 值', trailing: '有氧必填'),
            AppCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('供估算消耗大卡', style: T.body()),
                      ),
                      Text(_met.toStringAsFixed(1), style: T.numberS()),
                    ],
                  ),
                  Slider(
                    value: _met,
                    min: 2,
                    max: 16,
                    divisions: 28,
                    activeColor: C.actionOutline,
                    onChanged: (v) => setState(() => _met = v),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.lg),
          const SectionTitle('所需器材', trailing: '選填，可留空'),
          Wrap(
            spacing: S.sm,
            runSpacing: S.sm,
            children: [
              for (final item in kEquipmentVenues.keys)
                _Choice(
                  label: item,
                  selected: _equipment.contains(item),
                  onTap: () => setState(() {
                    _equipment.contains(item)
                        ? _equipment.remove(item)
                        : _equipment.add(item);
                  }),
                ),
            ],
          ),
          const SizedBox(height: S.md),
          _VenueCard(equipment: _equipment, venues: venues),
          const SizedBox(height: S.lg),
          const SectionTitle('預設組間休息'),
          AppCard(
            child: _SecondsStepper(
              seconds: _restSeconds,
              step: 15,
              min: 15,
              max: 600,
              onChanged: (v) => setState(() => _restSeconds = v),
            ),
          ),
          const SizedBox(height: S.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: Sz.iconDense, color: C.textSecondary),
                    const SizedBox(width: S.sm),
                    Text('建立後', style: T.body(weight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: S.sm),
                Text(
                  '這個動作只有你看得到，不會進入平台動作庫，'
                  '且練它不會提升六維能力值。',
                  style: T.body(color: C.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      // CTA 固定在底部：停用狀態就是這張表單的驗證回饋，
      // 埋在捲動區最底等於使用者看不到自己為什麼不能送出。
      bottomNavigationBar: _BottomBar(
        child: AppButton(
          label: '建立動作',
          onPressed: _canSave ? () => _save(context) : null,
        ),
      ),
    );
  }

  void _save(BuildContext context) {
    final created = Exercise(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      dim: _dim,
      type: _type,
      relativeIntensity: 0,
      isBodyweight: _bodyweight,
      isCustom: true,
      equipment: _equipment.isEmpty ? '不限' : _equipment.join('、'),
      defaultRestSeconds: _restSeconds,
    );
    Navigator.of(context).pop(created);
  }
}

/// 底部固定的動作列。上緣 1px 分隔線標出它與捲動區的分界。
class _BottomBar extends StatelessWidget {
  final Widget child;
  const _BottomBar({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: C.bgPage,
          border: Border(top: BorderSide(color: C.lineDivider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
            // AppButton 內部是 alignment: center 的 Container —— 收到寬鬆約束
            // 會撐滿可用高度。底部列的約束正是寬鬆的，故須自行收緊。
            child: Column(mainAxisSize: MainAxisSize.min, children: [child]),
          ),
        ),
      );
}

/// 可練場所為衍生值，由所需器材明細推導，**不儲存**。
/// 建立動作時只填器材，不需自行判斷該動作算健身房或居家。
class _VenueCard extends StatelessWidget {
  final Set<String> equipment;
  final Set<String> venues;
  const _VenueCard({required this.equipment, required this.venues});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.place_outlined,
                size: Sz.iconDense, color: C.textSecondary),
            const SizedBox(width: S.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('可練場所', style: T.body(weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    equipment.isEmpty
                        ? '未選器材 —— 這個動作不參與器材比對，'
                            '於動作庫依器材篩選時不會出現。'
                        : venues.isEmpty
                            ? '所選器材沒有共同的場所。'
                            : venues.join(' / '),
                    style: T.caption(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? C.actionOutline : C.bgSurface,
        borderRadius: BorderRadius.circular(R.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.control),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: Sz.tapTarget),
            padding: const EdgeInsets.symmetric(horizontal: S.base),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.control),
              border: Border.all(
                color: selected ? C.actionOutline : C.lineDivider,
              ),
            ),
            child: Text(
              label,
              style: T.body(color: selected ? C.textOnDark : C.textPrimary),
            ),
          ),
        ),
      );
}

/// 秒數步進器。數值寬度固定，避免 100 → 90 時整行左右跳動。
class _SecondsStepper extends StatelessWidget {
  final int seconds;
  final int step;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _SecondsStepper({
    required this.seconds,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _Btn(
            icon: Icons.remove_rounded,
            onTap: seconds - step >= min ? () => onChanged(seconds - step) : null,
          ),
          Expanded(
            child: Center(
              child: Text('$seconds 秒', style: T.numberS()),
            ),
          ),
          _Btn(
            icon: Icons.add_rounded,
            onTap: seconds + step <= max ? () => onChanged(seconds + step) : null,
          ),
        ],
      );
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _Btn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: Sz.tapTarget,
        height: Sz.tapTarget,
        child: Material(
          color: C.bgPage,
          borderRadius: BorderRadius.circular(R.child),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.child),
            onTap: onTap,
            child: Icon(
              icon,
              size: Sz.iconDense,
              color: onTap == null ? C.textDisabled : C.textPrimary,
            ),
          ),
        ),
      );
}
