import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/models.dart';
import '../../mock/mock_equipment.dart';
import '../../mock/mock_exercise_stats.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'create_exercise_screen.dart';
import 'exercise_detail_screen.dart';

/// Read Model：動作庫
/// 分頁：六個肌群 ＋ 有氧 ＋ 我的動作（後兩者不混入肌群分頁）。
/// 名稱搜尋與器材篩選皆為頁面層級，跨全部分頁生效。
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _search = TextEditingController();

  /// 器材篩選：預設帶入使用者的「持有器材明細」，可手動調整。
  /// 空集合代表不篩選（未設定持有器材者）。
  Set<String>? _equipment;

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

  /// 篩選預設帶入可用器材。訓練中若已解鎖器材，基準即為全部品項 ——
  /// 解鎖了卻在加入動作時還被自己的設定擋住，等於沒解鎖。
  Set<String> _owned(AppState s) => _equipment ??= {...s.equipmentForFiltering};

  /// 動作要做得起來，其**所需器材必須全部**在使用者選取的集合內 ——
  /// 與〈可練場所的推導〉同一判準：需要多項器材時，要同時具備全部。
  bool _matches(Exercise e, Set<String> owned, String query) {
    if (query.isNotEmpty && !e.name.contains(query)) return false;
    if (owned.isEmpty) return true;
    final need = requiredEquipment(e.equipment);
    // 所需器材為空值者不參與器材比對，於器材篩選時不出現於任何分類。
    if (need.isEmpty) return false;
    return need.every(owned.contains);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final owned = _owned(s);
    final q = _search.text.trim();

    List<Exercise> pick(List<Exercise> src) =>
        src.where((e) => _matches(e, owned, q)).toList();

    return DefaultTabController(
      length: 8,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          title: const Text('動作庫',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            // 建立自訂動作原本只有訓練中與課表編輯器兩個入口，
            // 動作庫的「我的動作」看得到卻加不了 —— 從清單本身也要建得起來。
            IconButton(
              tooltip: '建立自訂動作',
              onPressed: () async {
                final created = await Navigator.of(context).push<Exercise>(
                  MaterialPageRoute(builder: (_) => const CreateExerciseScreen()),
                );
                if (created == null || !context.mounted) return;
                final ok = s.createCustomExercise(created);
                showToast(context, ok ? '已建立「${created.name}」' : '已有同名的自建動作');
              },
              icon: const Icon(Icons.add, size: 22, color: AppColors.textDim),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textDim,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: [
              for (final d in Dim.values) Tab(text: dimNames[d]),
              const Tab(text: '有氧'),
              const Tab(text: '我的動作'),
            ],
          ),
        ),
        body: Column(
          children: [
            // 置頂區不參與捲動，下緣以 1px 分隔線與捲動區分界（§8.19）。
            Container(
              decoration: const BoxDecoration(
                color: C.bgPage,
                border: Border(bottom: BorderSide(color: C.lineDivider)),
              ),
              padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
              child: Column(
                children: [
                  SearchField(
                    controller: _search,
                    hint: '搜尋動作名稱',
                  ),
                  const SizedBox(height: S.md),
                  _EquipmentFilter(
                    selected: owned,
                    onToggle: (item) => setState(() {
                      owned.contains(item)
                          ? owned.remove(item)
                          : owned.add(item);
                    }),
                    onClear: owned.isEmpty
                        ? null
                        : () => setState(() => owned.clear()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // 依**訓練部位**分頁而非所屬肌群 —— 一個動作可練到多個部位，
                  // 窄距臥推同時出現在胸與手，才找得到。
                  for (final d in Dim.values)
                    _ExerciseList(
                        items:
                            pick(s.platformExercises.where((e) => e.tabs.contains(d)).toList())),
                  _ExerciseList(items: pick(s.cardioExercises)),
                  _ExerciseList(items: pick(s.myExercises)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 器材篩選 —— 列舉複選。全部取消即為不篩選。
class _EquipmentFilter extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback? onClear;
  const _EquipmentFilter({
    required this.selected,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded,
                  size: 15, color: AppColors.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  selected.isEmpty
                      ? '器材篩選：全部動作'
                      : '器材篩選：${selected.length} 項',
                  style: T.caption(),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Text('清除', style: T.caption(color: C.actionOutline)),
                ),
            ],
          ),
          const SizedBox(height: S.sm),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kEquipmentItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: S.sm),
              itemBuilder: (_, i) {
                final item = kEquipmentItems[i];
                final on = selected.contains(item);
                return GestureDetector(
                  onTap: () => onToggle(item),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: S.md),
                    decoration: BoxDecoration(
                      color: on ? C.actionOutline : C.bgSurface,
                      borderRadius: BorderRadius.circular(R.child),
                      border: Border.all(
                          color: on ? C.actionOutline : C.lineDivider),
                    ),
                    child: Text(
                      item,
                      style: T.caption(
                          color: on ? C.textOnDark : C.textPrimary),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
}

class _ExerciseList extends StatelessWidget {
  final List<Exercise> items;
  const _ExerciseList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(S.base),
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: '這個分頁沒有符合的動作',
          message: '換個關鍵字，或放寬器材篩選。',
        ),
      );
    }
    // 預設排序為累積練習次數由多到少 —— 主力動作長期固定，
    // 順序不隨每日訓練變動，使用者記得住位置。
    final sorted = [...items]
      ..sort((a, b) => statOf(b.id).count.compareTo(statOf(a.id).count));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
      itemCount: sorted.length,
      itemBuilder: (_, i) => _Row(exercise: sorted[i]),
    );
  }
}

class _Row extends StatelessWidget {
  final Exercise exercise;
  const _Row({required this.exercise});

  @override
  Widget build(BuildContext context) => Padding(
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.play_circle_outline,
                          size: 19, color: AppColors.textDim),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(exercise.name,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(
                            '${exercise.equipment}　·　'
                            '累積 ${statOf(exercise.id).count} 次',
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 11),
                          ),
                          if (exercise.isCustom) ...[
                            const SizedBox(height: 5),
                            const Pill('本動作不計入能力值',
                                color: AppColors.bronze),
                          ],
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
