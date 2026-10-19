import 'dart:async';
import 'package:flutter/material.dart';

import '../domain/ability.dart';
import '../domain/models.dart';
import '../domain/rewards.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/added_load_switch.dart';
import '../widgets/common.dart';
import '../domain/community.dart';
import 'ai/ai_adjust_screen.dart';
import 'train/create_exercise_screen.dart';
import 'train/equipment_unlock_sheet.dart';
import 'train/exercise_detail_screen.dart';
import 'train/exercise_picker.dart';
import 'train/rest_countdown.dart';
import 'settlement_screen.dart';

/// Read Model：訓練進行中頁
/// 全欄位即時 —— 每一欄皆直接支撐當下要下達的 Command。
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 訓練時長、組間休息倒數、防作弊阻擋秒數皆需每秒重繪
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // 快照產生後，系統自動比對器材明細；有動作做不了就解鎖本次訓練的器材。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = AppScope.of(context);
      if (s.unavailableExercises().isEmpty) return;
      await showEquipmentUnlockSheet(context);
      if (!mounted) return;
      // 解鎖後，系統詢問是否請 AI 智能教練調整本次訓練。
      final ai = await showAppDialog(
        context,
        title: '要請 AI 教練調整這份課表嗎？',
        message: '有動作是靠解鎖才做得了的。AI 可以依你現在的器材與能力值'
            '換掉那些動作，只改本次訓練，不動來源課表。',
        confirmLabel: '請 AI 調整',
        cancelLabel: '照原課表練',
      );
      if (ai != true || !mounted) return;
      // 器材解鎖後的替換動作走 planAdjust —— 成功後落地為一份新的
      // 自訂訓練並佔用一個名額，與使用者主動要求的訓練前微調不同。
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AiAdjustScreen(source: AiSource.planAdjust),
      ));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final session = s.session;
    if (session == null) return const Scaffold(body: SizedBox.shrink());

    // 空白課表尚未加入任何動作時沒有「目前動作」。
    final empty = session.exercises.isEmpty;
    final rec = s.currentRecord;
    final pe = empty ? null : session.exercises[session.exerciseIndex];
    final elapsed = s.now.difference(session.startedAt);
    final blocked = s.blockRemaining;
    final resting = s.restRemaining;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // §8.3 例外（R-17）：訓練進行中頁沒有頂部導覽列，全螢幕沉浸模式
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 50),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.md),
                  child: Row(
                    children: [
                      Expanded(child: Text(session.plan.name, style: T.h3())),
                      SizedBox(
                        width: Sz.tapTarget,
                        height: Sz.tapTarget,
                        child: IconButton(
                          onPressed: () => _confirmEnd(context, s),
                          icon: const Icon(Icons.close, size: Sz.iconDense),
                          color: C.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 總計畫組數為 0（空白課表）時不顯示進度條 —— 進度條不成立。
                // 加入第一個動作後總計畫組數大於 0，進度條自該時點起成立。
                _ProgressPanel(session: session, elapsed: elapsed),
                if (s.isIdleTimedOut) ...[
                  const SizedBox(height: 12),
                  Panel(
                    color: AppColors.hot.withValues(alpha: 0.10),
                    border: AppColors.hot,
                    child: const Row(
                      children: [
                        Icon(
                          Icons.timer_off_outlined,
                          color: AppColors.hot,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '已超過 40 分鐘未完成任何一組，本次訓練將判定為逾時中斷。',
                            style: TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // 全部組都做完之後，游標已推到界外，這一區再顯示就會寫出
                // 「第 4 / 3 組」這種數字 —— 沒有「目前」動作了。
                // 下面的 [_SetEditor] 仍要留著，那句「可以結束訓練了」在裡面。
                if (pe != null && rec != null) ...[
                  const SectionLabel('目前動作'),
                  _CurrentExercise(pe: pe, session: session, rec: rec),
                ] else if (empty)
                  const AppCard(
                    child: EmptyState(
                      icon: Icons.playlist_add_rounded,
                      title: '自由訓練',
                      message: '沒有預先排好的課表。練什麼、做幾組，'
                          '在這裡邊練邊加。',
                    ),
                  ),
                if (blocked > 0) ...[
                  const SizedBox(height: 12),
                  Panel(
                    color: AppColors.warn.withValues(alpha: 0.10),
                    border: AppColors.warn,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: AppColors.warn,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '請稍候 $blocked 秒後再勾選下一組。',
                            style: const TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (pe != null) ...[
                  const SizedBox(height: 18),
                  _SetEditor(state: s, rec: rec, blocked: blocked > 0),
                ],
                const SizedBox(height: S.md),
                // 兩種入口共用同一個 Command：空白課表取得其第一個動作、
                // 一般課表於訓練中臨時加練計畫外的動作。
                AppButton(
                  label: '加入動作至本次訓練',
                  kind: BtnKind.secondary,
                  icon: Icons.add_rounded,
                  onPressed: () => _addExercise(context, s),
                ),
                if (pe != null) ...[
                  const SizedBox(height: S.md),
                  AppButton(
                    label: 'AI 調整剩餘動作',
                    kind: BtnKind.secondary,
                    icon: Icons.auto_awesome_outlined,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiAdjustScreen(
                            source: AiSource.duringTraining),
                      ),
                    ),
                  ),
                  const SectionLabel('本次課表'),
                  _AllSets(session: session),
                ],
              ],
            ),
          ),
          // 組間休息蓋在訓練頁之上 —— 全屏，不是頁面裡的一塊區域（§8.10、R-28）。
          if (resting > 0 && s.restEndsAt != null)
            Positioned.fill(
              child: RestCountdownScreen(
                endsAt: s.restEndsAt!,
                totalSeconds: s.restTotalSeconds,
                onFinished: s.endRestByTimer,
                onSkip: s.skipRest,
                // 接下來要做的動作；清單空（空白課表剛開始）時沒有。
                onInfo: pe == null
                    ? null
                    : () => openExerciseInfo(context, pe.exercise),
              ),
            ),
        ],
      ),
    );
  }

  /// Command「加入動作至本次訓練」的使用者動線：
  /// 選動作 → 指定組數與每組的目標（加入的組無快照帶入值）。
  Future<void> _addExercise(BuildContext context, AppState s) async {
    final picked = await pickExercise(context,
        myExercises: AppScope.of(context).myExercises);
    if (picked == null || !context.mounted) return;

    var exercise = picked;
    if (picked.id == kCreateNewExerciseId) {
      final created = await Navigator.of(context).push<Exercise>(
        MaterialPageRoute(builder: (_) => const CreateExerciseScreen()),
      );
      if (created == null || !context.mounted) return;
      // 建立出來的動作要寫回「我的動作」，不是只用在這一場訓練。
      AppScope.of(context).createCustomExercise(created);
      exercise = created;
    }

    final planned = await showAppSheet<List<PlannedSet>>(
      context,
      title: exercise.name,
      child: _AddSetsForm(exercise: exercise),
    );
    if (planned == null) return;
    s.addExerciseToSession(exercise, planned);
  }

  Future<void> _confirmEnd(BuildContext context, AppState s) async {
    // 空白課表主動結束一律判定為「使用者已完成訓練」——
    // 「提前」的前提是存在預定終點，空白課表無預定內容即無「提前」可言；
    // 一律判為提前結束等於以不存在的標準給予較低獎勵。
    final blank = s.session!.isBlank;
    final all = blank || s.allSetsHandled;
    final kind = await showDialog<EndKind>(
      context: context,
      barrierColor: C.overlay,
      builder: (ctx) => Center(
        child: Material(
          color: C.bgSurface,
          borderRadius: BorderRadius.circular(R.card),
          child: Container(
            width: 280,
            constraints: const BoxConstraints(minHeight: 176),
            padding: const EdgeInsets.all(S.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('結束這次訓練？', style: T.h3(), textAlign: TextAlign.center),
                const SizedBox(height: S.sm),
                Text(
                  blank
                      ? '自由訓練沒有預定終點，結束即為完成。'
                          '空白課表不計入個人排行榜分數。'
                      : '終止方式影響金幣與排行榜分數，但不影響能力值與經驗值。',
                  style: T.body(color: C.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: S.lg),
                // 真正的 CTA：練完了
                AppButton(
                  label: all ? '完成訓練' : '尚有未完成的組',
                  onPressed: all
                      ? () => Navigator.pop(ctx, EndKind.completed)
                      : null,
                ),
                if (!blank) ...[
                  const SizedBox(height: S.md),
                  // §4.5 R-23：中途放棄不該是畫面上最醒目的按鈕
                  AppButton(
                    label: '提前結束訓練',
                    kind: BtnKind.secondary,
                    onPressed: () => Navigator.pop(ctx, EndKind.endedEarly),
                  ),
                ],
                const SizedBox(height: S.md),
                AppButton(
                  label: '繼續訓練',
                  kind: BtnKind.secondary,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (kind == null || !context.mounted) return;
    s.finishWorkout(kind);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SettlementScreen()),
    );
  }
}

/// 加入動作時指定組數與每組的目標。
/// 加入的組**無快照帶入值** —— 目標重量與次數由使用者於加入時指定。
class _AddSetsForm extends StatefulWidget {
  final Exercise exercise;
  const _AddSetsForm({required this.exercise});

  @override
  State<_AddSetsForm> createState() => _AddSetsFormState();
}

class _AddSetsFormState extends State<_AddSetsForm> {
  int _sets = 3;
  double _weight = 20;
  bool _loadOpen = false;
  int _reps = 10;
  int _seconds = 600;

  bool get _isCardio => widget.exercise.type == ExerciseType.cardio;

  @override
  void initState() {
    super.initState();
    if (widget.exercise.isBodyweight) _weight = 0;
    if (_isCardio) _sets = 1;
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row2(
            label: '組數',
            value: '$_sets',
            onMinus: _sets > 1 ? () => setState(() => _sets -= 1) : null,
            onPlus: () => setState(() => _sets += 1),
          ),
          if (_isCardio)
            // 有氧的第三層只有目標時長一欄，無目標重量與目標次數。
            _Row2(
              label: '目標時長',
              value: _seconds % 60 == 0
                  ? '${_seconds ~/ 60} 分'
                  : '${_seconds ~/ 60} 分 ${_seconds % 60} 秒',
              onMinus:
                  _seconds > 10 ? () => setState(() => _seconds -= 30) : null,
              onPlus: _seconds < 18000
                  ? () => setState(() => _seconds += 30)
                  : null,
            )
          else ...[
            // 重量為 0 的徒手動作：重量是外加負重，預設鎖著，開了開關才能調。
            if (widget.exercise.isBodyweight && !_loadOpen && _weight == 0)
              const _Row2(
                label: '目標重量', // 鎖著的一定是徒手動作，不會是啞鈴
                value: '徒手',
                onMinus: null,
                onPlus: null,
              )
            else
              _Row2(
                label: widget.exercise.weightIsPerHand
                    ? '每手重量'
                    : widget.exercise.weightIsSingleDumbbell
                        ? '啞鈴重量'
                        : '目標重量',
                value: _weight == 0 ? '徒手' : '${_kgText(_weight)} kg',
                onMinus: _weight >= 0.5
                    ? () => setState(() => _weight -= 0.5)
                    : null,
                onPlus: () => setState(() => _weight += 0.5),
              ),
            if (widget.exercise.isBodyweight)
              AddedLoadSwitch(
                on: _loadOpen || _weight > 0,
                onChanged: (v) => setState(() {
                  _loadOpen = v;
                  if (!v) _weight = 0;
                }),
              ),
            _Row2(
              label: '目標次數',
              value: '$_reps 下',
              onMinus: _reps > 1 ? () => setState(() => _reps -= 1) : null,
              onPlus: () => setState(() => _reps += 1),
            ),
          ],
          const SizedBox(height: S.md),
          Text(
            '加入後總計畫組數只增不減 —— 已加入的動作與組不可再移除；'
            '不想練的組不勾選即可。',
            style: T.caption(),
          ),
          const SizedBox(height: S.md),
          AppButton(
            label: '加入 $_sets 組',
            onPressed: () => Navigator.of(context).pop(
              List.generate(
                _sets,
                (_) => _isCardio
                    ? PlannedSet(0, _seconds)
                    : PlannedSet(_weight, _reps),
              ),
            ),
          ),
        ],
      );

  static String _kgText(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _Row2 extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _Row2({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Row(
          children: [
            SizedBox(width: 72, child: Text(label, style: T.caption())),
            _RoundBtn(icon: Icons.remove_rounded, onTap: onMinus),
            Expanded(child: Center(child: Text(value, style: T.numberS()))),
            _RoundBtn(icon: Icons.add_rounded, onTap: onPlus),
          ],
        ),
      );
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundBtn({required this.icon, required this.onTap});

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
            child: Icon(icon,
                size: Sz.iconDense,
                color: onTap == null ? C.textDisabled : C.textPrimary),
          ),
        ),
      );
}

class _ProgressPanel extends StatelessWidget {
  final WorkoutSession session;
  final Duration elapsed;
  const _ProgressPanel({required this.session, required this.elapsed});

  @override
  Widget build(BuildContext context) {
    // 總計畫組數為 0 時進度條不成立 —— 只留訓練時長。
    if (session.plannedSets == 0) {
      return Panel(
        child: Row(
          children: [
            const Icon(Icons.timer_outlined,
                size: Sz.iconDense, color: C.textSecondary),
            const SizedBox(width: S.sm),
            Text('訓練時長', style: T.body(color: C.textSecondary)),
            const Spacer(),
            Text(
              '${elapsed.inMinutes}:'
              '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
              style: T.numberS(),
            ),
          ],
        ),
      );
    }
    final pct = (session.progress * 100).round();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${session.doneSets}',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                ' / ${session.plannedSets} 組',
                style: const TextStyle(color: AppColors.textDim, fontSize: 14),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressBar(value: session.progress),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '訓練時長',
                  value:
                      '${elapsed.inMinutes}:'
                      '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '本次累計訓練量',
                  value: session.volume.round().toString(),
                  unit: 'kg',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentExercise extends StatelessWidget {
  final PlanExercise pe;
  final WorkoutSession session;
  final SetRecord? rec;
  const _CurrentExercise({required this.pe, required this.session, this.rec});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final dim = pe.exercise.dim;
    final dimGrade = majorGradeOf(
        dim == null ? kInitialPoints : (s.points[dim] ?? kInitialPoints));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: C.gradeFill(dimGrade),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pe.exercise.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${dim == null ? '有氧' : dimNames[dim]}　'
                      '第 ${session.setIndex + 1} / ${pe.planned.length} 組',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // 動作說明：訓練中也要看得到，不必先退出訓練（使用者 2026-10-19 回報）。
              // 開的是一般的詳情頁，疊在訓練頁上面，返回就回到原來那一組。
              IconButton(
                key: const ValueKey('exercise-info-current'),
                tooltip: '動作說明',
                onPressed: () => openExerciseInfo(context, pe.exercise),
                icon: const Icon(Icons.info_outline_rounded,
                    color: AppColors.cool, size: Sz.iconDefault),
              ),
            ],
          ),
          // 已被替換的標示：可展開檢視原動作，還原入口位於此
          if (pe.replacedFrom != null) ...[
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                iconColor: AppColors.cool,
                collapsedIconColor: AppColors.cool,
                title: const Row(
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 15,
                      color: AppColors.cool,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'AI 已替換此動作',
                      style: TextStyle(
                        color: AppColors.cool,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '原動作：${pe.replacedFrom!.name}',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      label: '還原為 ${pe.replacedFrom!.name}',
                      onPressed: () {
                        final s = AppScope.of(context);
                        final i = s.session!.exercises.indexOf(pe);
                        // **看回傳值再決定要說什麼。** 原本一律跳「已還原」，
                        // 但規格擋下「該動作已有完成的組」—— 那種情況下
                        // 畫面會說一件沒發生的事。
                        showToast(
                          context,
                          s.restoreReplacedExercise(i)
                              ? '已還原為 ${pe.replacedFrom!.name}'
                              : '這個動作已經做過組，不能還原了。',
                        );
                      },
                      kind: BtnKind.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                const Icon(Icons.history, size: 14, color: AppColors.textFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sourceOf(AppScope.of(context), pe),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 預帶值的來源。使用者看到欄位裡已經有數字，必須知道它是哪來的 ——
  /// 是上次的實績，還是系統依體重性別推算的起點。
  static String _sourceOf(AppState s, PlanExercise pe) {
    final last = s.lastActualSets(pe.exercise.id);
    if (last.isEmpty) {
      return pe.planned.first.targetWeight == 0
          ? '第一次做這個動作，無上次紀錄'
          : '第一次做這個動作，重量由體重與現有能力值推算';
    }
    final shown = last.take(4).map((t) {
      return t.weight == 0 ? '${t.reps} 下' : '${_num(t.weight)}×${t.reps}';
    }).join('　');
    final more = last.length > 4 ? '　…' : '';
    return '上次：$shown$more';
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';
}

/// 訓練中開動作說明。**疊在訓練頁上面**，不結束、不暫停訓練；返回就回到原來那一組。
@visibleForTesting
Future<void> openExerciseInfo(BuildContext context, Exercise e) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ExerciseDetailScreen(exercise: e)),
    );

/// 步進器（§8.11）—— 全 App 最高頻的操作。
///
/// 【必須】重量與次數**上下兩行**，間距 8px；勾選框在右側跨兩行。
/// 一行放不下：375 螢幕上一行需要 336px，可用寬只有 311px，爆版 25px。
/// 增減幅度：重量 1 kg、次數 1 次（1kg 對啞鈴、器械、槓鈴全都適用）。
class _SetEditor extends StatelessWidget {
  final AppState state;
  final SetRecord? rec;
  final bool blocked;
  const _SetEditor({required this.state, this.rec, required this.blocked});

  @override
  Widget build(BuildContext context) {
    final r = rec;
    if (r == null) {
      return Panel(
        child: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: C.statusSuccess,
              size: Sz.iconDefault,
            ),
            const SizedBox(width: S.md),
            Expanded(child: Text('所有組皆已處理，可以結束訓練了。', style: T.body())),
          ],
        ),
      );
    }

    final cur = state.session!;
    final ex = cur.exercises[cur.exerciseIndex].exercise;
    final locked = state.addedLoadLocked(ex, r.weight);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 兩個步進器上下排列
              Expanded(
                child: Column(
                  children: [
                    if (locked)
                      // 重量為 0 的徒手動作：重量是外加負重，預設鎖著。
                      Container(
                        constraints: const BoxConstraints(minHeight: Sz.tapTarget),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(R.control),
                          border: Border.all(color: C.lineDivider),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_outline,
                                  size: Sz.iconDense, color: C.textSecondary),
                              const SizedBox(width: S.sm),
                              Text('徒手', style: T.numberS()),
                            ],
                          ),
                        ),
                      )
                    else
                    _StepperRow(
                      value: kgText(r.weight),
                      unit: ex.weightIsPerHand
                          ? 'kg／每手'
                          : ex.weightIsSingleDumbbell
                              ? 'kg／一顆'
                              : 'kg',
                      // 目標重量的精度是 0.5 公斤，步進就該是 0.5。
                      // 用 1 的話，30.5 一按就再也回不到 .5 的格子上。
                      onMinus: () =>
                          state.editCurrentSet(weight: r.weight - 0.5),
                      onPlus: () =>
                          state.editCurrentSet(weight: r.weight + 0.5),
                      onTapValue: () => _askNumber(
                        context,
                        title: ex.weightIsPerHand
                            ? '這一組的重量（每手）'
                            : ex.weightIsSingleDumbbell
                                ? '這一組的重量（那一顆啞鈴）'
                                : '這一組的重量',
                        initial: kgText(r.weight),
                        unit: 'kg',
                        decimal: true,
                        onOk: (v) => state.editCurrentSet(weight: v),
                      ),
                      active: true,
                    ),
                    if (ex.isBodyweight)
                      AddedLoadSwitch(
                        on: !locked,
                        onChanged: (v) => state.setAddedLoad(ex, v),
                      ),
                    const SizedBox(height: S.sm),
                    _StepperRow(
                      value: '${r.reps}',
                      unit: '次',
                      onMinus: () => state.editCurrentSet(reps: r.reps - 1),
                      onPlus: () => state.editCurrentSet(reps: r.reps + 1),
                      onTapValue: () => _askNumber(
                        context,
                        title: '這一組的次數',
                        initial: '${r.reps}',
                        unit: '次',
                        decimal: false,
                        onOk: (v) => state.editCurrentSet(reps: v.round()),
                      ),
                      active: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: S.md),
              // 勾選框：44 寬 × 跨兩行高（約 96px）
              // 變大是好事 —— 這是全 App 最高頻的動作，流汗時更好按。
              _CheckBox(
                enabled: !blocked,
                onTap: () {
                  final ok = state.completeCurrentSet();
                  if (!ok) {
                    showToast(
                      context,
                      '距前一組不足 30 秒，請稍候 ${state.blockRemaining} 秒',
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: S.md),
          AppButton(
            label: '取消該組',
            kind: BtnKind.secondary,
            onPressed: state.cancelCurrentSet,
          ),
        ],
      ),
    );
  }
}

/// 重量的顯示文字。整數不補小數點，半公斤補一位。
String kgText(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// 直接輸入一個數字。
///
/// 步進器一次只動一格：從 20 公斤改到 82.5 要按 125 次，
/// 而重量本來就是每組都在改的東西。點數字直接打，才是輸入方式。
///
/// [decimal] 為真時允許 0.5 的小數（模型訂的重量精度）；
/// 為假時只收正整數（次數）。
Future<void> _askNumber(
  BuildContext context, {
  required String title,
  required String initial,
  required String unit,
  required bool decimal,
  required void Function(double) onOk,
}) async {
  final ctrl = TextEditingController(text: initial);
  String? error;

  final v = await showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        double? parse() {
          final raw = ctrl.text.trim();
          if (raw.isEmpty) return null;
          final n = double.tryParse(raw);
          if (n == null) return null;
          // 重量：≥ 0（0 代表徒手），精度 0.5。
          if (decimal) {
            if (n < 0) return null;
            if ((n * 2) != (n * 2).roundToDouble()) return null;
            return n;
          }
          // 次數：整數且 ≥ 1，不記錄次數為 0 的失敗組。
          if (n < 1 || n != n.roundToDouble()) return null;
          return n;
        }

        return AlertDialog(
          backgroundColor: C.bgSurface,
          title: Text(title, style: T.h3()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                    decimal: decimal, signed: false),
                style: T.numberS(),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  suffixText: unit,
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  final n = parse();
                  if (n != null) Navigator.pop(ctx, n);
                },
              ),
              const SizedBox(height: S.sm),
              Text(
                decimal ? '0.5 公斤為一格；0 代表徒手。' : '整數，至少 1 次。',
                style: T.caption(color: C.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final n = parse();
                if (n == null) {
                  setLocal(() => error =
                      decimal ? '請輸入 0 以上、每 0.5 一格的數字。' : '請輸入 1 以上的整數。');
                  return;
                }
                Navigator.pop(ctx, n);
              },
              child: const Text('確定'),
            ),
          ],
        );
      },
    ),
  );
  if (v != null) onOk(v);
}

