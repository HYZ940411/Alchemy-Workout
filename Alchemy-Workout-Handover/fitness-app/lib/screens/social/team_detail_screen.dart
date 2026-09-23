import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'team_leaderboard_screen.dart';

/// 團隊詳情頁（別人的隊）
///
/// 這一頁要回答的只有一個問題：**要不要申請加入**。
/// 故成員名單、簡介、排名與人數都攤開；
/// 加入申請的 Precondition 一條都不藏，按不下去時直接寫出為什麼。
class TeamDetailScreen extends StatefulWidget {
  final PublicTeam team;
  const TeamDetailScreen({super.key, required this.team});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = widget.team;
    final blocked = s.joinBlockedReason(t);
    final applied = s.sentApplications.any((a) => a.name == t.name);

    final ranked = teamRanking(s.boardTeams, TeamBoard.daily, t.groupSize);
    final pos = ranked.indexWhere((x) => x.name == t.name);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('團隊')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: S.scrollBottom),
        children: [
          Container(
            width: double.infinity,
            color: C.bgSurface,
            padding: const EdgeInsets.fromLTRB(S.base, S.lg, S.base, S.lg),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: C.accentDeep,
                    borderRadius: BorderRadius.circular(R.card),
                  ),
                  child: Center(
                    child: Text(t.name.characters.first,
                        style: T.h1(color: C.onFill(C.accentDeep))),
                  ),
                ),
                const SizedBox(height: S.md),
                Text(t.name, style: T.h2(), textAlign: TextAlign.center),
                const SizedBox(height: S.sm),
                Wrap(
                  spacing: S.sm,
                  runSpacing: S.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    TagBadge(t.isPublic ? '公開' : '私密'),
                    TagBadge('${t.size} / ${t.capacity} 人'),
                    if (pos >= 0)
                      TagBadge('${t.groupSize} 人組日常第 ${pos + 1}',
                          borderColor: C.accentDeep)
                    else
                      // 本週期從未達 3 人者不參與排名，也不領獎勵，
                      // 但分數照常累積 —— 加總本身不需要因人數不足而停止。
                      TagBadge('未達 $kTeamMinSize 人，本月不列入排名'),
                  ],
                ),
                if (t.intro.isNotEmpty) ...[
                  const SizedBox(height: S.md),
                  Text(t.intro,
                      style: T.body(color: C.textSecondary),
                      textAlign: TextAlign.center),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle('成員', trailing: '${t.members.length} 人'),
                ListGroup(rows: [
                  for (var i = 0; i < t.members.length; i++)
                    ListRow(
                      leading: CircleAvatar(
                        radius: Sz.avatarList / 2,
                        backgroundColor: C.bgPage,
                        child: Text(t.members[i].name.characters.first,
                            style: T.caption(color: C.textPrimary)),
                      ),
                      title: t.members[i].name,
                      // 團隊只有隊長與成員兩種角色，沒有副隊長。
                      // 隊友現在的階級。名冊上那份是他加入當下存的。
                      subtitle: '${teamRoleNames[t.members[i].role]}'
                          '　·　階級 ${s.rankOf(t.members[i].name, uid: t.members[i].uid, fallback: t.members[i].rank)}',
                      showDivider: i != t.members.length - 1,
                    ),
                ]),

                const SectionTitle('兩個分數', trailing: '不合併，各自一個排行榜'),
                Row(
                  children: [
                    Expanded(
                      child: AppCard(
                        child: StatField(
                            label: '日常分數', value: '${t.dailyScore}'),
                      ),
                    ),
                    const SizedBox(width: S.md),
                    Expanded(
                      child: AppCard(
                        child: StatField(
                            label: '限時分數', value: '${t.timedScore}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: S.md),
                AppButton(
                  label: '看 ${t.groupSize} 人組排行榜',
                  kind: BtnKind.secondary,
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const TeamLeaderboardScreen())),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            S.base, S.md, S.base, MediaQuery.of(context).padding.bottom + S.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (blocked != null)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Text(blocked, style: T.caption()),
              ),
            if (applied)
              AppButton(
                label: '撤回申請',
                kind: BtnKind.secondary,
                onPressed: () {
                  s.withdrawApplication(t.name);
                  showToast(context, '已撤回，可以再申請');
                  setState(() {});
                },
              )
            else
              AppButton(
                label: '申請加入',
                onPressed: blocked != null
                    ? null
                    : () {
                        s.applyToTeam(t);
                        showToast(context, '已送出申請，7 天內未回應即失效');
                        setState(() {});
                      },
              ),
          ],
        ),
      ),
    );
  }
}
