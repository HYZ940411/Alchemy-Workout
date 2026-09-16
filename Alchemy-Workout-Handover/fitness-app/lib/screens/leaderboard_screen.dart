import 'package:flutter/material.dart';

import '../domain/leaderboard.dart';
import '../domain/rank.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Read Model：個人排行榜
/// 分組依使用者階級，每 10 階一組；名次視窗為自己上下各 10 名。
/// 即時性為延遲更新，畫面須標明資料更新時間。
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  bool weekly = true;

  @override
  void initState() {
    super.initState();
    // 週期結算由排程觸發；本專案於進入本頁時結算，效果相同 ——
    // 使用者看到的一定是已經結算過的狀態。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).settleDueBoards();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final rows = s.leaderboardWindow(weekly: weekly);
    final ago = s.now.difference(s.leaderboardUpdatedAt).inMinutes;

    // 名次視窗是空的 ＝ 這個榜還沒有資料（見 AppState.leaderboardWindow）。
    // 下面整頁都建立在「我在第幾名」上 —— 沒有名次就沒有東西好畫，
    // 而編一個出來正是 `[QA-02e]` 要移除的事。
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(S.base),
        child: EmptyState(
          icon: Icons.leaderboard_outlined,
          title: '排行榜尚未開放',
          message: '排名要跟平台上的其他人比，'
              '那份資料還在後端施工中。你的週／月累計分數照常在累積，'
              '開放後直接接得上。',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_outlined,
                      size: 18, color: AppColors.textDim),
                  const SizedBox(width: 8),
                  Text(
                    '所屬組別　${rankGroupLabel(s.rankGroupNow(weekly: weekly))}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '組別於週期起點鎖定，不隨週期內的階級提升改變。',
                style: TextStyle(color: AppColors.textFaint, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              for (final (v, label) in [(true, '週榜'), (false, '月榜')])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => weekly = v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: weekly == v ? AppColors.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: weekly == v ? AppColors.onAccent : AppColors.textDim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 自己的那一列固定在最上面：名次視窗有 21 列，捲下去就看不到自己了。
        const SizedBox(height: 12),
        _SelfCard(weekly: weekly),

        SectionLabel('名次視窗',
            trailing: ago <= 0 ? '剛剛更新' : '$ago 分鐘前更新'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            children: [for (final e in rows) _Row(e: e)],
          ),
        ),

        SectionLabel('本期獎勵',
            trailing: '組內前 $kRankPrizeCut 名'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                () {
                  // 走到這裡表示名次視窗不是空的，所以一定找得到自己。
                  final place = s.myPlace(weekly: weekly)!;
                  final p = prizeFor(place);
                  return p.isEmpty
                      ? '目前第 $place 名，'
                          '未達獎勵名次（組內前 $kRankPrizeCut 名）。'
                      : '目前第 $place 名，結算可得 ${p.display}。';
                }(),
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 6),
              const Text(
                '同分並列同一名次，皆發放該名次的獎勵；並列後的下一名次順延跳號。'
                '獎勵不會自動入帳 —— 結算發生在週一 / 每月 1 日 04:00，'
                '當下你不在 App，故補發至獎勵信箱等你領。',
                style: TextStyle(
                    color: AppColors.textFaint, fontSize: 11, height: 1.5),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: weekly ? '模擬週榜結算' : '模擬月結（含兩個團隊榜）',
                  kind: BtnKind.secondary,
                  onPressed: () {
                    weekly ? s.settleWeekly() : s.settleMonthly();
                    showToast(context, '已結算，獎勵補發至獎勵信箱');
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),

        if (s.leaderboardHistory.isNotEmpty) ...[
          const SectionLabel('排行榜歷史紀錄', trailing: '一經寫入不可修改'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (final h in s.leaderboardHistory.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${boardNames[h.board]}　${h.group}',
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                '第 ${h.place} 名　·　${h.score} 分　·　'
                                '${h.prize.isEmpty ? '未達獎勵名次' : h.prize.display}',
                                style: const TextStyle(
                                    color: AppColors.textDim, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 自己的固定卡：名次、分數、距獎勵名次還差幾分、本期還剩多久結算。
class _SelfCard extends StatelessWidget {
  final bool weekly;
  const _SelfCard({required this.weekly});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final rows = s.leaderboardWindow(weekly: weekly);
    final scores = rows.map((e) => e.score).toList();
    final me = rows.indexWhere((e) => e.isSelf);
    final gap = gapToPlace(scores, me, kRankPrizeCut);
    final left = timeToSettlement(
        weekly ? Board.personalWeekly : Board.personalMonthly, s.now);

    return Panel(
      border: C.actionOutline,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text('${rows[me].position}',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('你',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  gap == null
                      ? '已在獎勵名次內（組內前 $kRankPrizeCut 名）'
                      : '距離前 $kRankPrizeCut 還差 $gap 分',
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 11.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${weekly ? '本週' : '本月'}還剩 '
                  '${left.inDays} 天 ${left.inHours % 24} 小時結算',
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 11),
                ),
              ],
            ),
          ),
          Text('${rows[me].score}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final dynamic e;
  const _Row({required this.e});

  @override
  Widget build(BuildContext context) {
    final self = e.isSelf as bool;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: self ? AppColors.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: self
            ? Border.all(color: AppColors.accent.withValues(alpha: 0.55))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${e.position}',
              style: TextStyle(
                color: self ? AppColors.accent : AppColors.textDim,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              e.name as String,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: self ? FontWeight.w800 : FontWeight.w500,
                color: self ? AppColors.text : AppColors.textDim,
              ),
            ),
          ),
          Text(
            '${e.score}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: self ? AppColors.accent : AppColors.textDim,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