class _StepperRow extends StatelessWidget {
  final String value;
  final String unit;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  /// 點數值本身直接輸入。步進器一次只動一格，
  /// 從 20 改到 82.5 要按 125 次 —— 那不是輸入方式。
  final VoidCallback? onTapValue;
  final bool active;
  const _StepperRow({
    required this.value,
    required this.unit,
    required this.onMinus,
    required this.onPlus,
    this.onTapValue,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: Sz.tapTarget),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(R.control),
      // 進行中那一組：2px action/outline
      border: Border.all(
        color: active ? C.actionOutline : C.lineDivider,
        width: active ? 2 : 1,
      ),
    ),
    child: Row(
      children: [
        _StepBtn(icon: Icons.remove, onTap: onMinus),
        // 數值區彈性填滿剩餘空間，且整塊可點 —— 點了直接輸入。
        Expanded(
          child: InkWell(
            onTap: onTapValue,
            borderRadius: BorderRadius.circular(R.control),
            child: SizedBox(
              height: Sz.tapTarget,
              child: Center(
                child: ValueUnit(value: value, unit: unit, style: T.numberS()),
              ),
            ),
          ),
        ),
        _StepBtn(icon: Icons.add, onTap: onPlus),
      ],
    ),
  );
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    highlightColor: C.press,
    // 感應區 44×44（§5.3）
    child: SizedBox(
      width: Sz.tapTarget,
      height: Sz.tapTarget,
      child: Icon(icon, size: Sz.iconDense, color: C.textPrimary),
    ),
  );
}

