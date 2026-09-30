import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/ability.dart';
import '../../domain/models.dart';
import '../../domain/commerce.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 平台動作庫（設定平台動作）
///
/// 527 筆動作，故以搜尋而非分頁進入 —— 後台改的是特定一筆，不是逛動作庫。
class PlatformExercisesScreen extends StatefulWidget {
  const PlatformExercisesScreen({super.key});

  @override
  State<PlatformExercisesScreen> createState() =>
      _PlatformExercisesScreenState();
}

class _PlatformExercisesScreenState extends State<PlatformExercisesScreen> {
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final q = search.text.trim();
    final hits = q.isEmpty
        ? const <Exercise>[]
        : s.platformExercises.where((e) => e.name.contains(q)).toList();

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('設定平台動作')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(S.base),
            child: SearchField(
              controller: search,
              hint: '搜尋動作名稱（共 ${s.platformExercises.length} 筆）',
            ),
          ),
          Expanded(
            child: q.isEmpty
                ? const EmptyState(
                    icon: Icons.search_rounded,
                    title: '輸入動作名稱',
                    message: '平台動作庫逾 500 筆，請以名稱搜尋要調整的那一筆。',
                  )
                : hits.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '找不到符合的動作',
                    message: '換個關鍵字再試一次。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      S.base,
                      0,
                      S.base,
                      S.scrollBottom,
                    ),
                    itemCount: hits.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: S.md),
                      child: AppCard(
                        padding: EdgeInsets.zero,
                        child: ListRow(
                          title: hits[i].name,
                          subtitle:
                              '${hits[i].equipment}　·　'
                              '相對強度 ${hits[i].relativeIntensity}　·　'
                              '休息 ${hits[i].defaultRestSeconds == null ? "未設定" : "${hits[i].defaultRestSeconds}s"}',
                          trailing: hits[i].dim == null
                              ? const TagBadge('有氧')
                              : TagBadge(dimNames[hits[i].dim!]!),
                          chevron: true,
                          showDivider: false,
                          onTap: () => _edit(context, s, hits[i]),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppState s, Exercise e) async {
    final ri = TextEditingController(text: '${e.relativeIntensity}');
    final rest = TextEditingController(
      text: e.defaultRestSeconds == null ? '' : '${e.defaultRestSeconds}',
    );
    final ok = await showAppDialog(
      context,
      title: e.name,
      size: DialogSize.medium,
      confirmLabel: '儲存',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Field(label: '相對強度係數', controller: ri, decimal: true),
          const SizedBox(height: S.md),
          _Field(label: '預設組間休息（秒）', controller: rest, hint: '留空＝退回全站預設'),
          const SizedBox(height: S.md),
          Text('相對強度係數調整不追溯既有點數 —— 點數為歷史最高的標準化分數，已寫入者不重算。', style: T.caption()),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = double.tryParse(ri.text.trim());
    if (v == null) {
      showToast(context, '相對強度係數不是有效的數字');
      return;
    }
    final r = rest.text.trim().isEmpty ? null : int.tryParse(rest.text.trim());
    if (rest.text.trim().isNotEmpty && r == null) {
      showToast(context, '組間休息秒數不是有效的整數');
      return;
    }
    final failure = s.setPlatformExercise(
      e,
      relativeIntensity: v,
      restSeconds: r,
    );
    if (failure != null) {
      showToast(context, failure);
      return;
    }
    final now = s.platformExercises.firstWhere((x) => x.id == e.id,
        orElse: () => e);
    final cloud = await s.pushExercise(now);
    if (!context.mounted) return;
    showToast(context, cloud ?? '已設定');
    setState(() {});
  }
}

/// 平台訓練計畫（設定訓練計畫）
class PlatformPlansScreen extends StatefulWidget {
  const PlatformPlansScreen({super.key});

  @override
  State<PlatformPlansScreen> createState() => _PlatformPlansScreenState();
}

class _PlatformPlansScreenState extends State<PlatformPlansScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('設定訓練計畫')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('管理員已設定訓練計畫', style: T.body(weight: FontWeight.w600)),
                const SizedBox(height: S.sm),
                Text(
                  '調整不影響已產生的快照與已解鎖者 —— 進行中的訓練與已付金幣解鎖的使用者不受影響。'
                  '解鎖價格統一為 $kPlanUnlockCoins 金幣，不逐計畫區分；設為空值即改為不可購買。',
                  style: T.caption(),
                ),
              ],
            ),
          ),
          const SectionTitle('平台計畫'),
          ListGroup(
            rows: [
              for (var i = 0; i < s.platformPlans.length; i++)
                ListRow(
                  title: s.platformPlans[i].name,
                  subtitle: _rowSubtitle(s, s.platformPlans[i]),
                  chevron: true,
                  showDivider: i != s.platformPlans.length - 1,
                  onTap: () => _edit(context, s, s.platformPlans[i]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 清單上每一列的第二行。
  ///
  /// **「示範」那兩個字是重點。** `platformPlans` 是七份示範用假課表
  /// （`kPlans`）加上 27 份真的平台課表，而**假的排在前面** ——
  /// 管理員打開這一頁，前七筆全是改了存不住的。
  ///
  /// 那七份在雲端沒有文件（它們不屬於平台資料，是撐著 AI 優化、會員鎖定
  /// 那幾條流程示範用的），所以寫回去無處可寫。程式在存檔時會講
  /// （`pushPlanSpec` 回一句話），但**那時候人已經改完了**。
  /// 要在他點進去之前就看得出來。
  String _rowSubtitle(AppState s, WorkoutPlan p) {
    final rank = p.requiredRank ?? '初階';
    final price = p.unlockCoins == null ? '不販售' : '${p.unlockCoins} 金幣';
    final demo = !s.planSpecById.containsKey(p.id);
    return '${demo ? "示範課表 · 改動不上雲　·　" : ""}'
        '所需階級 $rank　·　解鎖價格 $price　·　${p.totalSets} 組';
  }

  Future<void> _edit(BuildContext context, AppState s, WorkoutPlan p) async {
    final rank = TextEditingController(
      text: p.requiredRank == null ? '' : '${p.requiredRank}',
    );
    final coins = TextEditingController(
      text: p.unlockCoins == null ? '' : '${p.unlockCoins}',
    );
    final ok = await showAppDialog(
      context,
      title: p.name,
      size: DialogSize.medium,
      confirmLabel: '儲存',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Field(label: '所需階級', controller: rank, hint: '留空＝初階'),
          const SizedBox(height: S.md),
          _Field(label: '金幣解鎖價格', controller: coins, hint: '留空＝不呈現該解鎖方式'),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // 留空為合法輸入：所需階級留空＝初階，解鎖價格留空＝不呈現該解鎖方式。
    int? parse(TextEditingController c) =>
        c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

    final r = parse(rank);
    final u = parse(coins);
    if ((rank.text.trim().isNotEmpty && r == null) ||
        (coins.text.trim().isNotEmpty && u == null)) {
      showToast(context, '請填入整數或留空');
      return;
    }
    final failure = s.setPlanConfig(p, requiredRank: r, unlockCoins: u);
    if (failure != null) {
      showToast(context, failure);
      return;
    }
    // 沿用另外四類的寫法：本機先改（上面那一行），再把改完的樣子送上雲，
    // 雲端那一趟的結果才是使用者看到的那句話（`[BE-12b]`）。
    final cloud = await s.pushPlanSpec(p.id);
    if (!context.mounted) return;
    showToast(context, cloud ?? '已設定');
    setState(() {});
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool decimal;
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: T.body())),
          SizedBox(
            width: 104,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              style: T.numberS(),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: S.md,
                  vertical: S.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.control),
                ),
              ),
            ),
          ),
        ],
      ),
      if (hint != null) ...[
        const SizedBox(height: S.xs),
        Text(hint!, style: T.caption()),
      ],
    ],
  );
}
