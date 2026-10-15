import 'clock.dart';
import 'models.dart';
import 'rewards.dart';

/// 自訂訓練 Aggregate 的狀態機。
/// 草稿 → 已儲存 → 已發布 → 已申請公開 → 已公開；已刪除為終止狀態。
enum CustomPlanState { saved, published, pendingPublic, public, rejected }

const customPlanStateNames = <CustomPlanState, String>{
  CustomPlanState.saved: '已儲存',
  CustomPlanState.published: '已發布',
  CustomPlanState.pendingPublic: '已申請公開',
  CustomPlanState.public: '已公開',
  CustomPlanState.rejected: '審核未通過',
};

/// 公開訓練審核的時限：14 天。
/// 申請人於等待期間仍為已發布、自己可用，無實質損失，故為四類審核中最長。
const kPublicPlanReviewDays = 14;

class CustomPlan {
  final String id;
  String name;

  /// 課表內容 —— **與訓練計畫的三層結構完全一致**（模型明訂）。
  ///
  /// 自訂訓練的用途就是拿來練，所以它存的必須是可執行的課表本身，
  /// 不是「幾個動作」這種摘要。存摘要的話，這份課表既練不了、
  /// 打開編輯器也讀不回來，改一次就把原內容洗掉。
  List<PlanExercise> exercises;

  /// **我自己**用這份課表訓練的次數，取自訓練紀錄的課表 ID。
  /// 回答的是「這份課表我還在用嗎」—— 正是決定該不該刪除以釋放名額的依據。
  int myUses;

  /// 建立者。他人的課表也會進管理員的待審佇列。
  final String author;
  final bool isMine;

  CustomPlanState state;

  /// 與狀態正交的獨立欄位，預設否。
  bool visibleToFollowers;

  /// 轉為「已申請公開」的時點。審核時限自此起算。
  DateTime? appliedAt;

  /// 「公開訓練審核未通過」時呈現。
  String? rejectReason;

  CustomPlan({
    required this.id,
    required this.name,
    required this.exercises,
    required this.myUses,
    required this.state,
    this.author = '你',
    this.isMine = true,
    this.visibleToFollowers = false,
    this.appliedAt,
    this.rejectReason,
  });

  int get exerciseCount => exercises.length;

  int get totalSets => exercises.fold(0, (a, e) => a + e.planned.length);

  /// 課表內容的文字摘要，供管理員審核佇列呈現。**由內容推導**，
  /// 不另存一份 —— 存兩份就會有兩份對不起來的事實。
  List<String> get contents => [
        for (final e in exercises) _line(e),
      ];

  static String _line(PlanExercise e) {
    final n = e.planned.length;
    if (e.planned.isEmpty) return e.exercise.name;
    final first = e.planned.first;
    if (e.exercise.type == ExerciseType.cardio) {
      // 有氧的第三層只有目標時長；秒數借用 targetReps 欄位承載。
      return '${e.exercise.name} $n×${first.targetReps} 秒';
    }
    final w = first.targetWeight;
    final wt = w == 0
        ? '徒手'
        : (w == w.roundToDouble() ? w.round().toString() : w.toStringAsFixed(1));
    return '${e.exercise.name} $n×${first.targetReps}'
        '${w == 0 ? '（$wt）' : ' @$wt kg'}';
  }

  /// 我最近一次用這份課表訓練的日期與完成度；未用過為空值。
  DateTime? lastTrainedAt;
  double? lastCompletion;

  /// 轉為可執行的課表。**自訂訓練與訓練計畫的課表內容結構完全一致**，
  /// 故這裡只是換一層外殼，不做任何內容轉換。
  ///
  /// 課表來源係數看的是「已公開」與否，不是「誰做的」——
  /// 已公開者經過管理員審核，未公開者沒有。
  WorkoutPlan toWorkoutPlan() => WorkoutPlan(
        id: id,
        name: name,
        source: state == CustomPlanState.public
            ? PlanSource.publishedCustom
            : PlanSource.privateCustom,
        exercises: exercises,
        // 課表選擇頁的「上次訓練日期／上次完成度」兩欄同樣適用於自訂訓練。
        lastTrainedAt: lastTrainedAt,
        lastCompletion: lastCompletion,
      );

  /// 審核已逾期 —— 一次性狀態判定，不改變案件狀態，只在佇列標示。
  bool get reviewOverdue {
    final at = appliedAt;
    if (state != CustomPlanState.pendingPublic || at == null) return false;
    return appNow().difference(at).inDays >= kPublicPlanReviewDays;
  }

  /// 剩餘審核天數；已逾期為 0。
  int get reviewDaysLeft {
    final at = appliedAt;
    if (state != CustomPlanState.pendingPublic || at == null) return 0;
    final left =
        kPublicPlanReviewDays - appNow().difference(at).inDays;
    return left < 0 ? 0 : left;
  }

  /// 對關注者可見開關僅於已發布 / 已申請公開時可操作；
  /// 已公開時不生效（全平台已涵蓋關注者）。
  bool get canToggleVisibility =>
      state == CustomPlanState.published ||
      state == CustomPlanState.pendingPublic;

  /// 逐狀態的可用動作。
  List<String> get actions => switch (state) {
        CustomPlanState.saved => ['發布', '修改', '刪除'],
        CustomPlanState.published => ['取消發布', '申請公開', '修改', '刪除'],
        CustomPlanState.pendingPublic => ['修改', '刪除'],
        CustomPlanState.public => ['下架', '修改（重新審核）', '刪除'],
        CustomPlanState.rejected => ['退回已發布'],
      };
}