class _CheckBox extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CheckBox({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: Material(
      color: C.actionPrimary,
      borderRadius: BorderRadius.circular(R.control),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        highlightColor: C.press,
        child: const SizedBox(
          width: Sz.tapTarget,
          height: 96, // 跨兩行
          child: Icon(Icons.check, size: Sz.iconDefault, color: C.textOnAccent),
        ),
      ),
    ),
  );
}

class _AllSets extends StatelessWidget {
  final WorkoutSession session;
  const _AllSets({required this.session});

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < session.exercises.length; i++)
            _ExerciseRow(
              exerciseIndex: i,
              pe: session.exercises[i],
              records: session.records[i],
              isCurrent: i == session.exerciseIndex,
              currentSet: i == session.exerciseIndex ? session.setIndex : -1,
            ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  final int exerciseIndex;
  final PlanExercise pe;
  final List<SetRecord> records;
  final bool isCurrent;
  final int currentSet;
  const _ExerciseRow({
    required this.exerciseIndex,
    required this.pe,
    required this.records,
    required this.isCurrent,
    required this.currentSet,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Expanded(
          // 點動作名稱看說明 —— 下一個動作怎麼做，不必等輪到它才知道。
          child: GestureDetector(
            key: ValueKey('exercise-info-$exerciseIndex'),
            behavior: HitTestBehavior.opaque,
            onTap: () => openExerciseInfo(context, pe.exercise),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    pe.exercise.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? AppColors.text : AppColors.textDim,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
        Row(
          children: [
            for (var j = 0; j < records.length; j++)
              // 已完成的格子可點 —— Command「取消該組」的入口。
              // 健身時單手操作與誤觸是常態，勾錯了得有地方改回來。
              GestureDetector(
                onTap: records[j].state != SetState.done
                    ? null
                    : () async {
                        final ok = await _confirmUncheck(context, j + 1);
                        if (!ok || !context.mounted) return;
                        AppScope.of(context).uncheckSet(exerciseIndex, j);
                      },
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(left: 5),
                  decoration: BoxDecoration(
                    color: _fill(records[j].state, j == currentSet),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: j == currentSet ? AppColors.accent : AppColors.line,
                      width: j == currentSet ? 1.6 : 1,
                    ),
                  ),
                  child: records[j].state == SetState.done
                      ? const Icon(
                          Icons.check,
                          size: 13,
                          color: AppColors.onAccent,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ],
    ),
  );

  static Future<bool> _confirmUncheck(BuildContext context, int n) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: C.bgSurface,
          title: Text('取消第 $n 組？', style: T.h3()),
          content: Text(
            '該組回到未完成，進度條會跟著回退。'
            '原本那筆紀錄保留為已取消，不會消失。',
            style: T.body(color: C.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('不要'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('取消該組'),
            ),
          ],
        ),
      ) ??
      false;

  static Color _fill(SetState s, bool current) {
    switch (s) {
      case SetState.done:
        return AppColors.accent;
      case SetState.cancelled:
      case SetState.skipped:
        return AppColors.surfaceAlt;
      default:
        return current ? AppColors.surfaceAlt : Colors.transparent;
    }
  }
}
