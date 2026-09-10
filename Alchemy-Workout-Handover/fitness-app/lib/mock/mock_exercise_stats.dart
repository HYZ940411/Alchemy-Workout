import '../domain/models.dart';
import 'mock_data.dart';

/// 一次練這個動作的紀錄：日期、重量、次數。
typedef TrendPoint = ({String date, double weight, int reps});

/// 動作在「這位使用者」身上的統計 —— 資料來源為訓練紀錄 Aggregate。
///
/// 累積練習次數同時服務兩處：〈Read Model：動作庫〉的每筆項目欄位，
/// 以及〈Read Model：訓練歷史〉動作趨勢檢視的預設排序（由多到少）。
class ExerciseStat {
  final int count;

  /// 歷來的重量與次數，依時序排列（舊 → 新）。折線圖與逐次列表共用同一份。
  final List<TrendPoint> trend;

  const ExerciseStat({required this.count, this.trend = const []});
}

TrendPoint _p(String d, double w, int r) => (date: d, weight: w, reps: r);

/// 有練過的動作才有走勢；沒練過的落在空狀態。
final Map<String, ExerciseStat> kExerciseStats = {
  'bench': ExerciseStat(count: 41, trend: [
    _p('07/12', 50, 8), _p('07/19', 52.5, 8), _p('07/26', 55, 8),
    _p('08/02', 55, 9), _p('08/09', 57.5, 8), _p('08/16', 57.5, 9),
    _p('08/23', 60, 8), _p('08/25', 62.5, 7),
  ]),
  'squat': ExerciseStat(count: 36, trend: [
    _p('07/14', 70, 6), _p('07/21', 72.5, 6), _p('07/28', 75, 5),
    _p('08/04', 75, 6), _p('08/11', 77.5, 5), _p('08/18', 80, 5),
    _p('08/24', 80, 6),
  ]),
  'row': ExerciseStat(count: 33, trend: [
    _p('07/15', 45, 8), _p('07/22', 47.5, 8), _p('07/29', 50, 8),
    _p('08/05', 50, 9), _p('08/12', 52.5, 8), _p('08/19', 52.5, 9),
  ]),
  'deadlift': ExerciseStat(count: 22, trend: [
    _p('07/14', 90, 5), _p('07/28', 95, 5), _p('08/11', 100, 5),
    _p('08/24', 102.5, 4),
  ]),
  'ohp': ExerciseStat(count: 28, trend: [
    _p('07/12', 30, 8), _p('07/26', 32.5, 8), _p('08/09', 35, 8),
    _p('08/23', 35, 9),
  ]),
  'latpull': ExerciseStat(count: 25, trend: [
    _p('07/15', 40, 10), _p('07/29', 42.5, 10), _p('08/12', 45, 10),
  ]),
  'db_press': ExerciseStat(count: 19, trend: [
    _p('07/19', 20, 10), _p('08/02', 22, 10), _p('08/25', 22, 11),
  ]),
  'pushdown': ExerciseStat(count: 24, trend: [
    _p('07/12', 22.5, 12), _p('08/09', 25, 12), _p('08/25', 25, 13),
  ]),
  'curl': ExerciseStat(count: 21, trend: [
    _p('07/15', 12, 12), _p('08/05', 14, 10), _p('08/19', 14, 12),
  ]),
  'pullup': ExerciseStat(count: 17, trend: [
    _p('07/22', 0, 6), _p('08/05', 0, 8), _p('08/19', 2.5, 7),
  ]),
  'incline': ExerciseStat(count: 12, trend: [
    _p('07/26', 40, 8), _p('08/16', 42.5, 8),
  ]),
  'legpress': ExerciseStat(count: 14, trend: [
    _p('07/21', 120, 12), _p('08/11', 130, 12),
  ]),
  'lateral': ExerciseStat(count: 26, trend: [
    _p('07/12', 8, 15), _p('08/09', 10, 12), _p('08/23', 10, 14),
  ]),
  'crunch': ExerciseStat(count: 15, trend: [
    _p('08/04', 10, 20), _p('08/18', 12.5, 18),
  ]),
  'plank': ExerciseStat(count: 9),
  'dip': ExerciseStat(count: 0),
  // 有氧與自建動作同樣累積次數；有氧不記重量，故無重量走勢。
  'treadmill': ExerciseStat(count: 18),
  'rower': ExerciseStat(count: 6),
  'spin': ExerciseStat(count: 4),
  'elliptical': ExerciseStat(count: 0),
  'rope': ExerciseStat(count: 11),
  'c_erx': ExerciseStat(count: 13, trend: [
    _p('07/20', 0, 20), _p('08/10', 0, 25),
  ]),
  'c_farmer': ExerciseStat(count: 7, trend: [
    _p('08/03', 24, 1), _p('08/17', 28, 1),
  ]),
};

ExerciseStat statOf(String id) =>
    kExerciseStats[id] ?? const ExerciseStat(count: 0);

/// 動作趨勢檢視的預設排序：累積練習次數由多到少。
/// 主力動作長期固定，順序不隨每日訓練變動，使用者記得住位置。
List<Exercise> exercisesByFrequency() {
  final list = kAllExercises;
  list.sort((a, b) => statOf(b.id).count.compareTo(statOf(a.id).count));
  return list;
}
