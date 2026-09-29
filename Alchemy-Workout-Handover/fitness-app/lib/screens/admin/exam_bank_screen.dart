import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/platform_config.dart';
import '../../domain/task_pool.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 教官測驗（設定教官測驗）
///
/// 兩種題型都保留：**選擇題由系統即時判定，簡答題由管理員人工審核**。
/// 及格採雙門檻（選擇題 ≥ 80% 且簡答題全數通過），不採總分制 ——
/// 總分制下選擇題滿分者可以簡答全錯仍及格，人工審核就形同虛設。
///
/// 題目一律自題庫隨機抽取、不固定：固定題目會使題庫外流後測驗淪為背誦，
/// 也是重考機制的前提，否則重考等於重看同一份考卷。
class ExamBankScreen extends StatefulWidget {
  const ExamBankScreen({super.key});

  @override
  State<ExamBankScreen> createState() => _ExamBankScreenState();
}

class _ExamBankScreenState extends State<ExamBankScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final mc = s.examBank
        .where((q) => q.type == ExamQuestionType.multipleChoice)
        .toList();
    final sa = s.examBank
        .where((q) => q.type == ExamQuestionType.shortAnswer)
        .toList();
    final warning = s.examBankWarning;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        title: const Text('設定教官測驗'),
        actions: [
          IconButton(
            tooltip: '新增題目',
            onPressed: s.canConfigure ? () => _add(context, s) : null,
            icon: const Icon(Icons.add, size: Sz.iconDefault),
          ),
        ],
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('管理員已設定教官測驗', style: T.body(weight: FontWeight.w600)),
                const SizedBox(height: S.sm),
                Text(
                  '題庫、題數、配分與及格標準皆由管理員調整。'
                  '設定調整不改動任何已完成作答的既有測驗結果。',
                  style: T.caption(),
                ),
              ],
            ),
          ),

          const SectionTitle('抽題與及格', trailing: '雙門檻，兩者皆須通過'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatField(
                          label: '選擇題',
                          value: '${platformConfig.i('exam', 'mcCount')}',
                          unit: '題'),
                    ),
                    Expanded(
                      child: StatField(
                          label: '簡答題',
                          value: '${platformConfig.i('exam', 'saCount')}',
                          unit: '題'),
                    ),
                    Expanded(
                      child: StatField(
                          label: '選擇題及格',
                          value: '${platformConfig.i('exam', 'mcPass')}',
                          unit: '%'),
                    ),
                  ],
                ),
                const SizedBox(height: S.md),
                Text(
                  '題數與及格標準在「平台設定 → 設定教官測驗」的參數頁調整；'
                  '本頁維護的是題庫本身。簡答題的及格標準為全數通過，不設百分比。',
                  style: T.caption(),
                ),
                const SizedBox(height: S.sm),
                // 及格條件有三重，而參數頁只看得到其中一重（百分比）。
                // 少講的那兩重正好是最容易讓管理員答不出「他為什麼沒過」的。
                Text(
                  '及格採三重門檻：選擇題達上列百分比、'
                  '標示「必答題」者不得答錯任何一題（共 ${mustCount(s)} 題，'
                  '一定會出現在每一份考卷上）、且簡答題全數通過。',
                  style: T.caption(),
                ),
              ],
            ),
          ),

          // 抽不出考卷是後台該講的事，不是等考生撞上去才發現。
          if (warning != null) ...[
            const SizedBox(height: S.base),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: Sz.iconDense, color: C.statusError),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(warning,
                        style: T.body(color: C.statusError)),
                  ),
                ],
              ),
            ),
          ],

          SectionTitle('選擇題題庫', trailing: '${mc.length} 題 · 系統即時判定'),
          _bank(context, s, mc),
          SectionTitle('簡答題題庫', trailing: '${sa.length} 題 · 管理員人工審核'),
          _bank(context, s, sa),
        ],
      ),
    );
  }

  /// 題庫裡有幾題必答題。
  int mustCount(AppState s) => s.examBank
      .where((q) =>
          q.type == ExamQuestionType.multipleChoice && q.mustPass)
      .length;

  Widget _bank(BuildContext context, AppState s, List<ExamQuestion> list) {
    if (list.isEmpty) {
      return AppCard(child: Text('題庫是空的。', style: T.caption()));
    }
    return ListGroup(rows: [
      for (var i = 0; i < list.length; i++)
        ListRow(
          title: list[i].text,
          // **必答題要看得出來。** 管理員手上如果沒有這個資訊，
          // 就無從判斷「某人 95% 卻不及格」是不是對的 ——
          // 而那正是他要向被駁回者說明的事。
          subtitle: list[i].type == ExamQuestionType.multipleChoice
              ? '${list[i].mustPass ? "必答題（答錯即不及格）　·　" : ""}'
                  '正解：${list[i].options[list[i].answerIndex]}'
              : '由管理員人工審核，無標準答案',
          trailing: s.canConfigure
              ? GestureDetector(
                  onTap: () async {
                    final ok = await showAppDialog(
                      context,
                      title: '從題庫移除這一題？',
                      message: '不影響任何已完成作答的既有測驗結果。',
                      confirmLabel: '移除',
                      destructive: true,
                    );
                    if (ok != true || !context.mounted) return;
                    showToast(context, s.removeExamQuestion(list[i]) ?? '已移除');
                    setState(() {});
                  },
                  child: const Icon(Icons.delete_outline,
                      size: Sz.iconDense, color: C.textSecondary),
                )
              : null,
          showDivider: i != list.length - 1,
        ),
    ]);
  }

  Future<void> _add(BuildContext context, AppState s) async {
    final text = TextEditingController();
    final options = [
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
      TextEditingController(),
    ];
    var type = ExamQuestionType.multipleChoice;
    var answer = 0;

    final ok = await showAppDialog(
      context,
      title: '新增題目',
      size: DialogSize.medium,
      confirmLabel: '加入題庫',
      content: StatefulBuilder(
        builder: (context, setInner) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (final t in ExamQuestionType.values)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: t == ExamQuestionType.multipleChoice
                                ? S.sm
                                : 0),
                        child: GestureDetector(
                          onTap: () => setInner(() => type = t),
                          child: Container(
                            height: Sz.buttonMinHeight,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(R.control),
                              border: Border.all(
                                color: type == t
                                    ? C.actionOutline
                                    : C.lineDivider,
                                width: type == t ? 2 : 1,
                              ),
                            ),
                            child: Text(examQuestionTypeNames[t]!,
                                style: T.body(
                                    color: type == t
                                        ? C.actionOutline
                                        : C.textSecondary)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: S.md),
              TextField(
                controller: text,
                style: T.body(),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: '題目內容',
                  hintStyle: T.body(color: C.textDisabled),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(R.control),
                  ),
                ),
              ),
              if (type == ExamQuestionType.multipleChoice) ...[
                const SizedBox(height: S.md),
                for (var i = 0; i < options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.sm),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => setInner(() => answer = i),
                          child: Icon(
                            answer == i
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: Sz.iconDense,
                            color: answer == i
                                ? C.actionOutline
                                : C.textDisabled,
                          ),
                        ),
                        const SizedBox(width: S.sm),
                        Expanded(
                          child: TextField(
                            controller: options[i],
                            style: T.body(),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '選項 ${i + 1}',
                              hintStyle: T.body(color: C.textDisabled),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(R.control),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text('圈起來的是正解。選擇題由系統即時判定。',
                    style: T.caption()),
              ] else
                Text('簡答題沒有標準答案，由管理員人工審核，時限 7 個工作天。',
                    style: T.caption()),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final opts = [
      for (final c in options)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    final failure = s.addExamQuestion(ExamQuestion(
      id: 'q${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      text: text.text,
      options: type == ExamQuestionType.multipleChoice ? opts : [],
      answerIndex: answer < opts.length ? answer : 0,
    ));
    showToast(context, failure ?? '已加入題庫');
    setState(() {});
  }
}
