// AI 訓練品質評分改成真的算（`[BE-13]` 周邊，2026-09-25）。
//
// ## 在此之前：兩個寫死的數字
//
//     int qualityScore = 72;
//     int sanityScore = 68;
//
// 每一位申請人拿到的都是同一組數字，而那兩個數字決定他能不能申請教官
// （`evaluateInstructorGate` 拿它們去比對通過門檻 60、折抵門檻 80、
// 一票否決門檻 40）。也就是**初審的品質那一關從來沒有真的判過任何人**。
//
// ## 為什麼先做規則計算，而使用者選的是 Gemini
//
// 兩者不衝突。規格明訂 AI 服務中斷時「不直接駁回」——申請者本身無過失
// ——所以無論由誰評分，規則計算都必須存在頂著。這與
// `workers/src/adjust.ts` 的 `ruleFallback()` 是同一個道理。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/training_quality.dart';
import 'package:fitness_app/state/app_state.dart';

/// 一場「正常」的訓練：12 組、60 分鐘、重量遞增。
SessionSummary _session(DateTime d,
        {int sets = 12, int minutes = 60, double weight = 60}) =>
    SessionSummary(
      date: d,
      totalSets: sets,
      minutes: minutes,
      sets: [for (var i = 0; i < sets; i++) (weight + i, 8)],
    );

