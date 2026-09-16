/// 動作趨勢 —— 〈Read Model：訓練歷史〉的動作趨勢檢視。
///
/// **這是推導值，不是儲存欄位。** 唯一的事實來源是訓練紀錄 Aggregate；
/// 另存一份「累積練習次數」的話，補登或刪除一場訓練就會讓兩邊對不起來，
/// 而且不會有任何錯誤訊息 —— 使用者只會發現數字怪怪的。
///
/// 這個檔案刻意不認得 `HistoryEntry`（它目前住在 `mock/`）：
/// 呼叫端把訓練紀錄攤平成下面那個最小形狀再傳進來，
/// 領域層就不必反過來依賴假資料那一層。
library;

/// 一次練這個動作的紀錄：日期、重量、次數。
typedef TrendPoint = ({String date, double weight, int reps});

/// 攤平後的一筆訓練紀錄：哪一天、練了哪個動作、逐組成績。
typedef WorkoutRow = ({DateTime date, String id, List<(double, int)> sets});

/// 動作在「這位使用者」身上的統計。
class ExerciseStat {
  /// 累積練習次數 —— **練過幾場，不是做過幾組**。
  /// 同時服務〈Read Model：動作庫〉的每筆項目欄位，
  /// 以及動作趨勢檢視的預設排序（由多到少）。
  final int count;

  /// 歷來的重量與次數，依時序排列（舊 → 新）。折線圖與逐次列表共用同一份。
  final List<TrendPoint> trend;

  const ExerciseStat({required this.count, this.trend = const []});
}

String _md(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// 由訓練紀錄推導每個動作的統計。
///
/// **一場訓練在折線圖上只佔一個點**，取當場最重的那一組 ——
/// 逐組全畫的話，熱身組會把曲線壓成鋸齒，看不出長期是不是在進步。
/// 同重量時取次數多的那組，理由相同（那一組才是當天的上限）。
Map<String, ExerciseStat> statsFrom(Iterable<WorkoutRow> rows) {
  final counts = <String, int>{};
  final points = <String, List<(DateTime, TrendPoint)>>{};

  for (final r in rows) {
    if (r.sets.isEmpty) continue;
    counts[r.id] = (counts[r.id] ?? 0) + 1;

    var best = r.sets.first;
    for (final s in r.sets) {
      if (s.$1 > best.$1 || (s.$1 == best.$1 && s.$2 > best.$2)) best = s;
    }
    (points[r.id] ??= []).add(
      (r.date, (date: _md(r.date), weight: best.$1, reps: best.$2)),
    );
  }

  return {
    for (final id in counts.keys)
      id: ExerciseStat(
        count: counts[id]!,
        trend: [
          for (final p in points[id]!..sort((a, b) => a.$1.compareTo(b.$1)))
            p.$2,
        ],
      ),
  };
}
