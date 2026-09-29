/// 排行榜週期結算
///
/// 四個排行榜：個人週榜、個人月榜、團隊日常、團隊限時。
/// 週榜每週一 04:00 結算，其餘三個每月 1 日 04:00 結算。
library;

import 'platform_config.dart';

enum Board { personalWeekly, personalMonthly, teamDaily, teamTimed }

const boardNames = <Board, String>{
  Board.personalWeekly: '個人週榜',
  Board.personalMonthly: '個人月榜',
  Board.teamDaily: '團隊日常排行榜',
  Board.teamTimed: '團隊限時排行榜',
};

const boardMailSources = <Board, String>{
  Board.personalWeekly: '個人排行',
  Board.personalMonthly: '個人排行',
  Board.teamDaily: '團隊日常排行',
  Board.teamTimed: '團隊限時排行',
};

bool isWeekly(Board b) => b == Board.personalWeekly;

/// 名次。**同分並列同一名次，並列後的下一名次順延跳號**
/// （兩人並列第 2，下一位為第 4）。
///
/// 不以「先達到該分數者為先」決定順序：那只代表訓練時段較早，
/// 早上訓練者將永遠優於晚上訓練者，而偏好訓練時段是生活作息，不該影響名次。
List<int> placesOf(List<int> scoresDesc) {
  final out = <int>[];
  for (var i = 0; i < scoresDesc.length; i++) {
    if (i > 0 && scoresDesc[i] == scoresDesc[i - 1]) {
      out.add(out[i - 1]);
    } else {
      out.add(i + 1);
    }
  }
  return out;
}

/// 一份排行獎勵。
class RankPrize {
  final int coins;
  final int exp;
  const RankPrize(this.coins, this.exp);

  bool get isEmpty => coins == 0 && exp == 0;
  String get display => '金幣 $coins ＋ 經驗值 $exp';
}

/// 獎勵名次的門檻與各級數額 —— 屬〈獎勵定義 Aggregate〉，由管理員維護。
///
/// **模型未指定數額與名次門檻**，此處沿用假資料的第 1 名 300／120，
/// 其餘級距按比例遞減；四個榜共用同一張表。
int get kRankPrizeCut => platformConfig.i('reward', 'rankCut');

RankPrize prizeFor(int place) {
  if (place > kRankPrizeCut) return const RankPrize(0, 0);
  final k = switch (place) { 1 => '1', 2 => '2', 3 => '3', _ => 'Rest' };
  return RankPrize(
    platformConfig.i('reward', 'rank${k}Coin'),
    platformConfig.i('reward', 'rank${k}Exp'),
  );
}

/// 一筆排行榜歷史紀錄（獨立 Aggregate）。
///
/// **一經寫入不可修改**，為稽核用途：排行獎勵依組內名次發放，
/// 使用者質疑「我第 3 名卻沒拿到獎勵」時，沒有歷史就無從查證。
class LeaderboardHistory {
  final Board board;
  final DateTime periodFrom;
  final DateTime periodTo;

  /// 所屬組別。個人為階級區間（每 10 階一組），團隊為人數組（3/4/5 人組）。
  final String group;
  final String subject;
  final int place;
  final int score;
  final RankPrize prize;

  const LeaderboardHistory({
    required this.board,
    required this.periodFrom,
    required this.periodTo,
    required this.group,
    required this.subject,
    required this.place,
    required this.score,
    required this.prize,
  });
}

/// 距本週期結算還剩多久。
Duration timeToSettlement(Board board, DateTime now) {
  final (_, to) = periodOf(board, now);
  final left = to.difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// 距目標名次還差幾分。已在目標名次內者回傳 null。
int? gapToPlace(List<int> scoresDesc, int myIndex, int targetPlace) {
  if (myIndex < targetPlace) return null;
  if (scoresDesc.length < targetPlace) return null;
  return scoresDesc[targetPlace - 1] - scoresDesc[myIndex];
}

/// 週期起訖。週榜自週一 04:00；月榜自每月 1 日 04:00。
///
/// **04:00 換日**：00:00–03:59 仍屬前一自然日，沿用模型唯一的換日時點。
/// 少了這一步，週一與每月 1 日的凌晨會算出一段**不包含當下**的週期
/// —— 結算因此提早 4 小時觸發，那 4 小時掙得的分數被算進下一個週期。
(DateTime, DateTime) periodOf(Board board, DateTime now) {
  final d = now.hour < 4 ? now.subtract(const Duration(days: 1)) : now;
  if (isWeekly(board)) {
    final base = DateTime(d.year, d.month, d.day, 4);
    final start = base.subtract(Duration(days: (d.weekday - DateTime.monday) % 7));
    return (start, start.add(const Duration(days: 7)));
  }
  final start = DateTime(d.year, d.month, 1, 4);
  final end = DateTime(d.year, d.month + 1, 1, 4);
  return (start, end);
}

/// 一週的識別字串 —— 該週週一的 `YYYY-MM-DD`。
///
/// 給雲端當鍵用（週互動評分掛在關係文件上，一週一格）。**不含時分**：
/// 週界是週一 04:00，但同一週的任何時刻都該算出同一個鍵，
/// 帶上時分只會讓兩台裝置因為時鐘差一秒就寫出兩格。
///
/// 傳進來的應是 [periodOf] 算出的週起點。
String weekKeyOf(DateTime weekStart) =>
    '${weekStart.year.toString().padLeft(4, '0')}-'
    '${weekStart.month.toString().padLeft(2, '0')}-'
    '${weekStart.day.toString().padLeft(2, '0')}';
