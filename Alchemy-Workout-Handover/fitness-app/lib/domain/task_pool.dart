/// 每日任務池 —— **同時承載限時任務**
///
/// 兩者的欄位完全相同（名稱、判定來源 Event、目標次數、獎勵定義 ID），
/// 以「適用對象」欄位區分，**不另立限時任務 Aggregate** ——
/// 另立等於管理員要維護兩份內容重疊的清單，日後加欄位還得記得兩邊都加。
///
/// 指派方式不同，由各自流程承載：每日任務隨機抽 3 項給個人，
/// 限時任務每日指派一組給全平台所有團隊。
library;

import 'dart:math' as math;

import 'platform_config.dart';

/// 適用對象。個人者供每日任務抽取，團隊者供限時任務指派。
enum TaskAudience { personal, team }

const taskAudienceNames = <TaskAudience, String>{
  TaskAudience.personal: '個人',
  TaskAudience.team: '團隊',
};

/// 一個任務項目。**可組態的 Event 訂閱** ——
/// 管理員新增任務時只需指定判定來源 Event 與目標次數，不需改動系統程式。
class TaskPoolItem {
  final String id;
  String name;

  /// 系統訂閱此 Event 以累計進度。模型現有的每一個 Event 皆可作為判定來源。
  String sourceEvent;

  /// 該 Event 發生幾次視為完成。
  int target;
  TaskAudience audience;

  /// 完成該項時發放的獎勵定義 ID。
  String rewardId;

  TaskPoolItem({
    required this.id,
    required this.name,
    required this.sourceEvent,
    required this.target,
    this.audience = TaskAudience.personal,
    this.rewardId = 'daily',
  });

  String get summary =>
      '判定來源：$sourceEvent　·　目標 $target 次　·　'
      '${taskAudienceNames[audience]}';
}

/// 每日抽取數量。存於每日任務池 Aggregate，由管理員調整。
int get kDailyDrawCount => platformConfig.i('taskPool', 'drawCount');

/// 自任務池隨機抽取指派。
///
/// **允許與前一日重複，不做去重**：任務池的內容本來就是「訓練一次」
/// 「按讚 3 次」這類日常行為，連續兩日重複屬正常；且去重規則會隱含要求
/// 任務池維持足夠數量，管理員縮減池子時系統將抽不出來。
///
/// **項目數少於抽取數量時，抽出全部項目。**
List<TaskPoolItem> drawDaily(
  List<TaskPoolItem> pool,
  int count, {
  math.Random? rng,
}) {
  final personal =
      pool.where((t) => t.audience == TaskAudience.personal).toList();
  if (personal.length <= count) return personal;
  final r = rng ?? math.Random();
  final picked = <TaskPoolItem>[];
  final rest = [...personal];
  while (picked.length < count && rest.isNotEmpty) {
    picked.add(rest.removeAt(r.nextInt(rest.length)));
  }
  return picked;
}

/// 供限時任務指派的項目 —— 適用對象為團隊者。
List<TaskPoolItem> teamItems(List<TaskPoolItem> pool) =>
    pool.where((t) => t.audience == TaskAudience.team).toList();

// ---------------------------------------------------------------------------
// 教官測驗題庫
// ---------------------------------------------------------------------------

/// 題型。**兩種題型都保留**：選擇題由系統即時判定，簡答題由管理員人工審核。
enum ExamQuestionType { multipleChoice, shortAnswer }

const examQuestionTypeNames = <ExamQuestionType, String>{
  ExamQuestionType.multipleChoice: '選擇題',
  ExamQuestionType.shortAnswer: '簡答題',
};

class ExamQuestion {
  final String id;
  final ExamQuestionType type;
  String text;

  /// 選擇題的選項與正解索引；簡答題兩者皆空。
  List<String> options;
  int answerIndex;

  ExamQuestion({
    required this.id,
    required this.type,
    required this.text,
    List<String>? options,
    this.answerIndex = 0,
  }) : options = options ?? [];
}

/// 抽一份考卷 —— 自題庫隨機取 [mcCount] 題選擇題。
///
/// **題庫不足時回空清單**，呼叫端據此擋住作答（訊息用
/// [examBankShortage]）。不回「抽得出幾題就幾題」：那會**靜靜地降低
/// 及格門檻** —— 及格標準是百分比，20 題要對 16 題，4 題只要對 4 題
/// 卻是同一個 80%，而那張考卷根本不是同一場考試。
///
/// [rng] 由呼叫端傳入，測試才驗得到「抽出來的是題庫裡的題目、不重複、
/// 而且每次不一樣」。
///
/// 在此之前**沒有這個函式**：作答畫面是一個拉桿，申請人自己拉答對
/// 幾題，然後那個數字直接被當成成績。沒有出題，也沒有判卷。
List<ExamQuestion> drawExamPaper(
  List<ExamQuestion> bank,
  int mcCount, {
  math.Random? rng,
}) {
  final mc = bank
      .where((q) => q.type == ExamQuestionType.multipleChoice)
      .toList();
  if (mc.length < mcCount) return const [];
  mc.shuffle(rng ?? math.Random());
  return mc.take(mcCount).toList();
}

/// 抽簡答題 —— 自題庫隨機取 [saCount] 題。
///
/// 與 [drawExamPaper] 分開兩支，因為兩者**送去的地方不同**：
/// 選擇題由系統即時判定，簡答題送管理員人工審核（規格明訂的雙門檻）。
/// 合成一支回傳混在一起的清單，呼叫端還是得再分一次。
List<ExamQuestion> drawShortAnswers(
  List<ExamQuestion> bank,
  int saCount, {
  math.Random? rng,
}) {
  final sa =
      bank.where((q) => q.type == ExamQuestionType.shortAnswer).toList();
  if (sa.length < saCount) return const [];
  sa.shuffle(rng ?? math.Random());
  return sa.take(saCount).toList();
}

/// 判卷 —— [answers] 是「題目 ID → 選了第幾個選項」，回傳答對幾題。
///
/// **沒作答的題目算錯**，不是略過：略過的話交白卷會是 0/0，
/// 而 0/0 在百分比上是未定義的，實作起來很容易變成 100%。
int gradeExamPaper(List<ExamQuestion> paper, Map<String, int> answers) {
  var correct = 0;
  for (final q in paper) {
    if (answers[q.id] == q.answerIndex) correct++;
  }
  return correct;
}

/// 題庫是否足夠抽出一份考卷。
///
/// 題目**一律自題庫隨機抽取，不固定** —— 固定題目會使題庫答案外流後
/// 測驗淪為背誦；隨機抽取也是重考機制的前提，否則重考等於重看同一份考卷。
String? examBankShortage(List<ExamQuestion> bank, int mcCount, int saCount) {
  final mc = bank
      .where((q) => q.type == ExamQuestionType.multipleChoice)
      .length;
  final sa = bank
      .where((q) => q.type == ExamQuestionType.shortAnswer)
      .length;
  if (mc < mcCount) return '選擇題題庫只有 $mc 題，抽不出 $mcCount 題。';
  if (sa < saCount) return '簡答題題庫只有 $sa 題，抽不出 $saCount 題。';
  return null;
}
