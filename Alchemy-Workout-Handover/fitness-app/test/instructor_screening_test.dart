import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/data/quality_score_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/training_quality.dart';
import 'package:fitness_app/state/app_state.dart';

/// 使用者回報「教官申請是寫 Demo」。
///
/// 那顆「推進到下一階段（Demo）」是申請人**唯一的出路** ——
/// 因為「初審中 → 初審通過／駁回」這個自動判定根本沒有實作。
/// 而那顆按鈕會跳過品質評分與測驗，還**以滿分送出考卷**。
///
/// 規格：「[串聯] 系統執行『初審教官資格』導致『教官資格已初審通過』
/// —— Actor：系統（自動依門檻判定，無人工介入）」、
/// 「[分支] 初審 / 測驗 / 管理員審核任一階段未通過 → 教官資格已駁回」。
void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  AppState applying() {
    final s = AppState()..instructorStage = InstructorStage.screening;
    return s;
  }

  group('評分回來了，初審就該有結果', () {
    test('通過門檻 → 待作答測驗', () async {
      final s = applying()..qualitySource = _Scores(const QualityScore(
          completion: 90, consistency: 90, sanity: 90, source: '測試'));
      await s.rescoreTrainingQualityAsync();
      expect(s.instructorGate.passed, isTrue);
      expect(s.instructorStage, InstructorStage.screenPassed);
    });

    test('品質不過 → 駁回', () async {
      final s = applying()..qualitySource = _Scores(const QualityScore(
          completion: 10, consistency: 10, sanity: 90, source: '測試'));
      await s.rescoreTrainingQualityAsync();
      expect(s.instructorGate.passed, isFalse);
      expect(s.instructorStage, InstructorStage.rejected);
    });

    test('紀錄合理性一票否決 → 駁回', () async {
      final s = applying()..qualitySource = _Scores(const QualityScore(
          completion: 100, consistency: 100, sanity: 5, source: '測試'));
      expect(s.instructorGate.vetoed, isTrue);
      await s.rescoreTrainingQualityAsync();
      expect(s.instructorStage, InstructorStage.rejected);
    });
  });

  group('AI 失敗不改變申請狀態', () {
    // 規格：「該教官申請維持在初審中，不通過亦不駁回」、
    // 「由排程於隔日重跑」、「不直接駁回：申請者本身無過失，
    // 因平台的 AI 故障而使其被駁回，是把平台的技術風險轉嫁給使用者」。
    test('評分失敗時留在初審中，不駁回也不通過', () async {
      final s = applying()..qualitySource = _Fails();
      await s.rescoreTrainingQualityAsync();
      expect(s.instructorStage, InstructorStage.screening);
      expect(s.qualityScoreError, isNotNull, reason: '失敗要留下痕跡');
    });

    test('即使端內規則算出來的分數很低，也不因此駁回', () async {
      final s = applying()..qualitySource = _Fails();
      await s.rescoreTrainingQualityAsync();
      expect(s.instructorStage, InstructorStage.screening);
    });
  });

  group('只在初審中動作', () {
    test('待人工審核時重新評分，不會被踢回去', () async {
      final s = AppState()
        ..instructorStage = InstructorStage.pendingReview
        ..qualitySource = _Scores(const QualityScore(
            completion: 5, consistency: 5, sanity: 5, source: '測試'));
      await s.rescoreTrainingQualityAsync();
      expect(s.instructorStage, InstructorStage.pendingReview);
    });

    test('已是教官時重新評分，資格不受影響', () async {
      final s = AppState()
        ..instructorStage = InstructorStage.approved
        ..qualitySource = _Scores(const QualityScore(
            completion: 5, consistency: 5, sanity: 5, source: '測試'));
      await s.rescoreTrainingQualityAsync();
      expect(s.instructorStage, InstructorStage.approved);
    });
  });
}

class _Scores implements QualityScoreSource {
  final QualityScore q;
  _Scores(this.q);
  @override
  Future<QualityScore> score(List<SessionSummary> sessions) async => q;
}

class _Fails implements QualityScoreSource {
  @override
  Future<QualityScore> score(List<SessionSummary> sessions) async =>
      throw Exception('503 忙線');
}
