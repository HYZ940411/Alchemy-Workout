/// 偏好訓練時段與訓練體驗評分 —— 新手任務的兩個收尾步驟
///
/// 兩者都掛在「使用者已完成新手任務」之後，也都**可跳過**：
/// 引導的收尾若擋在獎勵前面，取得的會是筆數而非有用的資料。
library;

// 評分對象類型沿用 admin.dart 既有的那一個 —— 管理員的評分彙總讀的是同一個
// Aggregate，兩邊各定義一份列舉遲早會對不起來。
import 'admin.dart' show RatingTarget;

export 'admin.dart' show RatingTarget, ratingTargetNames;

/// 時段區間。以「當日 00:00 起算的分鐘數」表示。
///
/// 粒度 30 分鐘，且**不得跨日** —— 跨日的區間會使「某一天有沒有空」
/// 這個問題答不出來，而訓練提醒正是逐日發送的。
class TimeRange {
  final int startMin;
  final int endMin;
  const TimeRange(this.startMin, this.endMin);

  bool get valid =>
      startMin >= 0 &&
      endMin <= kMinutesPerDay &&
      startMin < endMin &&
      startMin % kSlotMinutes == 0 &&
      endMin % kSlotMinutes == 0;

  bool overlaps(TimeRange o) => startMin < o.endMin && o.startMin < endMin;

  /// 相鄰（首尾相接）也算可合併 —— 19:00–20:00 與 20:00–21:00
  /// 是同一段有空的時間，分成兩筆只是操作痕跡。
  bool touches(TimeRange o) => startMin <= o.endMin && o.startMin <= endMin;

  String get label => '${_hm(startMin)}–${_hm(endMin)}';

  static String _hm(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is TimeRange &&
      other.startMin == startMin &&
      other.endMin == endMin;

  @override
  int get hashCode => Object.hash(startMin, endMin);
}

const int kSlotMinutes = 30;
const int kMinutesPerDay = 24 * 60;

/// 星期一到日。欄位結構為：星期（7 天）→ 該日的區間集合 → 每個區間的起訖。
const weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 偏好訓練時段。語意是「**有空可以訓練**的時段」，不是「慣常訓練的時段」——
/// 新手還沒形成訓練習慣，答不出慣常時段，但答得出何時有空。
class PreferredTimes {
  /// 索引 0–6 對應週一到週日。
  final List<List<TimeRange>> byDay;

  PreferredTimes(List<List<TimeRange>> byDay)
      : byDay = [for (final d in byDay) normalize(d)];

  PreferredTimes.empty() : byDay = List.generate(7, (_) => <TimeRange>[]);

  /// 跳過者七天皆空。**某日的區間集合為空，代表該日無空閒時段，該日不發送訓練提醒**
  /// —— 跳過的效果天然落在這條既有規則上，不需要另一條規則。
  bool get isEmpty => byDay.every((d) => d.isEmpty);

  int get filledDays => byDay.where((d) => d.isNotEmpty).length;

  PreferredTimes withRange(int day, TimeRange r) {
    final next = [for (final d in byDay) [...d]];
    next[day].add(r);
    return PreferredTimes(next);
  }

  PreferredTimes withoutRange(int day, TimeRange r) {
    final next = [for (final d in byDay) [...d]];
    next[day].remove(r);
    return PreferredTimes(next);
  }

  /// 把某一天的區間排序並合併重疊與相鄰者。
  static List<TimeRange> normalize(List<TimeRange> day) {
    final sorted = [...day.where((r) => r.valid)]
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    final out = <TimeRange>[];
    for (final r in sorted) {
      if (out.isNotEmpty && out.last.touches(r)) {
        final last = out.removeLast();
        out.add(TimeRange(
          last.startMin < r.startMin ? last.startMin : r.startMin,
          last.endMin > r.endMin ? last.endMin : r.endMin,
        ));
      } else {
        out.add(r);
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// 訓練體驗評分
// ---------------------------------------------------------------------------

/// 一筆訓練體驗評分。獨立 Aggregate，不併入訓練紀錄或訓練計畫 ——
/// 管理員的評分彙總要逐筆下鑽，掛在別人底下就得跨表拼湊。
///
/// 唯一鍵為 評分者 ＋ 對象類型 ＋ 對象 ID：**同一人對同一個對象終身僅一筆**。
/// 但**可修改**（覆蓋原值，不另立 Event）—— 不可修改的話，
/// 誤觸就是永久寫入一筆錯的資料且無從更正。
class ExperienceRating {
  final RatingTarget target;
  final String targetId;
  final String rater;
  int stars;
  String? feedback;
  DateTime at;

  ExperienceRating({
    required this.target,
    required this.targetId,
    required this.rater,
    required this.stars,
    required this.at,
    this.feedback,
  });
}

/// 星等必填且限 1–5；文字回饋選填，可為空值。
bool isValidStars(int s) => s >= 1 && s <= 5;

/// 新手任務為單一範本，故對象 ID 固定。
const String kNoviceTaskId = 'novice-template';

/// 訓練提醒改由系統依訓練時戳推算的門檻：最近 4 週至少這麼多筆訓練紀錄。
const int kReminderInferMinWorkouts = 6;
