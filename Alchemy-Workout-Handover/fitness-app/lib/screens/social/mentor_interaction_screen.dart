import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/ability.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Read Model：師徒互動頁（教官方）
///
/// 支撐的 Command：回答學徒提問、指派師徒任務。
class MentorInteractionScreen extends StatefulWidget {
  const MentorInteractionScreen({super.key});
  @override
  State<MentorInteractionScreen> createState() =>
      _MentorInteractionScreenState();
}

class _MentorInteractionScreenState extends State<MentorInteractionScreen> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final apprentices = s.apprentices;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('師徒互動')),
      // **學徒清單空了不代表沒事可做** —— 剛解除的那些還在 3 天挽回
      // 窗口內，教官得看得到、回應得了。原本這裡直接畫「還沒有學徒」，
      // 於是解除之後那段關係就從教官眼前整個消失。
      body: apprentices.isEmpty && s.releasedApprentices.isEmpty
          ? const EmptyState(
              icon: Icons.school_outlined,
              title: '還沒有學徒',
              message: '通過教官資格後，學徒可以在教官清單找到你並提出申請。',
            )
          : apprentices.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(
                      S.base, S.base, S.base, S.scrollBottom),
                  children: [
                    const SectionTitle('已解除的學徒', trailing: '3 天內可挽回'),
                    for (final b in s.releasedApprentices)
                      _ReleasedCard(state: s, bond: b),
                  ],
                )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.base, S.base, S.scrollBottom),
              children: [
                // 學徒評分總平均：帶徒數未達 3 人時為空值，不呈現
                if (apprentices.length >= 3)
                  AppCard(
                    child: StatField(
                        label: '學徒評分總平均', value: '4.7', unit: '／ 5'),
                  )
                else
                  AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: Sz.iconDense, color: C.accentInfo),
                        const SizedBox(width: S.md),
                        Expanded(
                          child: Text(
                            '帶徒數未達 3 人，暫不呈現學徒評分總平均。',
                            style: T.caption(),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SectionTitle('學徒清單'),
                Row(
                  children: [
                    for (var i = 0; i < apprentices.length; i++) ...[
                      if (i > 0) const SizedBox(width: S.md),
                      Expanded(
                        child: _ApprenticeTab(
                          a: apprentices[i],
                          selected: i == selected,
                          onTap: () => setState(() => selected = i),
                        ),
                      ),
                    ],
                  ],
                ),

                _ApprenticeDetail(a: apprentices[selected]),

                const SectionTitle('待回答的提問'),
                _Questions(
                    state: s, apprenticeUid: apprentices[selected].uid),

                const SectionTitle('進行中的任務'),
                _Tasks(state: s, apprenticeUid: apprentices[selected].uid),

                const SizedBox(height: S.base),
                AppButton(
                  label: '解除與 ${apprentices[selected].name} 的師徒關係',
                  kind: BtnKind.secondary,
                  onPressed: () => _release(
                      context, s, apprentices[selected]),
                ),

                if (s.releasedApprentices.isNotEmpty) ...[
                  const SectionTitle('已解除的學徒', trailing: '3 天內可挽回'),
                  for (final b in s.releasedApprentices)
                    _ReleasedCard(state: s, bond: b),
                ],
              ],
            ),
    );
  }
}

class _ApprenticeTab extends StatelessWidget {
  final Apprentice a;
  final bool selected;
  final VoidCallback onTap;
  const _ApprenticeTab({
    required this.a,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        borderColor: selected ? C.actionOutline : C.lineDivider,
        borderWidth: selected ? 2 : 1,
        padding: const EdgeInsets.symmetric(vertical: S.md, horizontal: S.sm),
        child: Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: C.bgPage,
              child: Text(a.name.characters.first,
                  style: T.body(weight: FontWeight.w700)),
            ),
            const SizedBox(height: S.sm),
            Text(a.name,
                style: T.body(weight: selected ? FontWeight.w600 : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            // 學徒現在的階級，不是他拜師當下那個。
            Text(
                '${AppScope.of(context).rankOf(a.name, uid: a.uid, fallback: a.rank)} 階',
                style: T.caption()),
          ],
        ),
      );
}

class _ApprenticeDetail extends StatelessWidget {
  final Apprentice a;
  const _ApprenticeDetail({required this.a});

