import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/models.dart';
import '../../domain/task_pool.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 成就定義（設定成就定義）
///
/// 門檻調整不改動既有解鎖紀錄 —— 已解鎖者即使門檻調升仍維持已解鎖。
class AchievementDefsScreen extends StatelessWidget {
  const AchievementDefsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final byCategory = <String, List<Achievement>>{};
    for (final a in s.achievements) {
      byCategory.putIfAbsent(a.category, () => []).add(a);
    }

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('設定成就定義')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          const _NoteCard(
            event: '管理員已設定成就定義',
            note: '門檻調整不改動既有解鎖紀錄 —— 已解鎖與已領取的狀態原樣保留。',
          ),
          for (final entry in byCategory.entries) ...[
            SectionTitle(entry.key, trailing: '${entry.value.length} 項'),
            ListGroup(
              rows: [
                for (var i = 0; i < entry.value.length; i++)
                  ListRow(
                    title: entry.value[i].name,
                    subtitle:
                        '門檻 ${entry.value[i].threshold}　·　'
                        '金幣 ${entry.value[i].rewardCoins}　·　'
                        '經驗值 ${entry.value[i].rewardExp}',
                    trailing: entry.value[i].unlocked
                        ? const TagBadge('已解鎖', borderColor: C.statusSuccess)
                        : null,
                    chevron: true,
                    showDivider: i != entry.value.length - 1,
                    onTap: () => _edit(context, s, entry.value[i]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppState s, Achievement a) async {
    final threshold = TextEditingController(text: '${a.threshold}');
    final coins = TextEditingController(text: '${a.rewardCoins}');
    final exp = TextEditingController(text: '${a.rewardExp}');
    final ok = await showAppDialog(
      context,
      title: a.name,
      size: DialogSize.medium,
      confirmLabel: '儲存',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NumberRow(label: '達成門檻', controller: threshold),
          const SizedBox(height: S.md),
          _NumberRow(label: '獎勵金幣', controller: coins),
          const SizedBox(height: S.md),
          _NumberRow(label: '獎勵經驗值', controller: exp),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final t = int.tryParse(threshold.text.trim());
    final c = int.tryParse(coins.text.trim());
    final e = int.tryParse(exp.text.trim());
    if (t == null || c == null || e == null) {
      showToast(context, '請填入整數');
      return;
    }
    final failure = s.setAchievementDefinition(
      a,
      threshold: t,
      coins: c,
      exp: e,
    );
    if (failure != null) {
      showToast(context, failure);
      return;
    }
    // 改完的那一枚（同一個 category#threshold 可能已經換成新門檻）。
    final now = s.achievements.firstWhere(
        (x) => x.category == a.category && x.name == a.name,
        orElse: () => a);
    final cloud = await s.pushAchievement(now);
    if (!context.mounted) return;
    showToast(context, cloud ?? '已設定');
  }
}

/// 每日任務池（設定每日任務池）
///
/// 任務項目是**可組態的 Event 訂閱**：管理員只需指定判定來源 Event 與目標次數，
/// 不需改動系統程式。本頁同時承載限時任務項目，以「適用對象」欄位區分 ——
/// 兩者欄位完全相同，另立一份清單等於日後加欄位得記得兩邊都加。
class DailyTaskPoolScreen extends StatefulWidget {
  const DailyTaskPoolScreen({super.key});

  @override
  State<DailyTaskPoolScreen> createState() => _DailyTaskPoolScreenState();
}

class _DailyTaskPoolScreenState extends State<DailyTaskPoolScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final personal =
        s.taskPool.where((t) => t.audience == TaskAudience.personal).toList();
    final team = teamItems(s.taskPool);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: const Text('設定每日任務池'),
        actions: [
          IconButton(
            tooltip: '新增項目',
            onPressed: s.canConfigure ? () => _edit(context, s, null) : null,
            icon: const Icon(Icons.add, size: Sz.iconDefault),
          ),
        ],
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          const _NoteCard(
            event: '管理員已設定每日任務池',
            note: '任務進度由 Event 判定，故每一項都標明其判定來源。'
                '任務池調整不改動任何使用者當日已指派的任務 —— 要重抽才會換。',
          ),
          SectionTitle('每日抽取數量', trailing: '池內 ${personal.length} 項可抽'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('每日隨機抽 $kDailyDrawCount 項指派給個人',
                          style: T.body()),
                    ),
                    SizedBox(
                      width: 88,
                      child: AppButton(
                        label: '調整',
                        kind: BtnKind.secondary,
                        onPressed: s.canConfigure
                            ? () => _editDrawCount(context, s)
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.sm),
                Text(
                  '允許與前一日重複，不做去重 —— 池子的內容本來就是日常行為，'
                  '連續兩日重複屬正常；去重會隱含要求池子維持一定數量，'
                  '管理員縮減時系統就抽不出來。'
                  '${personal.length <= kDailyDrawCount ? '目前項目數不足抽取數量，會抽出全部。' : ''}',
                  style: T.caption(),
                ),
                const SizedBox(height: S.md),
                AppButton(
                  label: '重新抽一次（示範）',
                  kind: BtnKind.secondary,
                  onPressed: personal.isEmpty
                      ? null
                      : () {
                          s.redrawDailyTasks();
                          showToast(context, '已重抽今日任務');
                        },
                ),
              ],
            ),
          ),
          const SectionTitle('個人項目', trailing: '供每日任務抽取'),
          if (personal.isEmpty)
            AppCard(child: Text('池子是空的，抽不出任何任務。', style: T.caption()))
          else
            ListGroup(rows: [
              for (var i = 0; i < personal.length; i++)
                _row(context, s, personal[i], i != personal.length - 1),
            ]),
          const SectionTitle('團隊項目', trailing: '供限時任務指派'),
          if (team.isEmpty)
            AppCard(child: Text('沒有團隊項目，限時任務指派不出來。', style: T.caption()))
          else
            ListGroup(rows: [
              for (var i = 0; i < team.length; i++)
                _row(context, s, team[i], i != team.length - 1),
            ]),
        ],
      ),
    );
  }

  ListRow _row(
          BuildContext context, AppState s, TaskPoolItem t, bool divider) =>
      ListRow(
        title: t.name,
        subtitle: t.summary,
        chevron: true,
        showDivider: divider,
        onTap: () => _edit(context, s, t),
      );

  Future<void> _editDrawCount(BuildContext context, AppState s) async {
    final ctrl = TextEditingController(text: '$kDailyDrawCount');
    final ok = await showAppDialog(
      context,
      title: '每日抽取數量',
      confirmLabel: '儲存',
      content: _NumberRow(label: '抽取數量', controller: ctrl),
    );
    if (ok != true || !context.mounted) return;
    final v = int.tryParse(ctrl.text.trim());
    if (v == null) {
      showToast(context, '請填入整數');
      return;
    }
    final failure = s.applySettings('taskPool', {'drawCount': v});
    final cloud = failure ?? await s.pushConfigGroup('taskPool');
    if (!context.mounted) return;
    showToast(context, cloud ?? '已設定');
    setState(() {});
  }

  Future<void> _edit(
      BuildContext context, AppState s, TaskPoolItem? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final event = TextEditingController(text: existing?.sourceEvent ?? '');
    final target = TextEditingController(text: '${existing?.target ?? 1}');
    var audience = existing?.audience ?? TaskAudience.personal;

    final ok = await showAppDialog(
      context,
      title: existing == null ? '新增任務項目' : existing.name,
      size: DialogSize.medium,
      confirmLabel: '儲存',
      content: StatefulBuilder(
        builder: (context, setInner) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TextRow(controller: name, hint: '任務名稱'),
            const SizedBox(height: S.md),
            _TextRow(controller: event, hint: '判定來源 Event'),
            const SizedBox(height: S.md),
            _NumberRow(label: '目標次數', controller: target),
            const SizedBox(height: S.md),
            Row(
              children: [
                for (final a in TaskAudience.values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: a == TaskAudience.personal ? S.sm : 0),
                      child: GestureDetector(
                        onTap: () => setInner(() => audience = a),
                        child: Container(
                          height: Sz.buttonMinHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(R.control),
                            border: Border.all(
                              color:
                                  audience == a ? C.actionOutline : C.lineDivider,
                              width: audience == a ? 2 : 1,
                            ),
                          ),
                          child: Text(taskAudienceNames[a]!,
                              style: T.body(
                                  color: audience == a
                                      ? C.actionOutline
                                      : C.textSecondary)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (existing != null) ...[
              const SizedBox(height: S.md),
              AppButton(
                label: '移除此項目',
                kind: BtnKind.secondary,
                onPressed: () async {
                  Navigator.of(context).pop(false);
                  final failure = s.removeTaskPoolItem(existing);
                  final cloud =
                      failure ?? await s.dropTaskPoolItem(existing);
                  if (!context.mounted) return;
                  showToast(context, cloud ?? '已移除');
                },
              ),
            ],
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final n = int.tryParse(target.text.trim());
    if (n == null) {
      showToast(context, '目標次數請填整數');
      return;
    }
    final item = TaskPoolItem(
      id: existing?.id ?? 'tp${DateTime.now().millisecondsSinceEpoch}',
      name: name.text,
      sourceEvent: event.text.trim().isEmpty ? '（未指定）' : event.text.trim(),
      target: n,
      audience: audience,
    );
    final failure = existing == null
        ? s.addTaskPoolItem(item)
        : s.updateTaskPoolItem(existing,
            name: name.text,
            sourceEvent: event.text,
            target: n,
            audience: audience);
    if (failure != null) {
      showToast(context, failure);
      setState(() {});
      return;
    }
    // 更新走的是「同一個 id 覆寫」，新增是「新的 id」—— 兩者在雲端都是 set。
    final now = s.taskPool.firstWhere((x) => x.id == item.id, orElse: () => item);
    final cloud = await s.pushTaskPoolItem(now);
    if (!context.mounted) return;
    showToast(context, cloud ?? '已設定');
    setState(() {});
  }
}

/// 新手任務範本（設定新手任務範本）
///
/// 新手任務為三選一，非三項待辦 —— 本 Command 維護的正是那三個選項。
class NoviceTemplateScreen extends StatelessWidget {
  const NoviceTemplateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('設定新手任務範本')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          const _NoteCard(
            event: '管理員已設定新手任務範本',
            note: '新手任務為三選一，非三項待辦。範本調整不改動已指派給既有使用者的任務。',
          ),
          const SectionTitle('三個選項'),
          ListGroup(
            rows: [
              for (var i = 0; i < s.noviceTemplates.length; i++)
                ListRow(
                  title: s.noviceTemplates[i],
                  subtitle: '選項 ${i + 1}',
                  chevron: true,
                  showDivider: i != s.noviceTemplates.length - 1,
                  onTap: () => _edit(context, s, i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppState s, int i) async {
    final ctrl = TextEditingController(text: s.noviceTemplates[i]);
    final ok = await showAppDialog(
      context,
      title: '選項 ${i + 1}',
      confirmLabel: '儲存',
      content: _TextRow(controller: ctrl, hint: '範本內容'),
    );
    if (ok != true || !context.mounted) return;
    showToast(context, s.setNoviceTemplate(i, ctrl.text) ?? '已設定');
  }
}

/// 限時任務（設定限時任務）
///
/// 項目來自**同一份任務池**（適用對象＝團隊），不是自由打字的一段文字：
/// 團隊限時分數要拿來排名，而排名的前提是所有團隊做的是同一件事。
/// 全平台統一，一個指派日只有一組。
class TimedTaskConfigScreen extends StatefulWidget {
  const TimedTaskConfigScreen({super.key});

  @override
  State<TimedTaskConfigScreen> createState() => _TimedTaskConfigScreenState();
}

class _TimedTaskConfigScreenState extends State<TimedTaskConfigScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.timedTask;
    final items = teamItems(s.taskPool);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('設定限時任務')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          const _NoteCard(
            event: '管理員已設定限時任務',
            note: '全平台統一，一個指派日只有一組；有效時窗為指派當日。'
                '不分團隊指派 —— 各隊做的事不同時，分數放在同一排行榜比較就失去意義。',
          ),
          const SectionTitle('本日指派'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: T.h3()),
                const SizedBox(height: S.sm),
                Text(t.detail, style: T.body(color: C.textSecondary)),
                const SizedBox(height: S.md),
                Text('指派日 ${t.assignedOn.month}/${t.assignedOn.day}',
                    style: T.caption()),
              ],
            ),
          ),
          SectionTitle('可指派的項目',
              trailing: '任務池內適用對象＝團隊者 ${items.length} 項'),
          if (items.isEmpty)
            AppCard(
              child: Text(
                '任務池沒有團隊項目。到「設定每日任務池」新增一項、'
                '把適用對象設為團隊，這裡才指派得出來。',
                style: T.caption(),
              ),
            )
          else
            ListGroup(rows: [
              for (var i = 0; i < items.length; i++)
                ListRow(
                  title: items[i].name,
                  subtitle: items[i].summary,
                  trailing: items[i].name == t.title
                      ? TagBadge('本日指派', borderColor: C.accentDeep)
                      : null,
                  chevron: items[i].name != t.title,
                  showDivider: i != items.length - 1,
                  onTap: !s.canConfigure || items[i].name == t.title
                      ? null
                      : () {
                          showToast(
                              context, s.assignTimedTaskFrom(items[i]) ?? '已指派');
                          setState(() {});
                        },
                ),
            ]),
          const SizedBox(height: S.base),
          Text(
            '任務的多樣性由跨日提供 —— 每日換一組，不靠跨團隊提供。',
            style: T.caption(),
          ),
        ],
      ),
    );
  }
}

// --- 共用零件 ---

class _NoteCard extends StatelessWidget {
  final String event;
  final String note;
  const _NoteCard({required this.event, required this.note});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(event, style: T.body(weight: FontWeight.w600)),
        const SizedBox(height: S.sm),
        Text(note, style: T.caption()),
      ],
    ),
  );
}

class _NumberRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _NumberRow({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: T.body())),
      SizedBox(
        width: 96,
        child: TextField(
          controller: controller,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
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
  );
}

class _TextRow extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _TextRow({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: T.body(),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: T.body(color: C.textDisabled),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.control),
      ),
    ),
  );
}
