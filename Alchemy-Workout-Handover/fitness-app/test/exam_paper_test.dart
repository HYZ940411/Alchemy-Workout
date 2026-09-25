// 教官測驗要真的出題與判卷（2026-09-25）。
//
// ## 在此之前：作答是一個拉桿
//
// `_takeExam()` 給申請人一個 `Slider`，讓他**自己拉「答對幾題」**，
// 那個數字直接被當成成績交給 `submitExam()`。也就是：
//
//   · 沒有出題 —— 題庫（`examBank`）與後台的題庫管理頁都已存在，
//     但作答畫面從來沒去讀它
//   · 沒有判卷 —— 分數是申請人自己給的
//   · **任何人都能給自己滿分**，然後進入「待管理員審核」
//
// 而管理員那一側看到的 AI 評分與簡答作答同樣是寫死的假資料
// （見 PROGRESS.md 第 5 節 0j）—— 所以整條教官資格的把關是空的。
// 這次先補「選擇題真的出題與判卷」這一段。
//
// ## 為什麼題庫不足時不「抽幾題算幾題」
//
// 及格標準是**百分比**（`exam.mcPass`，目前 80）。20 題要對 16 題；
// 若題庫只有 4 題就抽 4 題，對 4 題也是 100%，但那張考卷根本不是
// 同一場考試 —— 那等於**靜靜地降低門檻**。所以題庫不足就抽不出考卷。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/domain/task_pool.dart';
import 'package:fitness_app/state/app_state.dart';