  @override
  Widget build(BuildContext context) {
    final overall = overallGrade(a.ability);
    // 找出最弱的一維，供教官判斷指派什麼任務
    final weakest = Dim.values
        .reduce((x, y) => (a.ability[x] ?? 0) <= (a.ability[y] ?? 0) ? x : y);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('六維能力值'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('綜合能力等級', style: T.caption()),
                  const SizedBox(width: S.sm),
                  GradeBadge(overall),
                  const Spacer(),
                  TagBadge('最弱：${dimNames[weakest]}',
                      borderColor: C.accentInfo),
                ],
              ),
              const SizedBox(height: S.base),
              for (var i = 0; i < Dim.values.length; i++) ...[
                if (i > 0) const SizedBox(height: S.md),
                _DimBar(dim: Dim.values[i], points: a.ability[Dim.values[i]]!),
              ],
            ],
          ),
        ),
        const SectionTitle('近期訓練摘要'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < a.recentWorkouts.length; i++)
                ListRow(
                  title: a.recentWorkouts[i],
                  showDivider: i != a.recentWorkouts.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: S.md),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Text('本週已計分次數', style: T.body()),
              ),
              ValueUnit(
                value: '${a.scoredThisWeek}',
                unit: '／ 2',
                style: T.numberS(
                    color: a.scoredThisWeek >= 2
                        ? C.textSecondary
                        : C.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DimBar extends StatelessWidget {
  final Dim dim;
  final int points;
  const _DimBar({required this.dim, required this.points});

  @override
  Widget build(BuildContext context) {
    final node = nodeOf(points);
    final within = node.upper > node.lower
        ? (points - node.lower) / (node.upper - node.lower)
        : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text('${dimNames[dim]}　${node.label}', style: T.body())),
            Text('$points', style: T.numberS()),
          ],
        ),
        const SizedBox(height: S.sm),
        BareProgress(value: within, color: C.gradeFill(node.major)),
      ],
    );
  }
}

class _Questions extends StatelessWidget {
  final AppState state;

  /// 目前選中的學徒。**問答要依他過濾** —— 本機這份 `questions` 是
  /// 所有學徒共用的一份清單，不過濾的話教官會在小明的頁面上看到
  /// 小華問的問題，答下去也記在小華那段關係上。
  final String? apprenticeUid;
  const _Questions({required this.state, this.apprenticeUid});

  @override
  Widget build(BuildContext context) {
    // 待回答＝回答內容為空值的師徒問答
    final pending = state.questions
        .where((q) => q.answer == null && q.apprenticeUid == apprenticeUid)
        .toList();
    if (pending.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                size: Sz.iconDense, color: C.statusSuccess),
            const SizedBox(width: S.md),
            Expanded(child: Text('沒有待回答的提問。', style: T.body())),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final q in pending) _AnswerCard(question: q, state: state),
      ],
    );
  }
}

class _AnswerCard extends StatefulWidget {
  final MentorQuestion question;
  final AppState state;
  const _AnswerCard({required this.question, required this.state});
  @override
  State<_AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends State<_AnswerCard> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.question.text, style: T.body()),
              const SizedBox(height: S.md),
              TextField(
                controller: ctrl,
                maxLines: null,
                minLines: 3,
                style: T.body(),
                decoration: InputDecoration(
                  hintText: '輸入回答…',
                  hintStyle: T.body(color: C.textSecondary),
                  filled: true,
                  fillColor: C.bgPage,
                  contentPadding: const EdgeInsets.all(S.md),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.control),
                    borderSide: const BorderSide(color: C.lineDivider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.control),
                    borderSide: const BorderSide(color: C.lineDivider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.control),
                    borderSide:
                        const BorderSide(color: C.actionOutline, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: S.md),
              AppButton(
                label: '回答',
                onPressed: () async {
                  // **回答的內容由狀態層寫入並送上雲端。**
                  // 在此之前是畫面直接改 `question.answer`，而
                  // `answerQuestion()` 只是個計數器 —— 學徒永遠看不到回答。
                  if (!widget.state.answerQuestion(
                      widget.question, ctrl.text)) {
                    return;
                  }
                  setState(() {});
                  final r = await widget.state.lastWrite('回答提問');
                  if (!context.mounted) return;
                  showToast(context,
                      r.ok ? '已回答' : '回答沒有送達學徒：${r.why}');
                },
              ),
            ],
          ),
        ),
      );
}

