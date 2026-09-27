import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/domain/training_quality.dart';
import 'package:fitness_app/state/app_state.dart';

/// 使用者截圖回報：四項初審條件**全部打勾**（品質 77/60、合理性 90/40），
/// 階段卻停在「初審中」。
///
/// 那不是矛盾 —— AI 評分失敗時留在初審中是規格要求的
/// （「申請者本身無過失，因平台的 AI 故障而使其被駁回⋯⋯是把平台的技術
/// 風險轉嫁給使用者」）。問題是畫面上那兩個分數是**端內規則算的備援值**，
/// 不是初審會採用的那一份，而打勾讓它看起來像已經通過了。
void main() {
  QualityScore score(String source) => QualityScore(
      completion: 80, consistency: 80, sanity: 90, source: source);

  test('AI 失敗、退回規則 → 這份分數是暫估的', () {
    final s = AppState()
      ..quality = score('rules')
      ..qualityScoreError = '503 忙線';
    expect(s.qualityIsProvisional, isTrue);
  });

  test('AI 成功 → 不是暫估的', () {
    final s = AppState()
      ..quality = score('gemini')
      ..qualityScoreError = null;
    expect(s.qualityIsProvisional, isFalse);
  });

  test('根本沒接雲端評分（沒有錯誤）→ 不算暫估', () {
    // 測試與示範環境走這條：沒有 AI 可等，規則就是最終答案。
    final s = AppState()
      ..quality = score('rules')
      ..qualityScoreError = null;
    expect(s.qualityIsProvisional, isFalse);
  });

  test('還沒評分 → 不算暫估', () {
    final s = AppState()
      ..quality = null
      ..qualityScoreError = '503 忙線';
    expect(s.qualityIsProvisional, isFalse);
  });

  test('暫估的分數不讓初審通過 —— 那一步要等 AI', () {
    final s = AppState()
      ..quality = score('rules')
      ..qualityScoreError = '503 忙線';
    // 分數本身是過的，但它不是初審採用的那一份。
    expect(s.instructorGate.qualityOk, isTrue);
    expect(s.qualityIsProvisional, isTrue,
        reason: '畫面靠它決定不要打勾');
  });
}
