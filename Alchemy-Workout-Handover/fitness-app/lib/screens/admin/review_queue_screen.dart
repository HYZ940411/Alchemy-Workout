import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../domain/custom_plan.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 這個人**現在**叫什麼，以及案件建立當下叫什麼（兩者不同才寫）。
///
/// **管理員是靠名字認人的** —— `02_Aggregate定義.md` 把顯示名稱列為
/// 「供待審佇列與稽核呈現」。使用者 2026-09-28 裁決 A 開放改名之後，
/// 被檢舉的人可以在案件審完之前換一張臉；30 天的冷卻期擋掉大部分，
/// 這一列擋掉剩下的。
///
/// 曾用名**只在這裡呈現，不對一般使用者公開** —— 那等於替一個人做了
/// 一次他沒同意的揭露，而規格說暱稱是顯示名稱不是識別碼。
///
/// 不必另存一份曾用名清單：案件本來就凍結著建立當下的名字
/// （`ReportCase.accused` 等），那正好就是這裡要的那一個。
String _withFormerName(AppState s, String frozen, String? uid) {
  final now = s.nameOf(frozen, uid: uid);
  return now == frozen ? now : '$now（案件建立時：$frozen）';
}

/// Read Model：管理員待審佇列
///
/// 分四個分頁，不採單一混合佇列 —— 混合後管理員每點一筆須切換心智模式；
/// 也不採四個完全獨立的佇列 —— 四種待審的欄位無法共用但仍需一處總覽。
class ReviewQueueScreen extends StatelessWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.admin.can(AdminScope.contentReview)) {
      return const _NoPermission(scope: AdminScope.contentReview);
    }

    final reports = s.reports.where(_open).toList();
    final appeals = s.appeals.where(_openA).toList();
    final ics = s.instructorCases
        .where((c) => c.state == CaseState.pending)
        .toList();
    final pps = s.pendingPublicPlans;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(
          title: const Text('待審佇列'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(Sz.tapTarget),
            child: AppTabBar(tabs: [
              '檢舉 ${reports.length}',
              '申訴 ${appeals.length}',
              '教官 ${ics.length}',
              '公開課表 ${pps.length}',
            ]),
          ),
        ),
        body: TabBarView(
          children: [
            _ReportTab(cases: reports, state: s),
            _AppealTab(cases: appeals, state: s),
            _InstructorTab(cases: ics, state: s),
            _PlanTab(cases: pps, state: s),
          ],
        ),
      ),
    );
  }

  static bool _open(ReportCase c) =>
      c.state == CaseState.pending || c.state == CaseState.reviewing;
  static bool _openA(AppealCase c) =>
      c.state == CaseState.pending || c.state == CaseState.reviewing;
}

class _NoPermission extends StatelessWidget {
  final AdminScope scope;
  const _NoPermission({required this.scope});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(title: const Text('權限不足')),
        body: EmptyState(
          icon: Icons.lock_outline,
          title: '沒有「${adminScopeNames[scope]}」權限',
          message: '每個管理員 Command 的 Precondition 都要求執行者狀態為生效中，'
              '且權限組涵蓋該 Command 所屬的組別。',
        ),
      );
}

/// 逾期標示 —— 各案件層級，供排序與標紅。
/// 逾期不改變案件狀態：不自動通過、不自動駁回、不自動退回待審視。
class _DeadlineTag extends StatelessWidget {
  final bool overdue;
  final String? left;
  const _DeadlineTag({required this.overdue, required this.left});

  @override
  Widget build(BuildContext context) => overdue
      ? const TagBadge('已逾期', borderColor: C.statusError)
      : Text(left ?? '', style: T.caption());
}

/// 佇列頂部：待處理筆數與最久等待時間，供判斷該先處理哪一類。
class _QueueHeader extends StatelessWidget {
  final int count;
  final Duration? longest;

  /// 已產生「審核已逾期」的案件數。逾期是營運指標，不是業務規則 ——
  /// 只標示，不自動通過也不自動駁回。
  final int overdue;
  const _QueueHeader({required this.count, this.longest, this.overdue = 0});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          children: [
            Expanded(child: StatField(label: '待處理', value: '$count', unit: '筆')),
            Expanded(
              child: StatField(
                label: '最久等待',
                value: longest == null ? '—' : '${longest!.inHours}',
                unit: longest == null ? null : '小時',
              ),
            ),
            Expanded(
              child: StatField(label: '逾期', value: '$overdue', unit: '筆'),
            ),
          ],
        ),
      );
}