class _Tasks extends StatelessWidget {
  final AppState state;

  /// 目前選中的學徒。理由同 [_Questions.apprenticeUid]。
  final String? apprenticeUid;
  const _Tasks({required this.state, this.apprenticeUid});

  @override
  Widget build(BuildContext context) {
    // 已領取與已作廢（教官取消或關係解除）的不算進行中。
    final ongoing = state.mentorTasks
        .where((t) =>
            t.state != MentorTaskState.claimed &&
            t.state != MentorTaskState.voided &&
            t.apprenticeUid == apprenticeUid)
        .toList();
    return Column(
      children: [
        if (ongoing.isEmpty)
          AppCard(child: Text('沒有進行中的任務。', style: T.body()))
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ongoing.length; i++) ...[
                  ListRow(
                    title: ongoing[i].title,
                    subtitle: switch (ongoing[i].state) {
                      MentorTaskState.submitted => '學徒說做完了，等你發放獎勵',
                      MentorTaskState.done => '已發放，等學徒領取',
                      _ => '已指派，學徒還沒完成',
                    },
                    showDivider: false,
                    trailing: TagBadge(
                      switch (ongoing[i].state) {
                        MentorTaskState.submitted => '待發放',
                        MentorTaskState.done => '已發放',
                        _ => '進行中',
                      },
                      borderColor: ongoing[i].state == MentorTaskState.assigned
                          ? C.lineDivider
                          : C.statusSuccess,
                    ),
                  ),
                  // 已發放的獎勵已經放行，不能再取消。
                  if (ongoing[i].state.isOpen)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(S.base, 0, S.base, S.md),
                      child: Row(
                        children: [
                          if (ongoing[i].state == MentorTaskState.submitted) ...[
                            Expanded(
                              child: AppButton(
                                label: '發放獎勵',
                                onPressed: () {
                                  final ok =
                                      state.releaseMentorTaskReward(ongoing[i]);
                                  showToast(
                                      context,
                                      ok
                                          ? '已發放，學徒現在可以領取了'
                                          : state.taskReviewBlockedReason(
                                                  ongoing[i]) ??
                                              '現在發放不了。');
                                },
                              ),
                            ),
                            const SizedBox(width: S.md),
                          ],
                          Expanded(
                            child: AppButton(
                              label: '取消任務',
                              kind: BtnKind.secondary,
                              onPressed: () => _cancel(context, ongoing[i]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (i != ongoing.length - 1)
                    const Divider(height: 1, color: C.lineDivider),
                ],
              ],
            ),
          ),
        const SizedBox(height: S.md),
        AppButton(
          label: '指派師徒任務',
          kind: BtnKind.secondary,
          icon: Icons.add,
          onPressed: () => _assign(context),
        ),
      ],
    );
  }

  /// 取消任務：作廢、沒有獎勵、不能復原，所以先確認。
  Future<void> _cancel(BuildContext context, MentorTask t) async {
    final ok = await showAppDialog(
      context,
      title: '取消「${t.title}」？',
      message: '取消後任務作廢，學徒拿不到獎勵，也不能復原。',
      confirmLabel: '取消任務',
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    final done = state.cancelMentorTask(t);
    showToast(
        context, done ? '任務已取消' : state.taskReviewBlockedReason(t) ?? '現在取消不了。');
  }

  /// 指派師徒任務。學徒標記完成後要教官發放獎勵，學徒才可領取；本頁負責指派、發放與取消。
  Future<void> _assign(BuildContext context) async {
    final title = TextEditingController();
    final detail = TextEditingController();
    final ok = await showAppDialog(
      context,
      title: '指派師徒任務',
      confirmLabel: '指派',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            style: T.body(),
            decoration: InputDecoration(
              hintText: '任務名稱，例：本週完成三次腿部訓練',
              hintStyle: T.body(color: C.textDisabled),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
              ),
            ),
          ),
          const SizedBox(height: S.md),
          TextField(
            controller: detail,
            style: T.body(),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: '說明（選填）',
              hintStyle: T.body(color: C.textDisabled),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.control),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final t = title.text.trim();
    if (t.isEmpty) return;
    // **指派給哪位學徒要講清楚。** 不帶的話任務進一份共用清單，
    // 誰都不知道是給誰的，也就寫不到正確的師徒關係下。
    final ok2 = state.assignMentorTask(t, detail.text.trim(),
        apprenticeUid: apprenticeUid);
    // **做不到的時候不可以說做到了。** 這裡原本不管結果一律跳
    // 「已指派」—— 而 `assignMentorTask` 有兩道守衛會靜靜 return。
    if (!context.mounted) return;
    showToast(context, ok2 ? '已指派「$t」' : state.assignBlockedReason);
  }
}

/// 教官解除與這位學徒的關係。**需經多次確認，避免誤觸**
/// —— 與學徒那一側同一套。
Future<void> _release(BuildContext context, AppState s, Apprentice a) async {
  final first = await showAppDialog(
    context,
    title: '解除與 ${a.name} 的師徒關係？',
    message: '未完成的師徒任務會作廢，且解除後 3 天內雙方都不能與別人建立師徒關係。',
    confirmLabel: '繼續',
  );
  if (first != true || !context.mounted) return;
  final second = await showAppDialog(
    context,
    title: '確定要解除嗎？',
    message: '3 天內你們任一方都可以提出恢復，但恢復需要雙方同意。',
    confirmLabel: '確定解除',
  );
  if (second != true || !context.mounted) return;
  final ok = s.releaseApprentice(a.uid ?? '', MentorReleaseReason.byInstructor);
  showToast(context, ok ? '已解除，3 天內可挽回' : '解除不了，這位學徒不在名單上。');
}

/// 一段已解除、還在挽回窗口內的關係。
///
/// **提出恢復與同意恢復不會同時出現在同一個人面前** ——
/// 那正是先前那版做錯的地方（規格：恢復需雙方同意）。
class _ReleasedCard extends StatefulWidget {
  final AppState state;
  final ReleasedBond bond;
  const _ReleasedCard({required this.state, required this.bond});