/// [n] 題選擇題，第 i 題的正解是 `i % 4`。
///
/// **ID 用 `t` 開頭，不用 `mc`** —— 真的題庫用的就是 `mc01`…`mc20`，
/// 撞到的話 `answers` 那個 Map 會被蓋掉，判卷結果就對不上。
/// （第一版用 `mc$i`，`mc10`–`mc20` 正好全撞。）
List<ExamQuestion> _bank(int n, {int sa = 0}) => [
      for (var i = 0; i < n; i++)
        ExamQuestion(
          id: 't$i',
          type: ExamQuestionType.multipleChoice,
          text: '第 $i 題',
          options: const ['A', 'B', 'C', 'D'],
          answerIndex: i % 4,
        ),
      for (var i = 0; i < sa; i++)
        ExamQuestion(
          id: 'ts$i',
          type: ExamQuestionType.shortAnswer,
          text: '簡答 $i',
        ),
    ];

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('抽考卷', () {
    test('抽得出指定題數，而且都來自題庫', () {
      final bank = _bank(30);
      final paper = drawExamPaper(bank, 20, rng: Random(1));

      expect(paper, hasLength(20));
      final ids = bank.map((q) => q.id).toSet();
      expect(paper.every((q) => ids.contains(q.id)), isTrue);
    });

    test('同一份考卷裡不重複出題', () {
      final paper = drawExamPaper(_bank(30), 20, rng: Random(2));
      expect(paper.map((q) => q.id).toSet(), hasLength(20));
    });

    test('每次抽出來不一樣 —— 固定題目等於背誦，重考也失去意義', () {
      final bank = _bank(30);
      final a = drawExamPaper(bank, 20, rng: Random(1)).map((q) => q.id);
      final b = drawExamPaper(bank, 20, rng: Random(99)).map((q) => q.id);
      expect(a, isNot(orderedEquals(b)));
    });

    test('只抽選擇題 —— 簡答題走人工審核那條路', () {
      final paper = drawExamPaper(_bank(20, sa: 5), 20, rng: Random(1));
      expect(
          paper.every((q) => q.type == ExamQuestionType.multipleChoice), isTrue);
    });

    test('題庫不足就抽不出考卷，不是抽幾題算幾題', () {
      // 抽 4 題也叫「及格 80%」的話，門檻就被靜靜地降低了。
      expect(drawExamPaper(_bank(4), 20), isEmpty);
    });

    test('剛好足夠時抽得出來', () {
      expect(drawExamPaper(_bank(20), 20, rng: Random(1)), hasLength(20));
    });
  });

  group('判卷', () {
    test('全對', () {
      final paper = _bank(5);
      final answers = {for (final q in paper) q.id: q.answerIndex};
      expect(gradeExamPaper(paper, answers), 5);
    });

    test('答錯的不算', () {
      final paper = _bank(5);
      final answers = {
        for (final q in paper) q.id: (q.answerIndex + 1) % 4,
      };
      expect(gradeExamPaper(paper, answers), 0);
    });

    test('沒作答的題目算錯，不是略過', () {
      // 略過的話交白卷是 0/0，而 0/0 在百分比上很容易變成 100%。
      final paper = _bank(5);
      expect(gradeExamPaper(paper, const {}), 0);
    });

    test('只算考卷上有的題目 —— 塞別題的答案不加分', () {
      final paper = _bank(3);
      final answers = {
        for (final q in _bank(10)) q.id: q.answerIndex,
      };
      expect(gradeExamPaper(paper, answers), 3, reason: '考卷只有 3 題');
    });
  });

  group('接上狀態層', () {
    test('題庫足夠時抽得出考卷', () {
      final s = AppState(demo: false)
        ..examBank.addAll(_bank(25))
        ..instructorStage = InstructorStage.screenPassed;

      expect(s.drawExam(), hasLength(platformConfig.i('exam', 'mcCount')));
    });

    test('示範題庫抽得出考卷 —— 2026-09-25 補足到規格的 20＋3', () {
      final s = AppState();
      expect(s.drawExam(), hasLength(platformConfig.i('exam', 'mcCount')));
      expect(s.examBankWarning, isNull);
    });

    test('題庫被改少了就抽不出來，畫面據此擋住作答', () {
      // 後台的題庫管理頁刪得動題目 —— 刪到不夠時不可以靜靜地出一張短考卷。
      final s = AppState()..examBank.removeWhere((q) => q.id != 'mc01');
      expect(s.drawExam(), isEmpty);
      expect(s.examBankWarning, contains('選擇題題庫只有 1 題'));
    });

    test('判卷結果餵得進 submitExam，答對八成才過', () {
      final s = AppState(demo: false)
        ..examBank.addAll(_bank(25))
        ..instructorStage = InstructorStage.screenPassed;
      final paper = s.drawExam();

      // 20 題答對 16 題 ＝ 80%，剛好及格。
      final answers = <String, int>{};
      for (var i = 0; i < paper.length; i++) {
        answers[paper[i].id] =
            i < 16 ? paper[i].answerIndex : (paper[i].answerIndex + 1) % 4;
      }

      expect(s.gradeExam(paper, answers), 16);
      expect(s.submitExam(16), isTrue);
      expect(s.examMcPassed, isTrue);
      expect(s.instructorStage, InstructorStage.pendingReview);
    });

    test('答對 15 題就不過，而且不進人工審核', () {
      final s = AppState(demo: false)
        ..examBank.addAll(_bank(25))
        ..instructorStage = InstructorStage.screenPassed;
      final paper = s.drawExam();

      final answers = <String, int>{};
      for (var i = 0; i < paper.length; i++) {
        answers[paper[i].id] =
            i < 15 ? paper[i].answerIndex : (paper[i].answerIndex + 1) % 4;
      }

      s.submitExam(s.gradeExam(paper, answers));

      expect(s.examMcPassed, isFalse);
      expect(s.instructorStage, InstructorStage.rejected,
          reason: '選擇題這一關就沒過，不必送人工審核');
    });
  });

  _bankMeetsSpec();
  _shortAnswersAreReal();
}

