import '../domain/community.dart';
import '../domain/leaderboard.dart';
import 'team_data.dart';

/// 團隊排行榜月結算（`[QA-05]`，使用者裁決 D，2026-10-17）。
///
/// 每月初由管理員按一次「結算上月團隊排行榜」：用雲端各隊**上個月**的分數算出名次與獎勵，
/// 寫成一份不可修改的結果；隊員登入後各自從這裡領進獎勵信箱。
/// 免費方案沒有排程，所以由管理員觸發；日後升 Blaze 改成排程，這份結果的形狀不用變。

/// 一支隊伍在一個榜上的結算結果。
class TeamBoardResult {
  final Board board;

  /// 日常榜是「N 人組」，限時榜是「全部隊伍」。
  final String group;
  final int place;
  final int score;
  final RankPrize prize;

  const TeamBoardResult({
    required this.board,
    required this.group,
    required this.place,
    required this.score,
    required this.prize,
  });
}

/// 一支隊伍一個月的結算結果（兩個榜各一份）。
class TeamSettlementResult {
  final String period;
  final String teamId;
  final String teamName;

  /// **結算當下**在那支隊上的成員 uid。領取資格看它，不看領取當下的隊伍。
  final List<String> memberUids;
  final TeamBoardResult daily;
  final TeamBoardResult timed;

  const TeamSettlementResult({
    required this.period,
    required this.teamId,
    required this.teamName,
    required this.memberUids,
    required this.daily,
    required this.timed,
  });
}

/// 單次批次寫入上限是 500 筆，扣掉標記與餘裕。超過就拒絕，**目前不支援分批**。
const int kMaxSettlementTeams = 450;

/// 上一個月的月份鍵（`yyyy-MM`）。
String previousMonthKey(String period) {
  final y = int.parse(period.substring(0, 4));
  final m = int.parse(period.substring(5, 7));
  return m == 1
      ? '${(y - 1).toString().padLeft(4, '0')}-12'
      : '${y.toString().padLeft(4, '0')}-${(m - 1).toString().padLeft(2, '0')}';
}

/// 算出 [period] 這個月的結算結果。**純函式**：只看傳進來的隊伍資料。
///
/// - 已解散的隊伍不上榜；本月從未成局（曾達最高人數 < 3）的隊伍也不上榜、不領獎勵。
/// - 日常榜依人數分組（3／4／5 人組各自排名），限時榜不分組 —— 見 [isGroupedBoard]。
/// - 同分並列同一名次，並列後順延跳號（[placesOf]）。
/// - 獎勵走百分比級距（[teamPrizeFor]）：分數是 0 的隊什麼都沒有，但結果照寫（沒得獎也要留紀錄）。
List<TeamSettlementResult> computeTeamSettlement(
  List<CloudTeam> teams,
  String period,
) {
  final live = [for (final t in teams) if (!t.disbanded) t];
  final byId = {for (final t in live) t.id: t};

  final pub = [
    for (final t in live)
      PublicTeam(
        t.name,
        t.members.length,
        t.capacity,
        id: t.id,
        isPublic: t.isPublic,
        dailyScore: (t.contribByMonth[period] ?? const <String, int>{})
            .values
            .fold<int>(0, (a, b) => a + b),
        timedScore: t.timedByMonth[period] ?? 0,
        // 曾達最高人數；舊資料沒有這個欄位時退回目前人數。
        peakSize: t.peakSize > 0 ? t.peakSize : t.members.length,
      ),
  ];

  // 日常：每個人數組各自排名。
  final daily = <String, TeamBoardResult>{};
  for (var g = kTeamMinSize; g <= kTeamCapacity; g++) {
    final ranked = teamRanking(pub, TeamBoard.daily, g);
    final places = placesOf([for (final t in ranked) t.dailyScore]);
    for (var i = 0; i < ranked.length; i++) {
      daily[ranked[i].id] = TeamBoardResult(
        board: Board.teamDaily,
        group: '$g 人組',
        place: places[i],
        score: ranked[i].dailyScore,
        prize: teamPrizeFor(Board.teamDaily,
            place: places[i], teamsInGroup: ranked.length, score: ranked[i].dailyScore),
      );
    }
  }

  // 限時：不分組，所有符合資格的隊伍排同一張榜。
  final timed = <String, TeamBoardResult>{};
  final rankedAll = teamRanking(pub, TeamBoard.timed, kTeamMinSize);
  final placesAll = placesOf([for (final t in rankedAll) t.timedScore]);
  for (var i = 0; i < rankedAll.length; i++) {
    timed[rankedAll[i].id] = TeamBoardResult(
      board: Board.teamTimed,
      group: '全部隊伍',
      place: placesAll[i],
      score: rankedAll[i].timedScore,
      prize: teamPrizeFor(Board.teamTimed,
          place: placesAll[i],
          teamsInGroup: rankedAll.length,
          score: rankedAll[i].timedScore),
    );
  }

  return [
    for (final id in daily.keys)
      TeamSettlementResult(
        period: period,
        teamId: id,
        teamName: byId[id]!.name,
        memberUids: byId[id]!.members.keys.toList(),
        daily: daily[id]!,
        timed: timed[id]!,
      ),
  ];
}

/// 結算的雲端讀寫。由 `FirestoreTeams` 一併實作 —— 接線不用多一條。
abstract class TeamSettlementSource {
  /// 這個月結算過了嗎。回傳結算時間；沒結算過回 null。
  Future<DateTime?> settledAt(String period);

  /// 讀全部隊伍（每支 1 次讀取，每月 1 次）。
  Future<List<CloudTeam>> allTeams();

  /// 一次寫入標記與全部結果。**標記只能建立一次**，所以同一個月不會被結算兩次。
  Future<void> publish(String period, List<TeamSettlementResult> results,
      {required String by});

  /// 讀這支隊伍這個月的結果。沒結算、或這支隊不在結果裡，回 null。
  Future<TeamSettlementResult?> resultFor(String period, String teamId);
}