  @override
  State<_ReleasedCard> createState() => _ReleasedCardState();
}

class _ReleasedCardState extends State<_ReleasedCard> {
  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final b = widget.bond;
    final blocked = s.restoreBlockedReasonOf(b);
    final byMe = b.restoreProposedBy == s.myUid;
    final awaitingMe = b.restoreProposedBy != null && !byMe;

    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(b.apprenticeName,
                      style: T.body(weight: FontWeight.w700)),
                ),
                TagBadge('剩 ${b.cooldownLeftAt(s.now).inHours} 小時',
                    borderColor: C.accentInfo),
              ],
            ),
            const SizedBox(height: S.sm),
            Text(
              '解除原因：${mentorReleaseReasonNames[b.reason] ?? '未註明'}。'
              '未完成的任務已作廢。',
              style: T.caption(),
            ),
            if (blocked != null) ...[
              const SizedBox(height: S.md),
              Text(blocked, style: T.caption(color: C.statusError)),
            ] else if (awaitingMe) ...[
              const SizedBox(height: S.md),
              Text('${b.apprenticeName} 提出了恢復，等你回應。', style: T.caption()),
              const SizedBox(height: S.sm),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: '拒絕恢復',
                      kind: BtnKind.secondary,
                      onPressed: () {
                        final ok = s.rejectRestoreFor(b.apprenticeUid);
                        showToast(context,
                            ok ? '已拒絕，3 天內還能再提' : '現在拒絕不了。');
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: AppButton(
                      label: '同意恢復',
                      onPressed: () {
                        // **做不到的時候不可以說做到了。**
                        // 這一顆是 2026-09-30 深夜我自己寫的，
                        // 而且重蹈當晚查了一整輪的那個覆轍 ——
                        // 使用者按下去、畫面說恢復了、雲端什麼也沒變。
                        final ok = s.acceptRestoreFor(b.apprenticeUid);
                        showToast(
                            context,
                            ok
                                ? '師徒關係已恢復'
                                : s.restoreBlockedReasonOf(b) ??
                                    '現在恢復不了。');
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ] else if (byMe) ...[
              const SizedBox(height: S.md),
              Text('已提出恢復，等 ${b.apprenticeName} 回應。', style: T.caption()),
            ] else ...[
              const SizedBox(height: S.md),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: '提出恢復師徒關係',
                  kind: BtnKind.secondary,
                  onPressed: () {
                    final ok = s.proposeRestoreFor(b.apprenticeUid);
                    showToast(
                        context,
                        ok
                            ? '已提出，等對方同意'
                            : s.restoreBlockedReasonOf(b) ?? '提不出來。');
                    setState(() {});
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