/// 題庫本身要符合規格（2026-09-25）。
///
/// 規格：選擇題 20 題、簡答題 3 題，皆自題庫隨機抽取
/// （`教官申請流程.md`）。在此之前題庫只有 3＋2 —— 而作答畫面是一個
/// 拉桿、根本沒去抽題，所以**從來沒有人發現不夠**。
void _bankMeetsSpec() {
  group('示範題庫符合規格', () {
    final bank = AppState().examBank;

    test('選擇題數量足夠抽一份考卷', () {
      final mc =
          bank.where((q) => q.type == ExamQuestionType.multipleChoice).length;
      expect(mc, greaterThanOrEqualTo(platformConfig.i('exam', 'mcCount')));
    });

    test('簡答題數量足夠', () {
      final sa =
          bank.where((q) => q.type == ExamQuestionType.shortAnswer).length;
      expect(sa, greaterThanOrEqualTo(platformConfig.i('exam', 'saCount')));
    });

    test('每題 ID 唯一 —— 撞 ID 會讓判卷對到別題', () {
      expect(bank.map((q) => q.id).toSet(), hasLength(bank.length));
    });

    test('選擇題都有四個選項，正解索引在範圍內', () {
      for (final q
          in bank.where((q) => q.type == ExamQuestionType.multipleChoice)) {
        expect(q.options, hasLength(4), reason: q.id);
        expect(q.answerIndex, inInclusiveRange(0, 3), reason: q.id);
      }
    });

    test('選項內容不重複 —— 同一題出現兩個一樣的選項是出題錯誤', () {
      for (final q
          in bank.where((q) => q.type == ExamQuestionType.multipleChoice)) {
        expect(q.options.toSet(), hasLength(q.options.length), reason: q.id);
      }
    });

    test('簡答題沒有選項', () {
      for (final q
          in bank.where((q) => q.type == ExamQuestionType.shortAnswer)) {
        expect(q.options, isEmpty, reason: q.id);
      }
    });

    test('題目與選項都不是空的', () {
      for (final q in bank) {
        expect(q.text.trim(), isNotEmpty, reason: q.id);
        for (final o in q.options) {
          expect(o.trim(), isNotEmpty, reason: q.id);
        }
      }
    });
  });
}

/// 簡答題要是申請人真的寫的（2026-09-25）。
///
/// 在此之前 `submitExam()` 裡**寫死兩題兩答**，而畫面上沒有任何地方
/// 能寫簡答。也就是管理員在待審佇列看到的是**申請人從來沒寫過的答案**，
/// 然後據此發教官資格。
void _shortAnswersAreReal() {
  group('簡答題', () {
    test('抽得出規格要求的題數，而且只抽簡答題', () {
      final s = AppState();
      final sa = s.drawShortAnswerQuestions();
      expect(sa, hasLength(platformConfig.i('exam', 'saCount')));
      expect(
          sa.every((q) => q.type == ExamQuestionType.shortAnswer), isTrue);
    });

    test('題庫不足就抽不出來', () {
      expect(drawShortAnswers(_bank(20), 3), isEmpty, reason: '一題簡答都沒有');
      // **有但不夠也要抽不出來。** 只驗「完全沒有」的話，
      // 拿掉那道不足檢查照樣是綠的 —— 空清單 take(3) 本來就是空的。
      expect(drawShortAnswers(_bank(0, sa: 2), 3), isEmpty,
          reason: '只有 2 題，抽不出 3 題');
    });

    test('每次抽出來不一樣', () {
      final bank = _bank(0, sa: 10);
      final a = drawShortAnswers(bank, 3, rng: Random(1)).map((q) => q.id);
      final b = drawShortAnswers(bank, 3, rng: Random(77)).map((q) => q.id);
      expect(a, isNot(orderedEquals(b)));
    });

    test('作答內容原樣進待審案件', () {
      final s = AppState(demo: false)
        ..displayName = '阿健'
        ..examBank.addAll(_bank(25))
        ..instructorStage = InstructorStage.screenPassed;

      s.submitExam(20, shortAnswers: const [
        ('第一題？', '我的第一個回答'),
        ('第二題？', '我的第二個回答'),
      ]);

      final c = s.instructorCases.first;
      // 在此之前這裡一律是那兩題寫死的範例答案。
      expect(c.answers, hasLength(2));
      expect(c.answers.first.$2, '我的第一個回答');
      expect(c.answers.last.$2, '我的第二個回答');
    });

    test('沒傳作答時案件上是空的，不是假答案', () {
      final s = AppState(demo: false)
        ..examBank.addAll(_bank(25))
        ..instructorStage = InstructorStage.screenPassed;

      s.submitExam(20);

      // 空的看得出「沒有作答紀錄」；假的看不出來。
      expect(s.instructorCases.first.answers, isEmpty);
    });
  });
}
