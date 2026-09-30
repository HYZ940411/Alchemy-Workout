// 教官題庫的品質條件（2026-09-29 專業覆核意見）。
//
// 這份題庫決定誰有資格帶別人訓練。覆核指出的五項缺陷，共同點是
// **測驗量不到它想量的東西** —— 而那種壞法不會有任何報錯：
// 題目看起來都很專業，考出來的分數看起來也很正常。
//
// 所以這裡把「它必須成立的條件」逐條釘住。這些條件中有幾條
// （正解分布、題庫大於考卷）是**改一次題庫就可能不小心破壞**的，
// 而破壞之後沒有人會發現。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/mock/mock_extra.dart';

void main() {
  final bank = buildExamBank();
  final mc =
      bank.where((q) => q.type == ExamQuestionType.multipleChoice).toList();
  final sa =
      bank.where((q) => q.type == ExamQuestionType.shortAnswer).toList();

  group('題數與抽題', () {
    test('選擇題至少 45 題、簡答題至少 8 題', () {
      expect(mc.length, greaterThanOrEqualTo(45));
      expect(sa.length, greaterThanOrEqualTo(8));
    });

    test('題庫必須大於考卷 —— 否則「隨機抽取」抽的是全部', () {
      final mcCount = platformConfig.i('exam', 'mcCount');
      final saCount = platformConfig.i('exam', 'saCount');
      expect(mc.length, greaterThan(mcCount),
          reason: '題庫等於考卷時每個人拿到同一份，重考等於重看同一份考卷');
      expect(sa.length, greaterThan(saCount));
      // 而且要說得出來，不是安靜地退化 —— 題庫剛好等於考卷的時候，
      // 抽題不會拋任何錯誤，只會安靜地讓隨機性變成零。
      expect(
          examBankShortage(
              [...mc.take(mcCount), ...sa.take(saCount)], mcCount, saCount),
          contains('剛好'));
    });

    test('題號不重複', () {
      final ids = bank.map((q) => q.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('正解分布 —— 前一版 20 題的正解全部是 B', () {
    test('任一選項的正解數不超過總題數的 30%', () {
      final count = <int, int>{};
      for (final q in mc) {
        count[q.answerIndex] = (count[q.answerIndex] ?? 0) + 1;
      }
      for (final e in count.entries) {
        expect(e.value / mc.length, lessThanOrEqualTo(0.30),
            reason: '第 ${e.key + 1} 個選項是正解的題目佔 '
                '${(e.value / mc.length * 100).toStringAsFixed(1)}%');
      }
    });

    test('四個選項都當過正解', () {
      expect(mc.map((q) => q.answerIndex).toSet(), {0, 1, 2, 3});
    });
  });

  group('選項要有迷惑性', () {
    test('每題都是四個選項，且彼此不重複', () {
      for (final q in mc) {
        expect(q.options, hasLength(4), reason: q.id);
        expect(q.options.toSet().length, 4, reason: '${q.id} 有重複選項');
      }
    });

    test('只憑長度作答，得分要接近隨機', () {
      // 前一版的錯誤選項短而誇張（「加咖啡因硬上」），正解則是唯一
      // 寫得完整的那一句 —— 於是「選最長的」就能全對。
      //
      // **兩個方向都要擋。** 第一次修完之後正解變成「從來不是最長的」，
      // 那只是把捷徑反過來：選最長的全錯，等於選另外三個就有三分之一。
      // 四選一的隨機基準是 25%，所以兩個比例都要落在它附近。
      int rate(bool Function(int len, Iterable<int> all) hit) => mc
          .where((q) =>
              hit(q.options[q.answerIndex].length, q.options.map((o) => o.length)))
          .length;

      final longest = rate((len, all) => len == all.reduce((a, b) => a > b ? a : b));
      final shortest = rate((len, all) => len == all.reduce((a, b) => a < b ? a : b));

      expect(longest / mc.length, inInclusiveRange(0.10, 0.40),
          reason: '正解是最長選項的比例 ${(longest / mc.length * 100).round()}%');
      expect(shortest / mc.length, lessThan(0.40),
          reason: '正解是最短選項的比例 ${(shortest / mc.length * 100).round()}%');
    });

    test('正解與誤答的平均長度相近', () {
      double avg(Iterable<int> xs) =>
          xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
      final right = avg(mc.map((q) => q.options[q.answerIndex].length));
      final wrong = avg([
        for (final q in mc)
          for (final (i, o) in q.options.indexed)
            if (i != q.answerIndex) o.length,
      ]);
      // 前一版是 28.3 比 15.7 —— 正解平均長了將近一倍。
      expect((right - wrong).abs() / wrong, lessThan(0.25),
          reason: '正解平均 ${right.toStringAsFixed(1)} 字、'
              '誤答平均 ${wrong.toStringAsFixed(1)} 字');
    });

    test('沒有明顯荒謬或惡意的選項', () {
      // 覆核點名的那幾句。它們的問題不是措辭，是**沒有人會選**，
      // 所以那一題實際上只有三個選項。
      const absurd = ['加咖啡因硬上', '斷食一週', '取消他的會員資格', '想練才練'];
      for (final q in mc) {
        for (final o in q.options) {
          for (final bad in absurd) {
            expect(o.contains(bad), isFalse, reason: '${q.id} 仍有「$bad」');
          }
        }
      }
    });
  });

  group('必答題', () {
    final must = mc.where((q) => q.mustPass).toList();

    test('8 到 12 題，且都是選擇題', () {
      expect(must.length, inInclusiveRange(8, 12));
      expect(sa.every((q) => !q.mustPass), isTrue,
          reason: '簡答題本來就全數要通過，標必答題沒有意義');
    });

    test('必答題不多於一份考卷，否則抽不出來', () {
      expect(must.length, lessThanOrEqualTo(platformConfig.i('exam', 'mcCount')));
    });

    test('每一份考卷都含全部必答題', () {
      // 「答錯任一題即不及格」的前提是那一題有被問到。
      for (var seed = 0; seed < 30; seed++) {
        final paper = drawExamPaper(mc, platformConfig.i('exam', 'mcCount'),
            rng: Random(seed));
        final got = paper.where((q) => q.mustPass).map((q) => q.id).toSet();
        expect(got, must.map((q) => q.id).toSet(),
            reason: 'seed=$seed 的考卷漏了必答題');
      }
    });

    test('必答題不固定排在前面 —— 那等於標出哪幾題是關鍵題', () {
      final positions = <int>{};
      for (var seed = 0; seed < 30; seed++) {
        final paper = drawExamPaper(mc, platformConfig.i('exam', 'mcCount'),
            rng: Random(seed));
        positions.add(paper.indexWhere((q) => q.mustPass));
      }
      expect(positions.length, greaterThan(1));
    });
  });

  group('說得出每一題為什麼在這裡', () {
    test('選擇題都有命題理由', () {
      for (final q in mc) {
        expect(q.rationale.trim(), isNotEmpty, reason: q.id);
      }
    });

    test('簡答題都有通過要素、不通過條件與追問範例', () {
      for (final q in sa) {
        expect(q.rubricPass.trim(), isNotEmpty, reason: '${q.id} 沒有通過要素');
        expect(q.rubricFail.trim(), isNotEmpty, reason: '${q.id} 沒有不通過條件');
        expect(q.followUp.trim(), isNotEmpty, reason: '${q.id} 沒有追問範例');
      }
    });

    test('至少兩題簡答題綁定應試者自己的訓練紀錄', () {
      final bound = sa
          .where((q) => q.text.contains('你自己') && q.text.contains('紀錄'))
          .length;
      expect(bound, greaterThanOrEqualTo(2),
          reason: '綁自身紀錄是目前唯一能提高代答難度的設計');
    });
  });

  group('必補主題都在', () {
    // 覆核指定的六個高風險主題，每項至少 2 題。
    const topics = {
      '未成年': ['未成年', '十五歲', '監護人'],
      '飲食失調': ['減脂', '一餐', '補回來', '量體重'],
      '身體評論': ['體態', '算胖', '對比照'],
      '心理警訊': ['提不起勁', '傷害自己', '焦慮'],
      '利益衝突': ['代理', '私人課程', '贊助'],
      '急症': ['胸口悶痛', '無力', '失去意識', '冒冷汗'],
    };
    topics.forEach((name, keys) {
      test('$name 至少 2 題', () {
        final hit = bank
            .where((q) => keys.any((k) => q.text.contains(k)))
            .length;
        expect(hit, greaterThanOrEqualTo(2), reason: '$name 只有 $hit 題');
      });
    });
  });

  group('不考有學派爭議的處方數值', () {
    test('被點名的三題已移除', () {
      // mc03 訓練頻率、mc10 力竭與 RIR、mc12 休息時間 ——
      // 出題原則宣稱「處方細節不出題」，而這三題正在考處方細節。
      for (final id in ['mc03', 'mc10', 'mc12']) {
        expect(mc.any((q) => q.id == id), isFalse, reason: '$id 還在');
      }
    });

    test('沒有把把握不足的題目含糊帶過', () {
      // 對正解沒有十足把握的，理由欄要明說，不是寫得像很確定。
      final flagged =
          mc.where((q) => q.rationale.contains('建議由專業人士確認')).toList();
      expect(flagged, isNotEmpty,
          reason: '一份 45 題的題庫裡一題都不需要專業確認，那更可疑');
    });
  });

  group('及格判定', () {
    test('必答題答錯即不及格，即使百分比達標', () {
      final paper = drawExamPaper(mc, 20, rng: Random(1));
      final allRight = {for (final q in paper) q.id: q.answerIndex};

      // 全對 → 過。
      expect(missedMustPass(paper, allRight), 0);
      expect(gradeExamPaper(paper, allRight), 20);

      // 只錯一題必答題 → 分數仍有 95%，但不及格。
      final oneMustWrong = {...allRight};
      final must = paper.firstWhere((q) => q.mustPass);
      oneMustWrong[must.id] = (must.answerIndex + 1) % 4;
      expect(gradeExamPaper(paper, oneMustWrong), 19,
          reason: '95% —— 百分比門檻擋不住它');
      expect(missedMustPass(paper, oneMustWrong), 1);
    });
  });
}