/// 從 [from] 起、每 [everyDays] 天一場，共 [n] 場。
///
/// **每場的重量刻意略有不同。** 第一版每場數字一模一樣，結果被
/// 「多場訓練的重量與次數完全相同」那條規則標記為疑似照抄預帶值 ——
/// 那是規則做對了，是這個假資料不像真人在練。真的訓練紀錄不會
/// 二十場一個數字都不動。
List<SessionSummary> _regular(int n,
    {int everyDays = 2, DateTime? from, double weight = 60}) {
  final start = from ?? DateTime(2026, 7, 1);
  return [
    for (var i = 0; i < n; i++)
      _session(start.add(Duration(days: i * everyDays)),
          // 每場微幅遞增，像漸進超負荷。
          weight: weight + (i % 5) * 2.5),
  ];
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('沒有紀錄', () {
    test('三維全 0，而且說得出為什麼 —— 不是「品質差」，是無從評分', () {
      final q = scoreTrainingQuality(const []);
      expect(q.completion, 0);
      expect(q.consistency, 0);
      expect(q.sanity, 0);
      expect(q.concerns.single, contains('沒有任何訓練紀錄'));
    });

    test('全 0 會被品質分門檻擋下 —— 這才是「無從評分」該有的結果', () {
      final q = scoreTrainingQuality(const []);
      expect(q.weighted, lessThan(platformConfig.i('instructorGate', 'qualityPass')));
    });
  });

  group('規律訓練的人拿得到好分數', () {
    test('每兩天一練、12 組、時間合理 → 三維都不低', () {
      final q = scoreTrainingQuality(_regular(20));
      expect(q.completion, greaterThanOrEqualTo(80));
      expect(q.consistency, greaterThanOrEqualTo(60));
      expect(q.sanity, 100, reason: '沒有任何造假訊號');
      expect(q.weighted,
          greaterThanOrEqualTo(platformConfig.i('instructorGate', 'qualityPass')));
    });

    test('疑慮標記是空的', () {
      expect(scoreTrainingQuality(_regular(20)).concerns, isEmpty);
    });
  });

  group('維度一：完成率抓偷懶', () {
    test('每場只做 2 組 → 完成率低', () {
      final q = scoreTrainingQuality(
          [for (final s in _regular(10)) _session(s.date, sets: 2)]);
      expect(q.completion, lessThan(40));
      expect(q.concerns.join(), contains('不足 6 組'));
    });

    test('組數夠多就不扣', () {
      final q = scoreTrainingQuality(
          [for (final s in _regular(10)) _session(s.date, sets: 15)]);
      expect(q.completion, 100);
    });
  });

  group('維度二：規律性抓集中衝量後消失', () {
    test('三個月只練一週 → 規律性低', () {
      // 七天內連練七場，然後消失三個月。
      final burst = [
        for (var i = 0; i < 7; i++) _session(DateTime(2026, 7, 1 + i)),
        _session(DateTime(2026, 9, 30)),
      ];
      final q = scoreTrainingQuality(burst);
      expect(q.consistency, lessThan(60));
      expect(q.concerns.join(), contains('訓練間隔很不平均'));
    });

    test('只有一場 → 規律性無從判斷，給 0 並說明', () {
      final q = scoreTrainingQuality([_session(DateTime(2026, 9, 1))]);
      expect(q.consistency, 0);
      expect(q.concerns.join(), contains('場次過少'));
    });

    test('穩定每兩天一練 → 規律性高', () {
      expect(scoreTrainingQuality(_regular(30)).consistency,
          greaterThanOrEqualTo(70));
    });
  });

  group('維度三：合理性抓造假', () {
    test('每組平均不到 30 秒 → 扣分並標記', () {
      final q = scoreTrainingQuality(
          [for (final s in _regular(10)) _session(s.date, minutes: 3)]);
      expect(q.sanity, lessThan(100));
      expect(q.concerns.join(), contains('每組平均耗時低於 30 秒'));
    });

    test('重量超出人體合理範圍 → 扣分', () {
      final s = _regular(5);
      final q = scoreTrainingQuality([
        ...s,
        SessionSummary(
          date: DateTime(2026, 8, 1),
          totalSets: 3,
          minutes: 60,
          sets: const [(900.0, 8), (60.0, 8), (60.0, 8)],
        ),
      ]);
      expect(q.concerns.join(), contains('超出人體合理範圍'));
    });

    test('多場數字完全雷同 → 疑似照抄預帶值', () {
      // 每一場的重量與次數一模一樣。
      final same = [
        for (var i = 0; i < 9; i++)
          SessionSummary(
            date: DateTime(2026, 7, 1).add(Duration(days: i * 2)),
            totalSets: 3,
            minutes: 60,
            sets: const [(60.0, 10), (60.0, 10), (60.0, 10)],
          ),
      ];
      final q = scoreTrainingQuality(same);
      expect(q.concerns.join(), contains('疑似照抄預帶值'));
      expect(q.sanity, lessThan(100));
    });

    test('重量突然暴增 → 標記', () {
      final q = scoreTrainingQuality([
        ..._regular(5, weight: 60),
        _session(DateTime(2026, 7, 20), weight: 300),
      ]);
      expect(q.concerns.join(), contains('成長超過一倍'));
    });

    test('合理性低到一票否決門檻以下時，加權平均再高也過不了', () {
      const q = QualityScore(completion: 100, consistency: 100, sanity: 20);
      // 25／25／50 之下，兩維滿分而合理性 20 分，加權平均剛好是 60 ——
      // **正好踩在通過門檻上**。這就是一票否決存在的理由：
      // 光看加權平均，這個人過得了。
      expect(q.weighted, 60);

      final gate = evaluateInstructorGate(
          rank: 99, workouts: 999, quality: q.weighted, sanity: q.sanity);
      expect(gate.qualityOk, isTrue, reason: '加權平均那一關他過了');
      expect(gate.vetoed, isTrue, reason: '但合理性 20 < 40，一票否決');
      expect(gate.passed, isFalse);
    });
  });

  group('加權平均', () {
    test('依平台設定的權重 25／25／50', () {
      const q = QualityScore(completion: 100, consistency: 0, sanity: 0);
      expect(q.weighted, 25);

      const q2 = QualityScore(completion: 0, consistency: 0, sanity: 100);
      expect(q2.weighted, 50, reason: '合理性權重最重 —— 它抓的是造假');
    });

    test('權重可由管理員調整', () {
      platformConfig.group('instructorGate').param('wSanity').value = 0;
      const q = QualityScore(completion: 0, consistency: 0, sanity: 100);
      expect(q.weighted, 0);
    });

    test('權重全 0 不當機 —— 回 0 讓門檻擋下，不是除以零', () {
      for (final k in ['wCompletion', 'wConsistency', 'wSanity']) {
        platformConfig.group('instructorGate').param(k).value = 0;
      }
      const q = QualityScore(completion: 100, consistency: 100, sanity: 100);
      expect(q.weighted, 0);
    });

    test('後台不准把權重全設成 0 —— 那等於把整條路關掉', () {
      final g = platformConfig.group('instructorGate');
      final before = {for (final p in g.params) p.key: p.value};
      before['wCompletion'] = 0;
      before['wConsistency'] = 0;
      before['wSanity'] = 0;
      expect(g.invariant?.call(before), contains('不得全為 0'));
    });
  });

  group('三維分數都要在 0–100', () {
    test('合法', () {
      expect(const QualityScore(completion: 0, consistency: 50, sanity: 100).valid,
          isTrue);
    });

    test('超出範圍不合法 —— 模型回來的東西要過這一關', () {
      expect(const QualityScore(completion: 101, consistency: 0, sanity: 0).valid,
          isFalse);
      expect(const QualityScore(completion: -1, consistency: 0, sanity: 0).valid,
          isFalse);
    });
  });

  group('接上狀態層', () {
    test('沒評過時分數是 0，不是寫死的 72', () {
      final s = AppState(demo: false);
      expect(s.quality, isNull);
      expect(s.qualityScore, 0);
      expect(s.sanityScore, 0);
    });

    test('評分依這個人自己的訓練紀錄 —— 不同的人不同分數', () {
      final busy = AppState()..rescoreTrainingQuality();
      final idle = AppState(demo: false)..rescoreTrainingQuality();

      expect(busy.qualityScore, greaterThan(idle.qualityScore),
          reason: '示範身分有 12 天連續訓練，空帳號一場都沒有');
    });

    test('重新申請會重新評分 —— 不沿用舊的', () {
      final s = AppState()
        ..instructorStage = InstructorStage.rejected
        ..lastExamAt = null;
      s.quality = const QualityScore(completion: 1, consistency: 1, sanity: 1);

      expect(s.reapplyInstructor(), isTrue);

      // 14 天只是最低重試間隔，數月後再申請時訓練紀錄已完全不同。
      expect(s.quality!.completion, isNot(1));
    });
  });
}
