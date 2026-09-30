import '../domain/training_quality.dart';

/// AI 訓練品質評分的來源（`[BE-13]` 周邊，2026-09-25）。
///
/// **空值＝走規則計算**，與 `AiSuggestionSource` 同一個形狀。
///
/// ## 退路在前端，不在 Worker
///
/// `workers/src/adjust.ts` 的退路是**在 Worker 裡再寫一份規則**
/// （`ruleFallback()`），而 Dart 那邊已經有一份 —— `PROGRESS.md` 記著
/// 那是違反「同一個決定只寫一個地方」的已知問題，兩份要一起改。
///
/// **這次不重蹈覆轍。** Worker 失敗或回傳不合格就直接丟錯，
/// 由 `AppState` 退回已經寫好的 `scoreTrainingQuality()` ——
/// 規則只有一份，在 Dart 裡，而且已經有測試釘著。
abstract class QualityScoreSource {
  /// 依訓練紀錄摘要評分。
  ///
  /// 失敗（沒登入、逾時、回傳不合格）一律往上拋 —— 呼叫端據此退回規則。
  /// **不在這裡吞掉**：吞掉的話「模型算的」與「規則算的」分不出來，
  /// 而管理員需要知道這筆評分是誰算的。
  Future<QualityScore> score(List<SessionSummary> sessions);
}
