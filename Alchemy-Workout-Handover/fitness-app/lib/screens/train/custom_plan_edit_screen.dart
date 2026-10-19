import 'package:flutter/material.dart';

import '../../domain/custom_plan.dart';
import '../../domain/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/added_load_switch.dart';
import '../../widgets/common.dart';
import 'create_exercise_screen.dart';
import 'exercise_picker.dart';

/// 課表內容的第三層 —— **多型**。
/// 重訓填目標重量與目標次數；有氧只填目標時長，無重量、無次數、亦不設目標強度。
class DraftSet {
  double weight;
  int reps;
  int seconds;

  /// 徒手動作打開了「外加負重」。重量為 0 的徒手動作預設鎖著不給調。
  bool loadOpen;
  DraftSet({
    this.weight = 20,
    this.reps = 10,
    this.seconds = 300,
    this.loadOpen = false,
  });
}

/// 第二層：該動作的組數。組數對有氧同樣適用，通常為 1，間歇會做多組。
class DraftExercise {
  final Exercise exercise;
  final List<DraftSet> sets;
  DraftExercise(this.exercise, this.sets);

  bool get isCardio => exercise.type == ExerciseType.cardio;
}

/// 儲存後回傳給管理頁的結果。草稿 → 已儲存；已儲存為**未啟用**狀態，
/// 不出現於課表選擇頁，不可選用於訓練 —— 要能練得先「發布」。
///
/// 回傳的是**課表內容本身**，不是「幾個動作」：自訂訓練與訓練計畫的
/// 課表內容結構完全一致，而它的用途就是拿來練。
typedef SavedPlan = ({String name, List<PlanExercise> exercises});

/// 自訂訓練編輯 —— 課表內容為三層結構：
/// 動作清單 → 該動作的組數 → 每組的目標重量與目標次數。
///
/// 每一組可各自設定不同的目標重量，不強制整個動作共用同一重量。
class CustomPlanEditScreen extends StatefulWidget {
  /// 要修改的既有課表；空值為新建。
  final CustomPlan? initial;
  const CustomPlanEditScreen({super.key, this.initial});

  @override
  State<CustomPlanEditScreen> createState() => _CustomPlanEditScreenState();
}

