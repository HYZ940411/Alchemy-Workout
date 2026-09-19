import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'team_create_screen.dart';
import 'team_detail_screen.dart';
import 'team_leaderboard_screen.dart';

/// 我的團隊頁 ＋ 團隊搜尋 —— 兩條加入路徑：隊長邀請（認識的人）、公開招募申請。
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return s.myTeam == null ? const _TeamSearch() : _MyTeam(team: s.myTeam!);
  }
}

class _MyTeam extends StatelessWidget {
  final Team team;
  const _MyTeam({required this.team});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isLeader =
        team.members.any((m) => m.name == '你' && m.role == TeamRole.leader);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(team.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  if (isLeader)
                    // 隊長已變更團隊可見性。可事後變更 ——
                    // 團隊性質本會隨時間改變，鎖死只會逼人解散重建。
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _toggleVisibility(context, s, team),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Pill(team.isPublic ? '公開' : '私密',
                              color: team.isPublic
                                  ? AppColors.accent
                                  : AppColors.textDim),
                          const SizedBox(width: 4),
                          const Icon(Icons.swap_horiz,
                              size: 15, color: AppColors.textFaint),
                        ],
                      ),
                    )
                  else
                    Pill(team.isPublic ? '公開' : '私密',
                        color: team.isPublic
                            ? AppColors.accent
                            : AppColors.textDim),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: '目前人數',
                      value: '${team.members.length}',
                      unit: '/ ${team.capacity}',
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: '鎖定分組',
                      value: '${team.lockedGroupSize}',
                      unit: '人組',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionLabel('兩個排行榜',
            trailing: '${team.lockedGroupSize} 人組'),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '團隊日常分數',
                  value: '${team.dailyScore}',
                  unit: '第 ${team.dailyRankPos} 名',
                  valueColor: AppColors.accent,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '團隊限時分數',
                  value: '${team.timedScore}',
                  unit: '第 ${team.timedRankPos} 名',
                  valueColor: C.accentDeep,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: '看團隊排行榜',
            kind: BtnKind.secondary,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TeamLeaderboardScreen())),
          ),
        ),
        // 限時任務是**每日**指派、當日有效，不是每週 ——
        // 標題寫「本週」，旁邊寫「當日有效」，同一行自相矛盾。
        const SectionLabel('今日限時任務', trailing: '全平台統一，當日有效'),
        _TimedTaskCard(state: s),
        const SectionLabel('成員清單'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final m in team.members)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.surfaceAlt,
                        child: Text(m.name.characters.first,
                            style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            // 各成員的本隊已貢獻分數。加總即為月累計日常分數 ——
                            // 沒有這一列，團隊分數就是個查不回去的孤兒數字。
                            Text(
                              '${m.rank} 階　·　本隊已貢獻 '
                              '${team.contributions[m.name] ?? 0} 分',
                              style: const TextStyle(
                                  color: AppColors.textDim, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      if (m.role == TeamRole.leader)
                        const Pill('隊長')
                      else if (isLeader) ...[
                        IconButton(
                          onPressed: () => _transfer(context, s, m),
                          tooltip: '轉讓隊長',
                          icon: const Icon(Icons.workspace_premium_outlined,
                              size: 16, color: AppColors.textFaint),
                        ),
                        IconButton(
                          onPressed: () => _kick(context, s, m),
                          tooltip: '踢除成員',
                          icon: const Icon(Icons.person_remove_outlined,
                              size: 16, color: AppColors.textFaint),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (isLeader && team.applications.isNotEmpty) ...[
          const SectionLabel('待回應的加入申請', trailing: '各自 7 天逾期'),
          for (final r in team.applications) _RequestRow(req: r, isInvite: false),
        ],
        if (isLeader && team.invites.isNotEmpty) ...[
          const SectionLabel('待回應的邀請', trailing: '各自 7 天逾期'),
          for (final r in team.invites) _RequestRow(req: r, isInvite: true),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            if (isLeader)
              Expanded(
                child: AppButton(
                  label: team.isFull ? '團隊已滿 5 人' : '邀請成員',
                  // Precondition：團隊人數未達上限 5 人（含隊長）。
                  onPressed: team.isFull ? null : () => _invite(context, s),
                  kind: BtnKind.secondary,
                ),
              ),
            if (isLeader) const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: s.leaveTeamOutcome().disbanded ? '解散團隊' : '退出團隊',
                onPressed: () => _leave(context, s),
                kind: BtnKind.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleVisibility(
      BuildContext context, AppState s, Team team) async {
    final toPrivate = team.isPublic;
    final ok = await showAppDialog(
      context,
      title: toPrivate ? '改為私密團隊？' : '改為公開團隊？',
      message: toPrivate
          // 既有待處理的加入申請一律保留 —— 申請已送出為既成事實，
          // 申請者不會知道隊長改了設定，無聲作廢的體驗差。
          ? '之後不會出現在搜尋結果，也不再接受新的加入申請。'
              '已經送出的 ${team.applications.length} 筆申請照樣留著，你仍可核准或拒絕。'
          : '之後可被搜尋，也開始接受加入申請。',
      confirmLabel: toPrivate ? '改為私密' : '改為公開',
    );
    if (ok != true || !context.mounted) return;
    s.setTeamVisibility(!toPrivate);
    showToast(context, toPrivate ? '已改為私密' : '已改為公開');
  }

  Future<void> _leave(BuildContext context, AppState s) async {
    final o = s.leaveTeamOutcome();
    final ok = await showAppDialog(
      context,
      title: o.disbanded ? '解散團隊？' : '退出團隊？',
      message: o.disbanded
          // 團隊僅剩隊長一人時，隊長退出即解散，不進入無隊長狀態。
          ? '隊上只剩你一個人，退出即解散。解散為終止狀態，不可復原；'
              '兩個團隊分數凍結於當下，本週期不參與排名也不發獎勵。'
          : o.newLeader != null
              // 未指定接任者即退出者，自動轉讓給最早加入的成員。
              ? '你是隊長，退出時隊長會自動轉讓給最早加入的 ${o.newLeader}。'
                  '轉讓完成後你才脫離團隊，退出仍適用 12 小時換隊冷卻。'
              : '退出後 12 小時內不可加入或建立團隊。'
                  '已貢獻的團隊分數留在原團隊，不隨你離開而扣除。',
      confirmLabel: o.disbanded ? '解散' : '退出',
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    s.leaveTeam();
    showToast(context, o.disbanded ? '團隊已解散' : '已退出團隊');
  }

  /// 隊長已轉讓。主動轉讓與退出時的自動轉讓為多對一，這是主動的那條。
  Future<void> _transfer(
      BuildContext context, AppState s, TeamMember m) async {
    final ok = await showAppDialog(
      context,
      title: '把隊長轉讓給「${m.name}」？',
      message: '轉讓後你成為一般成員，核准申請、邀請成員、指派與踢人都改由他負責。'
          '團隊不會進入無隊長狀態。',
      confirmLabel: '轉讓',
    );
    if (ok != true || !context.mounted) return;
    s.transferLeader(m);
    showToast(context, '已轉讓給 ${m.name}');
  }

  /// 隊長已踢除成員。被踢除者不適用 12 小時換隊冷卻期。
  Future<void> _kick(BuildContext context, AppState s, TeamMember m) async {
    final ok = await showAppDialog(
      context,
      title: '踢除「${m.name}」？',
      message: '團隊人數 −1。對方可立即加入或建立其他團隊，不受 12 小時換隊冷卻期限制'
          '——該次離隊非其本人所為。他已貢獻的團隊分數留在本隊。',
      confirmLabel: '踢除',
      destructive: true,
    );
    if (ok != true) return;
    s.kickMember(m);
  }

  /// 隊長已邀請成員。邀請自送出起算 7 天未回應即逾期。
  Future<void> _invite(BuildContext context, AppState s) async {
    final controller = TextEditingController();
    final ok = await showAppDialog(
      context,
      title: '邀請成員',
      confirmLabel: '送出邀請',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('待回應的邀請不佔用 5 人名額；7 天未回應即逾期，屆時可再次邀請。',
              style: T.body(color: C.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: S.md),
          TextField(
            controller: controller,
            style: T.body(),
            decoration: InputDecoration(
              hintText: '對方的暱稱',
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
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final sent = s.inviteMember(name, 20);
    showToast(context, sent ? '已邀請 $name，7 天內有效' : '已邀請過 $name');
  }
}

/// 限時任務（〈團隊任務流程〉）
///
/// 全平台統一 —— 一個指派日只有一組，所有團隊相同。
/// 有效時窗為指派當日（當地 04:00 換日），隔日失效、不可補做。
class _TimedTaskCard extends StatelessWidget {
  final AppState state;
  const _TimedTaskCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.timedTask;
    final expired = state.timedTaskExpired;
    final tally = state.timedTally;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.title, style: T.h3())),
              TagBadge(
                expired ? '已失效' : '今日有效',
                borderColor: expired ? C.lineDivider : C.accentInfo,
              ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text(t.detail, style: T.caption()),
          const SizedBox(height: S.base),

          // 各成員完成狀態 —— 名單向團隊要，不從任務裡拿。
          // 任務是全平台統一的一份，名單卻屬於團隊：換隊或重建之後，
          // 從任務裡拿名單就會列出上一支隊伍的人。
          for (final m in tally.members)
            Padding(
              padding: const EdgeInsets.only(bottom: S.sm),
              child: Row(
                children: [
                  Icon(
                    tally.credited.contains(m.name)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: Sz.iconDense,
                    color: tally.credited.contains(m.name)
                        ? C.statusSuccess
                        : C.textSecondary,
                  ),
                  const SizedBox(width: S.sm),
                  Expanded(child: Text(m.name, style: T.body())),
                  // 「提醒」是催隊友的，自己那一列不該有 —— 催自己沒有意義。
                  // 自己還沒做的話，該做的是去把它做完，不是按提醒。
                  if (!tally.credited.contains(m.name) &&
                      !expired &&
                      m.name != state.displayName)
                    GestureDetector(
                      onTap: () => showToast(context, '已提醒 ${m.name}'),
                      child: const TagBadge('提醒'),
                    ),
                ],
              ),
            ),

          if (state.timedDoneElsewhere)
            Padding(
              padding: const EdgeInsets.only(bottom: S.sm),
              child: Text(
                '你今天已經完成過這項任務，但那一次的分數記在前一支隊伍帳上。',
                style: T.caption(),
              ),
            ),

          const Divider(height: S.lg, color: C.lineDivider),
          AppProgress(
            value: tally.total == 0 ? 0 : tally.doneCount / tally.total,
            label: '已完成 ${tally.doneCount} / ${tally.total} 人',
            trailingLabel: '${tally.score} 分',
          ),
          const SizedBox(height: S.md),
          Text(
            tally.allDone
                ? '全員完成，已加成 ＋$kTimedTaskAllBonus 分'
                : '每人 $kTimedTaskPerMember 分，全員完成再加 $kTimedTaskAllBonus 分',
            style: T.caption(),
          ),
          if (state.canClaimTimedReward) ...[
            const SizedBox(height: S.md),
            AppButton(
              label: '領取限時任務獎勵　'
                  '$kTimedRewardExp EXP · $kTimedRewardCoin 金幣',
              onPressed: () {
                final r = state.claimTimedReward()!;
                showToast(context, '已領取 ${r.exp} EXP、${r.coins} 金幣');
              },
            ),
            const SizedBox(height: S.sm),
            Text(
              '「當日有效」管的是完成任務的期限，不是領獎的期限：'
              '沒領到的當日結束會補發到獎勵信箱，不作廢。',
              style: T.caption(),
            ),
          ] else if (state.timedRewardClaimed) ...[
            const SizedBox(height: S.md),
            Text('本日獎勵已領取。', style: T.caption()),
          ],
          if (!expired && !t.doneBy(state.displayName)) ...[
            const SizedBox(height: S.md),
            AppButton(
              label: '開始限時任務',
              onPressed: state.completeTimedTask,
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final PendingRequest req;
  final bool isInvite;
  const _RequestRow({required this.req, required this.isInvite});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final left = req.expiresAt.difference(s.now);
    final gone = s.expired(req);
    final full = s.myTeam?.isFull ?? true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(req.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    gone
                        // 逾期後該筆失效，對方可再次申請、隊長可再次邀請。
                        ? '已逾期，${isInvite ? '可再次邀請' : '對方可再次申請'}'
                        : '階級 ${req.rank}　·　'
                            '${left.inDays} 天 ${left.inHours % 24} 小時後逾期',
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (!isInvite && !gone) ...[
              SizedBox(
                width: 68,
                child: AppButton(
                  label: '拒絕',
                  kind: BtnKind.secondary,
                  onPressed: () {
                    s.rejectApplication(req);
                    showToast(context, '已拒絕，對方可再次申請');
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 68,
                child: AppButton(
                  label: full ? '已滿' : '同意',
                  // 待回應的申請不佔名額，超收由本 Command 當下擋下。
                  onPressed: full
                      ? null
                      : () {
                          s.approveApplication(req);
                          showToast(context, '${req.name} 已加入團隊');
                        },
                ),
              ),
            ],
            if (isInvite && !gone)
              SizedBox(
                width: 80,
                child: AppButton(
                  label: '取消邀請',
                  kind: BtnKind.secondary,
                  onPressed: () {
                    s.cancelInvite(req);
                    showToast(context, '已取消邀請');
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TeamSearch extends StatefulWidget {
  const _TeamSearch();

  @override
  State<_TeamSearch> createState() => _TeamSearchState();
}

class _TeamSearchState extends State<_TeamSearch> {
  /// 冷卻期是倒數，畫面得跟著走。沒有這個 Timer，剩餘時間會停在按下退出的
  /// 那一刻，時間到了訊息也不會消失 —— 使用者只會看到「還是在冷卻」。
  Timer? tick;

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  static String _left(Duration d) => d.inHours > 0
      ? '${d.inHours} 小時 ${d.inMinutes % 60} 分'
      : d.inMinutes > 0
          ? '${d.inMinutes} 分 ${d.inSeconds % 60} 秒'
          : '${d.inSeconds} 秒';

  void _keepTicking(bool cooling) {
    if (cooling && tick == null) {
      tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!cooling && tick != null) {
      tick!.cancel();
      tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // 私密團隊不可被搜尋 —— 只能由隊長邀請加入。
    final teams = s.publicTeams.where((t) => t.isPublic).toList()
      ..sort((a, b) => (b.viaFollowing ? 1 : 0) - (a.viaFollowing ? 1 : 0));
    // 判定與按鈕的停用條件用同一個門檻，免得出現「按鈕是暗的但沒說為什麼」。
    final cooling = s.switchCooldownLeft > Duration.zero;
    _keepTicking(cooling);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('你目前沒有團隊',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                cooling
                    ? '換隊冷卻剩餘 ${_left(s.switchCooldownLeft)}，'
                        '期間不可申請加入別人的隊。自己開一隊不受冷卻限制。'
                    : '可以自己開一隊，也可以申請加入公開團隊或等待隊長邀請。',
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: '建立團隊',
                  // 建立本身無門檻；擋人的只有一人一隊與換隊冷卻。
                  onPressed: s.createBlockedReason() != null
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const TeamCreateScreen())),
                  kind: BtnKind.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: '搜尋團隊名稱',
            hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 19, color: AppColors.textFaint),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: AppColors.line),
            ),
          ),
        ),
        const SectionLabel('公開團隊'),
        for (final t in teams)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TeamDetailScreen(team: t))),
              child: Panel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(t.name,
                                style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                            if (t.viaFollowing) ...[
                              const SizedBox(width: 7),
                              const Pill('關注的人在這隊'),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${t.size} / ${t.capacity} 人',
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textFaint),
                ],
              ),
            ),
            ),
          ),
      ],
    );
  }
}