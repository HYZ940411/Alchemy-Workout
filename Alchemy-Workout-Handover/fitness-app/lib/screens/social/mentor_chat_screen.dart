import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/community.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 師徒對話頁（學徒方）
///
/// **單一入口兩種動作**：直接送出為閒聊（走私訊），點「提問」才產生問答。
/// 問答與閒聊是兩種不同互動 —— 教官需要區分何者需要回答，
/// 故提問為獨立 Command，不與私訊混在同一條流水。
///
/// 頂部的本週互動摘要不是裝飾：每週評分的幅度為 −2／0／+4／+8／+12，
/// 直接連動教官聲望。學徒若只看到一顆評分按鈕，他評的是最近一次對話的心情，
/// 而非這一週。摘要使評分從憑印象變成看著紀錄。
class MentorChatScreen extends StatefulWidget {
  final Instructor instructor;
  const MentorChatScreen({super.key, required this.instructor});

  @override
  State<MentorChatScreen> createState() => _MentorChatScreenState();
}

class _MentorChatScreenState extends State<MentorChatScreen> {
  final ctrl = TextEditingController();

  /// 本頁的閒聊。問答走 [AppState.questions]，兩者分開存 ——
  /// 它們是不同的 Aggregate。
  final List<(bool mine, String text, DateTime at)> chat = [
    (false, '這週的深蹲組數我幫你調成 4 組了，先把姿勢穩住。', DateTime.now().subtract(const Duration(hours: 5))),
    (true, '收到，今天練完回報。', DateTime.now().subtract(const Duration(hours: 4))),
  ];

  @override
  void initState() {
    super.initState();
    ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  /// 距週一 04:00 重置還剩幾天 —— 評分窗口每週一重置，錯過即該週無法補評。
  int get _daysToReset {
    final now = appNow();
    final ahead = (DateTime.monday - now.weekday + 7) % 7;
    return ahead == 0 ? 7 : ahead;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final asked = s.questions.where(s.isMyQuestion).toList();
    final answered = asked.where((q) => q.answer != null).length;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: Text(widget.instructor.name)),
      body: Column(
        children: [
          // 本週互動摘要
          Container(
            color: C.bgSurface,
            padding: const EdgeInsets.all(S.base),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatField(
                          label: '本週提問／回覆',
                          value: '${asked.length} / $answered'),
                    ),
                    Expanded(
                      child: StatField(
                          label: '本週任務指派／完成',
                          value: '${s.weeklyAssigned} / ${s.weeklyCompleted}'),
                    ),
                  ],
                ),
                const SizedBox(height: S.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.ratedThisWeek
                            ? '本週已評分。'
                            : '本週尚未評分，距週一重置還有 $_daysToReset 天。',
                        style: T.caption(),
                      ),
                    ),
                    if (!s.ratedThisWeek)
                      TagBadge('待評分', borderColor: C.accentDeep),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  S.base, S.base, S.base, S.scrollBottom),
              children: [
                for (final m in chat) _Bubble(mine: m.$1, text: m.$2, at: m.$3),
                if (asked.isNotEmpty) ...[
                  const SectionTitle('提問', trailing: '教官需要回答的那些'),
                  for (final q in asked) ...[
                    _Bubble(mine: true, text: q.text, at: q.at, question: true),
                    if (q.answer != null)
                      _Bubble(mine: false, text: q.answer!, at: q.at),
                  ],
                ],
              ],
            ),
          ),

          Container(
            decoration: const BoxDecoration(
              color: C.bgSurface,
              border: Border(top: BorderSide(color: C.lineDivider)),
            ),
            padding: EdgeInsets.fromLTRB(S.base, S.md, S.base,
                MediaQuery.of(context).padding.bottom + S.base),
            child: Column(
              children: [
                Text(
                  '直接送出為閒聊；點「提問」才會進教官的待回答清單。',
                  style: T.caption(),
                ),
                const SizedBox(height: S.sm),
                TextField(
                  controller: ctrl,
                  style: T.body(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '想說點什麼？',
                    hintStyle: T.body(color: C.textDisabled),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: S.base, vertical: S.md),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.control),
                      borderSide: const BorderSide(color: C.lineDivider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.control),
                      borderSide: const BorderSide(color: C.lineDivider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.control),
                      borderSide:
                          const BorderSide(color: C.actionOutline, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: S.md),
                ButtonRow(
                  left: AppButton(
                    label: '提問',
                    kind: BtnKind.secondary,
                    onPressed: ctrl.text.trim().isEmpty
                        ? null
                        : () {
                            s.askQuestion(ctrl.text);
                            ctrl.clear();
                            showToast(context, '已送出提問');
                            setState(() {});
                          },
                  ),
                  right: AppButton(
                    label: '傳送',
                    onPressed: ctrl.text.trim().isEmpty
                        ? null
                        : () {
                            setState(() {
                              chat.add((true, ctrl.text.trim(), DateTime.now()));
                              ctrl.clear();
                            });
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool mine;
  final String text;
  final DateTime at;

  /// 提問另加標記 —— 同一條流水裡，教官要看得出哪些需要回答。
  final bool question;
  const _Bubble({
    required this.mine,
    required this.text,
    required this.at,
    this.question = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!mine) ...[
              const CircleAvatar(
                radius: 14,
                backgroundColor: C.bgSurface,
                child: Icon(Icons.school_outlined,
                    size: 14, color: C.textSecondary),
              ),
              const SizedBox(width: S.sm),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: S.base, vertical: S.md),
                decoration: BoxDecoration(
                  color: mine ? C.actionOutline : C.bgSurface,
                  borderRadius: BorderRadius.circular(R.card),
                  border: Border.all(
                      color: mine ? C.actionOutline : C.lineDivider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (question) ...[
                      Text('提問',
                          style: T.caption(color: C.onFill(C.actionOutline))),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      text,
                      // 深藍底配墨字只有 1.15:1，前景一律交給 onFill 決定。
                      style: T.body(
                          color: mine ? C.onFill(C.actionOutline) : null),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
