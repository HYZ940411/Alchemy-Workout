import 'package:flutter/material.dart';

import '../../domain/registration.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// 簽到畫面一併詢問的兩個週期更新。
///
/// 兩者**都不是簽到的 Precondition**：跳過仍可正常簽到。
/// 若跳過即無法簽到，連續簽到天數會因此中斷 —— 該代價遠大於一筆資料；
/// 且強迫回報體重對有飲食失調傾向的使用者構成實際傷害。
class PeriodicAskCards extends StatelessWidget {
  const PeriodicAskCards({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Column(
      children: [
        if (s.weightAskDue) ...[
          const _WeightAsk(),
          const SizedBox(height: S.md),
        ],
        if (s.surveyAskDue) ...[
          const _SurveyAsk(),
          const SizedBox(height: S.md),
        ],
      ],
    );
  }
}

/// 距上次填入體重滿 14 天。週期以「距上次填入滿 14 天」逐使用者計算，
/// 非全站對齊的雙週一 —— 各使用者的詢問時點自然分散。
class _WeightAsk extends StatefulWidget {
  const _WeightAsk();
  @override
  State<_WeightAsk> createState() => _WeightAskState();
}

class _WeightAskState extends State<_WeightAsk> {
  late final TextEditingController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = TextEditingController();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('順便更新體重？', style: T.h3()),
          const SizedBox(height: S.xs),
          Text(
            '上次填的是 ${s.weightText(s.bodyweightKg)}。'
            '體重會影響能力值換算與徒手動作的代入重量。',
            style: T.caption(),
          ),
          const SizedBox(height: S.md),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: T.body(),
            decoration: InputDecoration(
              isDense: true,
              hintText: s.bodyweightKg.toStringAsFixed(1),
              suffixText: 'kg',
              filled: true,
              fillColor: C.bgPage,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
                borderSide: const BorderSide(color: C.lineDivider),
              ),
            ),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '更新',
                  onPressed: () {
                    final v = double.tryParse(ctrl.text.trim());
                    if (v == null || v < 20 || v > 300) {
                      showToast(context, '請填 20–300 之間的體重');
                      return;
                    }
                    s.updateWeight(v);
                    showToast(context, '已更新體重');
                  },
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: AppButton(
                  label: '這次跳過',
                  kind: BtnKind.secondary,
                  onPressed: s.skipWeightAsk,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text('跳過不影響簽到，沿用上次的值，這一輪不再問。', style: T.caption()),
        ],
      ),
    );
  }
}

/// 距上次填寫滿 90 天：每週健身天數、每次健身時長、健身目標、健身經驗。
/// 四者不若體重會週週變動，一年詢問 4 次不致構成騷擾。
class _SurveyAsk extends StatefulWidget {
  const _SurveyAsk();
  @override
  State<_SurveyAsk> createState() => _SurveyAskState();
}

class _SurveyAskState extends State<_SurveyAsk> {
  int? days;
  String? duration;
  String? goal;
  String? experience;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    days ??= s.daysPerWeek;
    duration ??= s.duration;
    goal ??= s.commonGoal;
    experience ??= s.experience;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('這三個月，練法有變嗎？', style: T.h3()),
          const SizedBox(height: S.xs),
          Text('改了任何一項，系統會立刻重新推薦並換掉你的當前計畫。'
              '進行中的訓練不受影響。', style: T.caption()),
          const SizedBox(height: S.md),
          _Field(
            label: '每週健身天數',
            options: const ['1', '2', '3', '4', '5', '6', '7'],
            value: days?.toString(),
            onPick: (v) => setState(() => days = int.parse(v)),
          ),
          _Field(
            label: '每次健身時長',
            options: kDurations,
            value: duration,
            onPick: (v) => setState(() => duration = v),
          ),
          _Field(
            label: '健身目標',
            options: kCommonGoals,
            value: goal,
            onPick: (v) => setState(() => goal = v),
          ),
          _Field(
            label: '健身經驗',
            options: kExperience,
            value: experience,
            onPick: (v) => setState(() => experience = v),
          ),
          const SizedBox(height: S.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '更新',
                  onPressed: () {
                    s.updateSurvey(
                      daysPerWeek: days,
                      duration: duration,
                      commonGoal: goal,
                      experience: experience,
                    );
                    showToast(context,
                        '已更新，當前計畫換成「${s.currentPlan?.name ?? '—'}」');
                  },
                ),
              ),
              const SizedBox(width: S.md),
              Expanded(
                child: AppButton(
                  label: '這次跳過',
                  kind: BtnKind.secondary,
                  onPressed: s.skipSurveyAsk,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text('跳過不影響簽到，沿用原值，這一輪不再問。', style: T.caption()),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String> onPick;
  const _Field({
    required this.label,
    required this.options,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: T.caption()),
            const SizedBox(height: S.sm),
            Wrap(
              spacing: S.sm,
              runSpacing: S.sm,
              children: [
                for (final o in options)
                  _Chip(label: o, selected: o == value, onTap: () => onPick(o)),
              ],
            ),
          ],
        ),
      );
}

/// 選項籤。§4.4：選取態為 2px 外框，不靠改底色 ——
/// 改底色在深淺主題下各需一組對比可過的顏色，外框只需一個。
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sz.tapTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: S.md),
          decoration: BoxDecoration(
            color: C.bgSurface,
            borderRadius: BorderRadius.circular(R.control),
            border: Border.all(
              color: selected ? C.actionOutline : C.lineDivider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: T.body(
              color: selected ? C.actionOutline : C.textPrimary,
              weight: selected ? FontWeight.w700 : null,
            ),
          ),
        ),
      );
}
