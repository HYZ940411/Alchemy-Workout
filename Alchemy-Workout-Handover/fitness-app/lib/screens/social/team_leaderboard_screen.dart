import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 團隊排行榜
///
/// 兩個榜別衡量的是兩件事，故分數不合併、各自維護、各對應一種排行獎勵：
/// **日常**＝成員的訓練努力程度，**限時**＝團隊的動員參與率。
///
/// 榜單**只列同組別的隊伍**：日常分數維持加總、不改人均，
/// 小隊公平性改由依人數分級距分組承擔（3 / 4 / 5 人組各自排名）——
/// 與個人排行榜的階級分組同一套設計語言，不另訂補償係數。
class TeamLeaderboardScreen extends StatefulWidget {
  const TeamLeaderboardScreen({super.key});

  @override
  State<TeamLeaderboardScreen> createState() => _TeamLeaderboardScreenState();
}

class _TeamLeaderboardScreenState extends State<TeamLeaderboardScreen> {
  TeamBoard board = TeamBoard.daily;
  int? group;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final mine = s.myTeamOnBoard;
    final g = group ?? mine?.groupSize ?? kTeamMinSize;
    final ranked = teamRanking(s.boardTeams, board, g);
    final myPos = mine == null ? -1 : ranked.indexWhere((t) => t.id == mine.id);
    final gap = myPos < 0 ? null : gapToTopThree(ranked, myPos, board);
    final regroup = inRegroupWindow(s.now);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('團隊排行榜')),
      body: Column(
        children: [
          // 榜別
          Container(
            color: C.bgSurface,
            padding: const EdgeInsets.fromLTRB(S.base, S.md, S.base, S.md),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final b in TeamBoard.values)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: b == TeamBoard.daily ? S.sm : 0),
                          child: _Choice(
                            label: teamBoardNames[b]!,
                            selected: board == b,
                            onTap: () => setState(() => board = b),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: S.sm),
                Text(teamBoardHints[board]!, style: T.caption()),
              ],
            ),
          ),

          // 分組。只跟同組別的隊伍比，所以組別要看得見也選得動。
          Container(
            color: C.bgSurface,
            padding: const EdgeInsets.fromLTRB(S.base, 0, S.base, S.md),
            child: Row(
              children: [
                for (var n = kTeamMinSize; n <= kTeamCapacity; n++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: n == kTeamCapacity ? 0 : S.sm),
                      child: _Choice(
                        label: '$n 人組',
                        selected: g == n,
                        onTap: () => setState(() => group = n),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.base, S.base, S.scrollBottom),
              children: [
                if (regroup)
                  AppCard(
                    child: Text(
                      '重新分隊期（每月前 $kRegroupDays 天）：兩個團隊分數都不累加。'
                      '個人排行榜分數照常 —— 它限制的是「隊」，不是「練」。',
                      style: T.caption(),
                    ),
                  ),

                // 自己的隊固定在最上面，捲多遠都看得到。
                if (mine != null && myPos >= 0 && g == mine.groupSize) ...[
                  _Row(
                    pos: myPos + 1,
                    team: mine,
                    board: board,
                    highlight: true,
                    note: gap == null
                        ? '已在前三名'
                        : '距離前 3 還差 $gap 分',
                  ),
                  const SizedBox(height: S.md),
                ] else if (mine != null && g != mine.groupSize)
                  AppCard(
                    child: Text(
                      '你的隊在 ${mine.groupSize} 人組。'
                      '分組取本週期曾達到的最高成員數，之後有人退出也不會降回原組別。',
                      style: T.caption(),
                    ),
                  ),

                if (ranked.isEmpty)
                  const EmptyState(
                    icon: Icons.groups_2_outlined,
                    title: '這一組還沒有隊伍上榜',
                    message: '本週期曾達 3 人的隊伍才會列入排名',
                  )
                else
                  ListGroup(rows: [
                    for (var i = 0; i < ranked.length; i++)
                      _row(ranked[i], i, mine, i != ranked.length - 1),
                  ]),

                const SectionTitle('沒有上榜的隊伍', trailing: '分數照常累積'),
                AppCard(
                  child: Text(
                    '本週期自始至終未達 $kTeamMinSize 人的隊伍不參與排名、也不領獎勵，'
                    '但分數照常累積 —— 加總本身不需要因人數不足而停止。'
                    '曾經達到過 $kTeamMinSize 人的隊伍即使月底跌破，仍保留排名與獎勵資格。',
                    style: T.caption(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ListRow _row(PublicTeam t, int i, PublicTeam? mine, bool divider) {
    final isMine = mine != null && t.id == mine.id;
    return ListRow(
      leading: SizedBox(
        width: 28,
        child: Text('${i + 1}',
            style: T.numberM(
                color: isMine ? C.actionOutline : C.textSecondary)),
      ),
      title: t.name,
      subtitle: '${t.size} / ${t.capacity} 人',
      trailing: Text('${teamScoreOf(t, board)}', style: T.numberM()),
      showDivider: divider,
    );
  }
}

class _Row extends StatelessWidget {
  final int pos;
  final PublicTeam team;
  final TeamBoard board;
  final bool highlight;
  final String note;
  const _Row({
    required this.pos,
    required this.team,
    required this.board,
    required this.highlight,
    required this.note,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(S.base),
        decoration: BoxDecoration(
          color: C.bgSurface,
          borderRadius: BorderRadius.circular(R.card),
          // §4.4：選取／強調一律用 2px 外框，不換底色。
          border: Border.all(
              color: highlight ? C.actionOutline : C.lineDivider,
              width: highlight ? 2 : 1),
        ),
        child: Row(
          children: [
            SizedBox(width: 28, child: Text('$pos', style: T.numberM())),
            const SizedBox(width: S.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name, style: T.body(weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(note, style: T.caption()),
                ],
              ),
            ),
            Text('${teamScoreOf(team, board)}', style: T.numberM()),
          ],
        ),
      );
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Choice(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.control),
        child: Container(
          height: Sz.buttonMinHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.control),
            border: Border.all(
              color: selected ? C.actionOutline : C.lineDivider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(label,
              style: T.body(
                  weight: selected ? FontWeight.w700 : null,
                  color: selected ? C.actionOutline : C.textSecondary)),
        ),
      );
}