class _ReportTab extends StatelessWidget {
  final List<ReportCase> cases;
  final AppState state;
  const _ReportTab({required this.cases, required this.state});

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) {
      return const EmptyState(
        icon: Icons.flag_outlined,
        title: '沒有待審的檢舉',
        message: '使用者檢舉與系統自動標記的內容都會進到這裡。',
      );
    }
    final longest = cases
        .map((c) => appNow().difference(c.enteredAt))
        .reduce((a, b) => a > b ? a : b);

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        _QueueHeader(
          count: cases.length,
          longest: longest,
          overdue: cases.where((c) => c.overdue).length,
        ),
        const SizedBox(height: S.md),
        for (final c in cases) _ReportCard(c: c, state: state),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportCase c;
  final AppState state;
  const _ReportCard({required this.c, required this.state});

  @override
  Widget build(BuildContext context) {
    final waited = appNow().difference(c.enteredAt);
    // 級距一律依**當下的**累計違規次數決定；同一人的前一案成立後，
    // 後續案件的預告級距要跟著變。
    final after = state.violationsForCase(c) + 1;
    final tier = tierForViolations(after);
    final mine = c.handlerName == state.admin.name;
    // 被檢舉者**現在**的名字，後面括號補上開案當下那個。
    // 判定與記點靠的是 `accusedUid`，這裡只是顯示。
    final accused = _withFormerName(state, c.accused, c.accusedUid);

    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TagBadge(caseStateNames[c.state]!,
                    borderColor: c.state == CaseState.reviewing
                        ? C.accentInfo
                        : C.lineDivider),
                const SizedBox(width: S.sm),
                TagBadge(reportTargetNames[c.target]!),
                const Spacer(),
                _DeadlineTag(overdue: c.overdue, left: c.timeLeft),
              ],
            ),
            const SizedBox(height: S.md),
            Text('${c.id}　·　已等待 ${waited.inHours} 小時', style: T.caption()),
            const SizedBox(height: S.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: C.bgPage,
                borderRadius: BorderRadius.circular(R.child),
              ),
              child: Text(c.content, style: T.body()),
            ),
            const SizedBox(height: S.md),
            _Row(label: '案件來源', value: caseOriginNames[c.origin]!),
            _Row(
                label: c.origin == CaseOrigin.autoFlag ? '命中的違規類別' : '檢舉理由',
                value: c.reason),
            if (c.origin == CaseOrigin.userReport)
              _Row(label: '檢舉者人數', value: '${c.reporterCount}'),
            _Row(label: '被檢舉者', value: accused),
            _Row(label: '累計違規次數', value: '${c.accusedViolations}'),
            if (c.handlerName != null)
              _Row(label: '處理中的管理員', value: c.handlerName!),

            const Divider(height: S.lg, color: C.lineDivider),

            // 成立時的級距由固定階梯累犯制推出，管理員不逐案選級距
            Row(
              children: [
                const Icon(Icons.gavel_outlined,
                    size: Sz.iconDense, color: C.textSecondary),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Text('成立後將處以：${tier.label}（累計第 $after 次）',
                      style: T.body()),
                ),
              ],
            ),
            if (c.target == ReportTarget.account) ...[
              const SizedBox(height: S.sm),
              Text('帳號類檢舉無可下架的標的 —— 帳號不是一則內容。',
                  style: T.caption()),
            ],
            if (revokesInstructor(after)) ...[
              const SizedBox(height: S.sm),
              Text('若其具教官身分，資格將一併撤銷（警告不撤銷）。',
                  style: T.caption(color: C.statusError)),
            ],
            const SizedBox(height: S.md),

            if (c.state == CaseState.pending)
              AppButton(
                label: '審視檢舉',
                onPressed: () => state.reviewReport(c),
              )
            else if (!mine && c.overdue)
              // 接手：僅限審視中且已逾審核時限
              AppButton(
                label: '接手審核案件（已逾 ${c.waited} 小時）',
                onPressed: () {
                  state.takeOverReport(c);
                  showToast(context, '已接手，案件狀態維持審視中');
                },
              )
            else if (!mine)
              AppButton(
                label: '由 ${c.handlerName} 處理中',
                onPressed: null,
              )
            else
              ButtonRow(
                left: AppButton(
                  label: '駁回檢舉',
                  kind: BtnKind.secondary,
                  onPressed: () {
                    state.dismissReport(c);
                    showToast(context, '已駁回');
                  },
                ),
                right: AppButton(
                  label: '成立並處罰',
                  onPressed: () async {
                    final ok = await showAppDialog(
                      context,
                      title: '確認處罰',
                      message: '$accused 的累計違規將成為 '
                          '$after 次，處以「${tier.label}」。'
                          '${c.target == ReportTarget.account ? '' : '違規內容一併下架。'}',
                      confirmLabel: '處罰',
                      destructive: true,
                    );
                    if (ok != true || !context.mounted) return;
                    // **說實際發生的事，不說級距的名字。**
                    //
                    // 原本固定印「已處罰：警告」之類 —— 那是照著級距算出來
                    // 的字，不是照著結果印的。2026-09-28 使用者雙人實測 T8：
                    // 判成立之後貼文兩邊都還在、對方也沒有收到處罰，
                    // 而畫面照樣說「已處罰」。
                    final out = state.upholdReport(c);
                    showToast(context, '${tier.label}　·　${out.summary}');
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppealTab extends StatelessWidget {
  final List<AppealCase> cases;
  final AppState state;
  const _AppealTab({required this.cases, required this.state});

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) {
      return const EmptyState(
        icon: Icons.balance_outlined,
        title: '沒有待審的申訴',
        message: '使用者對處罰或內容攔截提出的申訴會進到這裡。',
      );
    }
    final longest = cases
        .map((c) => appNow().difference(c.filedAt))
        .reduce((a, b) => a > b ? a : b);

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        _QueueHeader(
          count: cases.length,
          longest: longest,
          overdue: cases.where((c) => c.overdue).length,
        ),
        const SizedBox(height: S.md),
        for (final c in cases)
          Padding(
            padding: const EdgeInsets.only(bottom: S.md),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TagBadge(caseStateNames[c.state]!,
                          borderColor: c.state == CaseState.reviewing
                              ? C.accentInfo
                              : C.lineDivider),
                      const SizedBox(width: S.sm),
                      TagBadge(appealTargetNames[c.target]!),
                      const Spacer(),
                      _DeadlineTag(overdue: c.overdue, left: c.timeLeft),
                    ],
                  ),
                  const SizedBox(height: S.md),
                  _Row(label: '已等待', value: '${c.waited} 小時'),
                  _Row(
                      label: '申訴者',
                      value: _withFormerName(AppScope.of(context), c.appellant,
                          c.appellantUid)),
                  _Row(label: '所申訴的對象', value: c.subject),
                  _Row(label: '距事發天數', value: '${c.daysSinceIncident} 天'),
                  if (c.handlerName != null)
                    _Row(label: '處理中的管理員', value: c.handlerName!),
                  const SizedBox(height: S.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(S.md),
                    decoration: BoxDecoration(
                      color: C.bgPage,
                      borderRadius: BorderRadius.circular(R.child),
                    ),
                    child: Text(c.reason, style: T.body()),
                  ),
                  const SizedBox(height: S.md),
                  if (c.state == CaseState.pending)
                    AppButton(
                        label: '審視申訴',
                        onPressed: () => state.reviewAppeal(c))
                  else if (c.handlerName != state.admin.name && c.overdue)
                    AppButton(
                      label: '接手審核案件（已逾 ${c.waited} 小時）',
                      onPressed: () {
                        state.takeOverAppeal(c);
                        showToast(context, '已接手');
                      },
                    )
                  else if (c.handlerName != state.admin.name)
                    AppButton(
                        label: '由 ${c.handlerName} 處理中', onPressed: null)
                  else
                    ButtonRow(
                      left: AppButton(
                        label: '駁回申訴',
                        kind: BtnKind.secondary,
                        onPressed: () {
                          state.decideAppeal(c, false);
                          showToast(context, '已駁回申訴');
                        },
                      ),
                      right: AppButton(
                        label: '成立並撤銷處罰',
                        onPressed: () {
                          state.decideAppeal(c, true);
                          showToast(context, '申訴成立，處罰已撤銷');
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _InstructorTab extends StatelessWidget {
  final List<InstructorCase> cases;
  final AppState state;
  const _InstructorTab({required this.cases, required this.state});

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) {
      return const EmptyState(
        icon: Icons.school_outlined,
        title: '沒有待審的教官申請',
        message: '簡答題需人工審核的申請會進到這裡。',
      );
    }
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        _QueueHeader(
          count: cases.length,
          longest: cases
              .map((c) => appNow().difference(c.enteredAt))
              .reduce((a, b) => a > b ? a : b),
          overdue: cases.where((c) => c.overdue).length,
        ),
        const SizedBox(height: S.md),
        for (final c in cases)
          Padding(
            padding: const EdgeInsets.only(bottom: S.md),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(
                              _withFormerName(AppScope.of(context), c.applicant,
                                  c.applicantUid),
                              style: T.h3())),
                      _DeadlineTag(overdue: c.overdue, left: c.timeLeft),
                      const SizedBox(width: S.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.weighted >= 70
                              ? C.statusSuccess
                              : C.statusError,
                          borderRadius: BorderRadius.circular(R.child),
                        ),
                        child: Text(c.weighted.toStringAsFixed(1),
                            style: T.numberS(
                                color: c.weighted >= 70
                                    ? C.textOnAccent
                                    : C.textOnDark)),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.md),
                  for (final e in c.aiScores.entries) ...[
                    AppProgress(
                      value: e.value / 100,
                      label: e.key,
                      trailingLabel: e.value.toStringAsFixed(0),
                    ),
                    const SizedBox(height: S.md),
                  ],
                  if (c.concerns.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(S.md),
                      decoration: BoxDecoration(
                        color: C.statusError.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(R.child),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('疑慮標記',
                              style: T.body(color: C.statusError)),
                          const SizedBox(height: S.xs),
                          for (final x in c.concerns)
                            Text('· $x',
                                style: T.caption(color: C.statusError)),
                        ],
                      ),
                    ),
                    const SizedBox(height: S.md),
                  ],
                  Text('簡答題作答', style: T.caption()),
                  const SizedBox(height: S.xs),
                  for (final (q, a) in c.answers) ...[
                    Text(q, style: T.body(weight: FontWeight.w600)),
                    const SizedBox(height: S.xs),
                    Text(a, style: T.body(color: C.textSecondary)),
                    const SizedBox(height: S.md),
                  ],
                  ButtonRow(
                    left: AppButton(
                      label: '駁回資格',
                      kind: BtnKind.secondary,
                      onPressed: () {
                        state.decideInstructor(c, false);
                        showToast(context, '已駁回教官資格');
                      },
                    ),
                    right: AppButton(
                      label: '通過',
                      onPressed: () {
                        state.decideInstructor(c, true);
                        showToast(context, '已通過教官資格');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PlanTab extends StatelessWidget {
  final List<CustomPlan> cases;
  final AppState state;
  const _PlanTab({required this.cases, required this.state});

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) {
      return const EmptyState(
        icon: Icons.playlist_add_check_outlined,
        title: '沒有待審的公開課表',
        message: '使用者申請公開的自訂訓練會進到這裡。',
      );
    }
    final overdue = cases.where((c) => c.reviewOverdue).length;
    final longest = cases
        .map((c) => appNow().difference(c.appliedAt!))
        .reduce((a, b) => a > b ? a : b);
    return ListView(
      padding:
          const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
      children: [
        _QueueHeader(count: cases.length, longest: longest, overdue: overdue),
        const SizedBox(height: S.md),
        for (final c in cases)
          Padding(
            padding: const EdgeInsets.only(bottom: S.md),
            child: _PlanCard(plan: c, state: state),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final CustomPlan plan;
  final AppState state;
  const _PlanCard({required this.plan, required this.state});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(plan.name, style: T.h3())),
                if (plan.reviewOverdue)
                  const TagBadge('已逾期', borderColor: C.statusError)
                else
                  Text('剩 ${plan.reviewDaysLeft} 天', style: T.caption()),
              ],
            ),
            const SizedBox(height: 2),
            Text('建立者 ${plan.author}　·　'
                '${appNow().difference(plan.appliedAt!).inDays} 天前申請',
                style: T.caption()),
            const SizedBox(height: S.md),
            for (final e in plan.contents)
              Padding(
                padding: const EdgeInsets.only(bottom: S.xs),
                child: Text('· $e', style: T.body()),
              ),
            const SizedBox(height: S.md),
            ButtonRow(
              left: AppButton(
                label: '未通過',
                kind: BtnKind.secondary,
                onPressed: () => _reject(context),
              ),
              right: AppButton(
                label: '通過公開',
                onPressed: () {
                  state.approvePublicPlan(plan);
                  showToast(context, '已通過，「${plan.name}」已公開');
                },
              ),
            ),
          ],
        ),
      );

  /// 駁回須附理由 —— 無理由則申請人不知為何被退、該改什麼再送。
  Future<void> _reject(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showAppDialog(
      context,
      title: '駁回「${plan.name}」',
      destructive: true,
      confirmLabel: '駁回',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('退回為已發布，作者仍可自己使用，可修改後重新申請，不限次數。',
              style: T.body(color: C.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: S.md),
          TextField(
            controller: controller,
            style: T.body(),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '駁回理由（作者會看到）',
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
    final reason = controller.text.trim();
    state.rejectPublicPlan(
        plan, reason.isEmpty ? '未附理由。' : reason);
    showToast(context, '已駁回，作者會看到駁回理由');
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 104, child: Text(label, style: T.caption())),
            Expanded(child: Text(value, style: T.body())),
          ],
        ),
      );
}