class _CustomPlanEditScreenState extends State<CustomPlanEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  final List<DraftExercise> _items = [];

  /// 使用者自建的動作 —— 本頁建立後即可立刻選用。
  /// 我的動作取自狀態，不是 const 清單 —— 在別處建立的動作，這裡也要挑得到。
  late final List<Exercise> _myExercises = [...AppScope.of(context).myExercises];

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    // 修改既有課表：帶出**原內容**。讀不回原內容的話，
    // 使用者只是改個名字，存回去就把整份課表洗掉了。
    for (final pe in widget.initial?.exercises ?? const <PlanExercise>[]) {
      _items.add(DraftExercise(pe.exercise, [
        for (final st in pe.planned)
          if (pe.exercise.type == ExerciseType.cardio)
            DraftSet(weight: 0, reps: 1, seconds: st.targetReps)
          else
            DraftSet(weight: st.targetWeight, reps: st.targetReps),
      ]));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty && _items.isNotEmpty;

  /// 正在修改的是一份**已公開**的課表。
  bool get _editingPublic => widget.initial?.state == CustomPlanState.public;

  /// 儲存。**已公開的課表修改前要先確認** —— 一修改（連改名都算）就會重新送審，
  /// 審核期間別人看不到它。以前沒有任何警告：使用者把已公開的課表改了名字，
  /// 它就從全站消失了，而他不知道（2026-10-17 使用者測 Z5 時踩到）。
  Future<void> _save() async {
    if (_editingPublic) {
      final ok = await showAppDialog(
        context,
        title: '修改後需要重新審核',
        message: '這份課表已經公開。修改後會重新送審，審核期間其他人暫時看不到它，'
            '通過後才會再公開。要繼續嗎？',
        confirmLabel: '繼續修改',
        cancelLabel: '先不要',
      );
      if (ok != true || !mounted) return;
    }
    Navigator.of(context).pop((name: _name.text.trim(), exercises: _toPlan()));
  }

  /// 草稿轉為課表內容。有氧的目標時長借用 [PlannedSet.targetReps] 承載，
  /// 與課表選擇頁、訓練頁的既有慣例一致，不另立一種表示法。
  List<PlanExercise> _toPlan() => [
        for (final it in _items)
          PlanExercise(
            exercise: it.exercise,
            planned: [
              for (final st in it.sets)
                it.isCardio
                    ? PlannedSet(0, st.seconds)
                    : PlannedSet(st.weight, st.reps),
            ],
          ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        backgroundColor: C.bgPage,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.initial == null ? '新增自訂訓練' : '修改自訂訓練',
            style: T.h3()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.scrollBottom),
        children: [
          const SectionTitle('課表名稱'),
          AppCard(
            child: TextField(
              controller: _name,
              style: T.body(),
              maxLength: 20,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                counterText: '',
                hintText: '例：出差旅館版',
                hintStyle: T.body(color: C.textDisabled),
              ),
            ),
          ),
          const SizedBox(height: S.lg),
          SectionTitle('課表內容',
              trailing: _items.isEmpty ? null : '${_items.length} 動作'),
          for (final (i, item) in _items.indexed) ...[
            _ExerciseEditor(
              item: item,
              onChanged: () => setState(() {}),
              onRemove: () => setState(() => _items.removeAt(i)),
            ),
            const SizedBox(height: S.md),
          ],
          // §8.20：虛線按鈕只出現在這裡，不抽成共用元件。
          _DashedAddButton(onTap: _pickExercise),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: C.bgPage,
          border: Border(top: BorderSide(color: C.lineDivider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _editingPublic
                      ? '這份課表已公開。修改並儲存後會重新送審，'
                          '審核期間其他人暫時看不到它。'
                      : '儲存後為「已儲存」狀態，尚未啟用 —— '
                          '要選來訓練，還須到自訂訓練頁按「發布」。',
                  style: T.caption(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: S.sm),
                AppButton(
                  label: '儲存',
                  onPressed: _canSave ? _save : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickExercise() async {
    final picked = await pickExercise(context, myExercises: _myExercises);
    if (picked == null || !mounted) return;

    if (picked.id == kCreateNewExerciseId) {
      final created = await Navigator.of(context).push<Exercise>(
        MaterialPageRoute(builder: (_) => const CreateExerciseScreen()),
      );
      if (created == null || !mounted) return;
      AppScope.of(context).createCustomExercise(created);
      setState(() {
        _myExercises.add(created);
        _items.add(_draftFor(created));
      });
      return;
    }
    setState(() => _items.add(_draftFor(picked)));
  }

  DraftExercise _draftFor(Exercise e) => DraftExercise(
        e,
        [
          if (e.type == ExerciseType.cardio)
            DraftSet(seconds: 600)
          else
            DraftSet(weight: e.isBodyweight ? 0 : 20, reps: 10),
        ],
      );
}

// ---------------------------------------------------------------------------
// 第二層與第三層的編輯
// ---------------------------------------------------------------------------

class _ExerciseEditor extends StatelessWidget {
  final DraftExercise item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  const _ExerciseEditor({
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.exercise.name, style: T.h3())),
                if (item.exercise.isCustom)
                  const TagBadge('自建', borderColor: C.statusWarning),
                SizedBox(
                  width: Sz.tapTarget,
                  height: Sz.tapTarget,
                  child: IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, size: Sz.iconDense),
                    color: C.textSecondary,
                    tooltip: '移除這個動作',
                  ),
                ),
              ],
            ),
            for (final (i, set) in item.sets.indexed) ...[
              const SizedBox(height: S.sm),
              _SetEditor(
                index: i + 1,
                set: set,
                isCardio: item.isCardio,
                bodyweight: item.exercise.isBodyweight,
                perHand: item.exercise.weightIsPerHand,
                singleDumbbell: item.exercise.weightIsSingleDumbbell,
                onChanged: onChanged,
              ),
            ],
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: '加一組',
                    kind: BtnKind.secondary,
                    onPressed: () {
                      // 新的一組沿用最後一組的值 —— 多數人各組同重量。
                      final last = item.sets.last;
                      item.sets.add(DraftSet(
                        weight: last.weight,
                        reps: last.reps,
                        seconds: last.seconds,
                        loadOpen: last.loadOpen,
                      ));
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: AppButton(
                    label: '刪一組',
                    kind: BtnKind.secondary,
                    // 每個動作至少留一組，否則該動作等於不存在。
                    onPressed: item.sets.length > 1
                        ? () {
                            item.sets.removeLast();
                            onChanged();
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _SetEditor extends StatelessWidget {
  final int index;
  final DraftSet set;
  final bool isCardio;
  final bool bodyweight;

  /// 啞鈴：重量欄填每手重量。
  final bool perHand;

  /// 只拿一顆啞鈴的動作（高腳杯式深蹲、臀橋）：填那一顆的重量。
  final bool singleDumbbell;
  final VoidCallback onChanged;
  const _SetEditor({
    required this.index,
    required this.set,
    required this.isCardio,
    required this.bodyweight,
    required this.perHand,
    required this.singleDumbbell,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(S.md),
        decoration: BoxDecoration(
          color: C.bgPage,
          borderRadius: BorderRadius.circular(R.control),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text('第 $index 組', style: T.caption()),
              ],
            ),
            const SizedBox(height: S.sm),
            if (isCardio)
              // 有氧的第三層只有目標時長一欄，無目標重量與目標次數，
              // 亦不設目標強度 —— 強度的單位隨動作而異，要定義即須另立對照表。
              _Field(
                label: '目標時長',
                value: _mmss(set.seconds),
                // 秒為單位（間歇的單組可短至數十秒），顯示格式由前端決定。
                onMinus: set.seconds - 10 >= 10
                    ? () {
                        set.seconds -= 10;
                        onChanged();
                      }
                    : null,
                onPlus: set.seconds + 10 <= 18000
                    ? () {
                        set.seconds += 10;
                        onChanged();
                      }
                    : null,
              )
            else ...[
              // 重量為 0 的徒手動作：重量是外加負重，預設鎖著，開了開關才能調。
              if (bodyweight && set.weight == 0 && !set.loadOpen)
                const _Field(
                  label: '目標重量', // 鎖著的一定是徒手動作，不會是啞鈴
                  value: '徒手',
                  onMinus: null,
                  onPlus: null,
                )
              else
                _Field(
                  label: perHand
                      ? '每手重量'
                      : singleDumbbell
                          ? '啞鈴重量'
                          : '目標重量',
                  // float 精度 0.5 公斤，≥ 0；值為 0 代表徒手（自身體重）動作。
                  value: set.weight == 0 ? '徒手' : '${_kg(set.weight)} kg',
                  onMinus: set.weight - 0.5 >= 0
                      ? () {
                          set.weight -= 0.5;
                          onChanged();
                        }
                      : null,
                  onPlus: () {
                    set.weight += 0.5;
                    onChanged();
                  },
                ),
              if (bodyweight)
                AddedLoadSwitch(
                  on: set.loadOpen || set.weight > 0,
                  onChanged: (v) {
                    set.loadOpen = v;
                    if (!v) set.weight = 0;
                    onChanged();
                  },
                ),
              const SizedBox(height: S.sm),
              _Field(
                label: '目標次數',
                // int，≥ 1。
                value: '${set.reps} 下',
                onMinus: set.reps > 1
                    ? () {
                        set.reps -= 1;
                        onChanged();
                      }
                    : null,
                onPlus: () {
                  set.reps += 1;
                  onChanged();
                },
              ),
            ],
          ],
        ),
      );

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String _mmss(int s) {
    final m = s ~/ 60, r = s % 60;
    return m == 0 ? '$r 秒' : (r == 0 ? '$m 分' : '$m 分 $r 秒');
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _Field({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: Sz.tapTarget,
        child: Row(
          children: [
            SizedBox(width: 68, child: Text(label, style: T.caption())),
            _Round(icon: Icons.remove_rounded, onTap: onMinus),
            Expanded(
              child: Center(child: Text(value, style: T.numberS())),
            ),
            _Round(icon: Icons.add_rounded, onTap: onPlus),
          ],
        ),
      );
}

class _Round extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _Round({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: Sz.tapTarget,
        height: Sz.tapTarget,
        child: Material(
          color: C.bgSurface,
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

/// §8.20 的「虛線按鈕」—— 全案只出現在這裡，故不抽成共用元件。
class _DashedAddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DashedAddButton({required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: CustomPaint(
          painter: const _DashedBorderPainter(),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(R.control),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.control),
              onTap: onTap,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded,
                        size: Sz.iconDense, color: C.actionOutline),
                    const SizedBox(width: S.sm),
                    Text('加入動作',
                        style: T.button(color: C.actionOutline)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.actionOutline;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(R.control),
    );
    // Flutter 的 Border 不支援虛線 —— 沿路徑取樣，4 實 4 虛。
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => false;
}
