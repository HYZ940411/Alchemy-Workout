import 'package:flutter/material.dart';

import '../../domain/community.dart';
import '../../domain/platform_config.dart';
import '../../domain/task_pool.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：教官申請頁
class InstructorApplyScreen extends StatelessWidget {
  const InstructorApplyScreen({super.key});

  static const _stageNames = <InstructorStage, String>{
    InstructorStage.notApplied: '尚未申請',
    InstructorStage.screening: '初審中',
    InstructorStage.screenPassed: '已初審通過',
    InstructorStage.testing: '測驗中',
    InstructorStage.pendingReview: '待人工審核',
    InstructorStage.approved: '已通過',
    InstructorStage.rejected: '已駁回',
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // 門檻數值取自平台級可調參數，管理員調整後本 Read Model 即時反映。
    final g = s.instructorGate;
    // **按得下申請鍵的條件是 `canApply`（階級與次數），不是 `passed`。**
    // `passed` 還包含品質評分，而評分發生在申請**之後** ——
    // 讀它的話，門檻達標的人也永遠按不下去。
    final qualified = g.canApply;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('教官申請',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 50),
        children: [
          const SectionLabel('初審條件', trailing: '兩條件須同時成立'),
          Panel(
            child: Column(
              children: [
                _Condition(
                  // **標題不寫規格術語**（2026-09-28 使用者要求）。
                  // 「／需求階級」「／通過門檻」「／一票否決門檻」是事件風暴的
                  // 欄位名 —— 右邊那個 `51 / 20` 已經把「現值 / 門檻」講完了，
                  // 標題再重複一次只是把規格搬到前台。
                  label: '我的階級',
                  value: '${s.rank} / ${g.requiredRank}',
                  ok: g.rankOk,
                ),
                const Divider(height: 22, color: AppColors.line),
                _Condition(
                  // 品質分達折抵門檻者，需求次數改用折抵後的值；階級門檻不折抵。
                  // **「已折抵」留著** —— 那不是術語，是「你的門檻比別人低」
                  // 這件事，不說他會以為數字錯了。
                  label: g.discounted ? '累積訓練次數（已折抵）' : '累積訓練次數',
                  value: '${s.totalWorkouts} / ${g.requiredWorkouts}',
                  ok: g.workoutsOk,
                ),
                const Divider(height: 22, color: AppColors.line),
                // **沒評過就寫「尚未評分」，不寫 0。**
                //
                // 規格的時序是：申請 → 初審（階級與次數）→ 分析訓練品質。
                // 評分屬於**一筆申請**（請求識別碼含教官申請 ID），
                // 不屬於這個人 —— 沒有申請就沒有評分。
                //
                // 而 0 看起來像「很低的分數」。使用者回報「練了 7 次還是 0」
                // 時，問題不是沒算，是把「沒有分數」畫成了 0。
                // **暫估的分數不打勾。**
                //
                // AI 評分失敗時會退回端內規則算一份備援值，而初審採用的
                // 是 AI 那一份 —— 打了勾看起來像已經通過，但階段仍停在
                // 「初審中」，兩者當著使用者的面互相矛盾（他截圖回報過）。
                _Condition(
                  label: '訓練品質評分',
                  value: !s.qualityScored
                      ? '尚未評分'
                      : s.qualityIsProvisional
                          ? '暫估 ${s.qualityScore}（等 AI 評分）'
                          : '${s.qualityScore} / '
                              '${platformConfig.i('instructorGate', 'qualityPass')}',
                  ok: g.qualityOk && !s.qualityIsProvisional,
                ),
                const Divider(height: 22, color: AppColors.line),
                _Condition(
                  // 一票否決獨立於加權平均：該單項低於門檻即駁回。
                  // **那件事不寫在標題上** —— 它是規則，不是這一列的名字。
                  label: '紀錄合理性',
                  value: !s.qualityScored
                      ? '尚未評分'
                      : s.qualityIsProvisional
                          ? '暫估 ${s.sanityScore}（等 AI 評分）'
                          : '${s.sanityScore} / '
                              '${platformConfig.i('instructorGate', 'veto')}',
                  ok: !g.vetoed && !s.qualityIsProvisional,
                ),
              ],
            ),
          ),
          const SectionLabel('目前階段'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('申請階段',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                    Pill(_stageNames[s.instructorStage]!,
                        color: s.instructorStage == InstructorStage.approved
                            ? AppColors.accent
                            : AppColors.blue),
                  ],
                ),
                // 每個階段講自己的話。
                //
                // 「評分處理中」是**初審中**的訊息（AI 品質評分失敗、隔日重跑），
                // 原本掛在「待人工審核」上 —— 兩個不同階段用同一句話，
                // 而且是另一個階段的那一句。
                if (_note(s) != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _note(s)!,
                      style: const TextStyle(
                          color: AppColors.blue, fontSize: 11.5, height: 1.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel('教官測驗', trailing: '雙門檻，兩者皆須通過'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                _Info(
                    label: '選擇題',
                    value: '${platformConfig.i('exam', 'mcCount')} 題　·　及格 ${(platformConfig.i('exam', 'mcCount') * platformConfig.i('exam', 'mcPass') / 100).ceil()} 題'),
                _Info(
                    label: '簡答題',
                    value: '${platformConfig.i('exam', 'saCount')} 題　·　管理員人工審核，須全數通過'),
                const _Info(label: '及格判定', value: '選擇題與簡答題皆須通過'),
              ],
            ),
          ),
          // 申請時須填寫專長：值域由管理員維護，至少 1 項至多 3 項。
          if (s.instructorStage == InstructorStage.notApplied) ...[
            SectionLabel('教學專長',
                trailing: '$kSpecialtyMin–$kSpecialtyMax 項　·　'
                    '已選 ${s.instructorSpecialties.length}'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in kInstructorSpecialties)
                        GestureDetector(
                          onTap: () => s.toggleSpecialty(v),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              // §4.4：選取態為 2px 外框，不換底色。
                              border: Border.all(
                                color: s.instructorSpecialties.contains(v)
                                    ? C.actionOutline
                                    : AppColors.line,
                                width:
                                    s.instructorSpecialties.contains(v) ? 2 : 1,
                              ),
                            ),
                            child: Text(v,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      s.instructorSpecialties.contains(v)
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                  color: s.instructorSpecialties.contains(v)
                                      ? C.actionOutline
                                      : AppColors.textDim,
                                )),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 原本這段在解釋「值域為什麼這樣設計」（刻意不含、等同平台
                  // 替你背書…）—— 那是給讀規格的人看的。使用者要知道的只有
                  // 「為什麼我想選的不在清單上」（`[QA-02m]`）。
                  const Text(
                    '專長不含六大肌群 —— 你的六維能力值在教官清單上本來就會顯示。'
                    '也不含飲食營養、傷後復健等需要執照的項目。',
                    style: TextStyle(
                        color: AppColors.textFaint, fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ],

          if (s.examMcScore != null) ...[
            const SizedBox(height: 12),
            Panel(
              child: Text(
                '上次選擇題 ${s.examMcScore} 分'
                '（及格 ${s.examPassMark}）'
                '${s.examMcPassed ? '，已通過' : '，未達及格標準'}。'
                '簡答題送管理員人工審核，時限 7 個工作天。'
                '${s.examRetakeLeft > Duration.zero ? '重考還要等 ${s.examRetakeLeft.inDays + 1} 天。' : ''}',
                style: const TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ),
          ],

          // 僅首次成為教官時確認一次；聲明改版後須重新確認。
          if (s.instructorDutyNeeded) ...[
            const SectionLabel('指導責任聲明', trailing: '未確認不得回答與指派任務'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '你給的建議會被學徒當成專業意見執行。平台不為指導內容擔保，'
                    '也不代表你具備任何證照。請在自己能判斷的範圍內指導，'
                    '遇到傷痛或醫療問題一律請對方就醫。',
                    style: TextStyle(fontSize: 12.5, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: '我已了解並確認（$kInstructorDutyVersion）',
                      onPressed: () {
                        s.confirmInstructorDuty();
                        showToast(context, '已確認，現在可以回答與指派任務');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: switch (s.instructorStage) {
                InstructorStage.notApplied => !qualified
                    ? '尚未達到初審條件'
                    : (s.specialtyBlockedReason ?? '申請教官資格'),
                InstructorStage.approved => '你已是教官',
                InstructorStage.screenPassed ||
                InstructorStage.testing =>
                  s.examRetakeLeft > Duration.zero
                      ? '重考還要等 ${s.examRetakeLeft.inDays + 1} 天'
                      : '作答教官測驗',
                InstructorStage.pendingReview => '等管理員審核簡答題',
                InstructorStage.rejected => s.examRetakeLeft > Duration.zero
                    ? '重新申請還要等 ${s.examRetakeLeft.inDays + 1} 天'
                    : '重新申請',
                // **初審中沒有按鈕可按** —— 那一階段的下一步是系統的
                // Command（AI 評分回來就結算），不是申請人的。
                //
                // 在此之前這裡是「推進到下一階段（Demo）」，而它會跳過
                // 品質評分與測驗、還以滿分送出考卷。那是示範用的捷徑，
                // 不該出現在真的帳號上（使用者回報「教官申請是寫 Demo」）。
                InstructorStage.screening =>
                  s.developerMode ? '推進到下一階段（Demo）' : '等待系統評分',
              },
              onPressed: switch (s.instructorStage) {
                // 待人工審核的下一步是管理員的 Command ——
                // 這裡放一顆按得下去的按鈕，等於申請人自己核准自己。
                InstructorStage.approved ||
                InstructorStage.pendingReview =>
                  null,
                InstructorStage.rejected => s.examRetakeLeft > Duration.zero
                    ? null
                    : s.reapplyInstructor,
                InstructorStage.screenPassed ||
                InstructorStage.testing =>
                  s.examRetakeLeft > Duration.zero
                      ? null
                      : () => _takeExam(context, s),
                // 申請本身（尚未申請 → 初審中）是使用者的 Command，
                // 一般使用者當然按得下去。其餘階段的推進是**示範用捷徑**，
                // 只給開發者模式。
                InstructorStage.notApplied => (qualified &&
                        s.specialtyBlockedReason == null)
                    ? s.advanceInstructorApplication
                    : null,
                _ => s.developerMode ? s.advanceInstructorApplication : null,
              },
            ),
          ),
          // 撤銷是管理員的 Command —— 這顆是示範用捷徑，只給開發者模式。
          if (s.isInstructor && s.developerMode) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              // 撤銷因違規而發生，既有師徒關係一併解除。
              child: AppButton(
                label: '（Demo）管理員撤銷教官資格',
                kind: BtnKind.secondary,
                onPressed: () {
                  s.revokeInstructor();
                  showToast(context, '教官資格已撤銷，既有師徒關係一併解除');
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Condition extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;
  const _Condition({required this.label, required this.value, required this.ok});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: ok ? AppColors.accent : AppColors.textFaint,
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: ok ? AppColors.accent : AppColors.textDim,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      );
}

/// 使用者已作答教官測驗。選擇題即時判定，簡答題送人工審核。
/// 題目每次隨機抽取 —— 固定題目會使題庫外流後測驗淪為背誦，重考也失去意義。
///
/// **在此之前這裡是一個拉桿**：申請人自己拉「答對幾題」，那個數字直接
/// 被當成成績。沒有出題、沒有判卷 —— 也就是任何人都能給自己滿分。
Future<void> _takeExam(BuildContext context, AppState s) async {
  final paper = s.drawExam();
  if (paper.isEmpty) {
    // 題庫不足時擋住，而且說出是哪一種不足。
    // **不抽「有幾題就幾題」** —— 及格標準是百分比，那會靜靜地
    // 降低門檻：20 題要對 16 題，4 題只要對 4 題也是同一個 80%。
    showToast(context, s.examBankWarning ?? '題庫不足，暫時無法作答。');
    return;
  }

  final sa = s.drawShortAnswerQuestions();
  if (sa.isEmpty) {
    showToast(context, s.examBankWarning ?? '題庫不足，暫時無法作答。');
    return;
  }

  final done = await Navigator.of(context).push<_ExamResult>(MaterialPageRoute(
      builder: (_) => _ExamPaperScreen(paper: paper, shortAnswers: sa)));
  if (done == null || !context.mounted) return;

  final correct = s.gradeExam(paper, done.choices);
  s.submitExam(
    correct,
    // **申請人真正寫的內容。** 在此之前送進待審佇列的是兩題寫死的
    // 範例答案 —— 管理員據此發教官資格，而那不是他寫的。
    shortAnswers: [
      for (final q in sa) (q.text, done.written[q.id] ?? ''),
    ],
  );
  if (!context.mounted) return;
  showToast(
    context,
    s.examMcPassed
        ? '選擇題 $correct/${paper.length} 通過，簡答題送人工審核'
        : '選擇題 $correct/${paper.length}，未達及格標準',
  );
}

/// 一份交出來的考卷。
class _ExamResult {
  /// 選擇題：題目 ID → 選了第幾個選項。
  final Map<String, int> choices;

  /// 簡答題：題目 ID → 寫了什麼。
  final Map<String, String> written;
  const _ExamResult(this.choices, this.written);
}

/// 作答頁 —— 一題一張卡，全部作答完才能交卷。
///
/// 一次列出全部而不是一題一頁：題數由平台設定（目前 20 ＋ 3），
/// 分頁要多一層「上一題」的狀態，而作答本身沒有順序相依。
class _ExamPaperScreen extends StatefulWidget {
  final List<ExamQuestion> paper;
  final List<ExamQuestion> shortAnswers;
  const _ExamPaperScreen({required this.paper, required this.shortAnswers});

  @override
  State<_ExamPaperScreen> createState() => _ExamPaperScreenState();
}

class _ExamPaperScreenState extends State<_ExamPaperScreen> {
  final _answers = <String, int>{};
  final _written = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final q in widget.shortAnswers) {
      _written[q.id] = TextEditingController()..addListener(_onTyped);
    }
  }

  @override
  void dispose() {
    for (final c in _written.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTyped() => setState(() {});

  /// 還有幾題沒作答。簡答題**空白或只有空格都算沒作答**。
  int get _left =>
      widget.paper.length -
      _answers.length +
      _written.values.where((c) => c.text.trim().isEmpty).length;

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final total = widget.paper.length + widget.shortAnswers.length;
    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: Text('教官測驗　$total 題')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(S.base, S.base, S.base, S.scrollBottom),
        children: [
          for (var i = 0; i < widget.paper.length; i++)
            _question(i, widget.paper[i]),
          if (widget.shortAnswers.isNotEmpty) ...[
            const SectionTitle('簡答題'),
            // 這幾題不由系統判 —— 說清楚，免得有人以為交卷就知道結果。
            Padding(
              padding: const EdgeInsets.only(bottom: S.md),
              child: Text('由管理員人工審核，7 個工作天內完成。',
                  style: T.caption()),
            ),
            for (var i = 0; i < widget.shortAnswers.length; i++)
              _shortAnswer(widget.paper.length + i, widget.shortAnswers[i]),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(S.base),
          child: AppButton(
            label: left == 0 ? '交卷' : '還有 $left 題未作答',
            // **未作答不給交卷。** 選擇題沒作答判卷時算錯，簡答題空白
            // 送到管理員手上也只會被退 —— 而交卷之後 14 天不能重考。
            onPressed: left == 0
                ? () => Navigator.of(context).pop(_ExamResult(
                      Map.of(_answers),
                      {
                        for (final e in _written.entries)
                          e.key: e.value.text.trim(),
                      },
                    ))
                : null,
          ),
        ),
      ),
    );
  }

  Widget _shortAnswer(int index, ExamQuestion q) => Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${index + 1}.　${q.text}',
                  style: T.body(weight: FontWeight.w700)),
              const SizedBox(height: S.sm),
              TextField(
                controller: _written[q.id],
                maxLines: 5,
                minLines: 3,
                style: T.body(),
                decoration: const InputDecoration(
                  hintText: '寫下你的作法與理由…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _question(int index, ExamQuestion q) => Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${index + 1}.　${q.text}',
                  style: T.body(weight: FontWeight.w700)),
              const SizedBox(height: S.sm),
              for (var o = 0; o < q.options.length; o++)
                RadioListTile<int>(
                  value: o,
                  // ignore: deprecated_member_use
                  groupValue: _answers[q.id],
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() => _answers[q.id] = v!),
                  title: Text(q.options[o], style: T.body()),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
      );
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 12.5)),
          ],
        ),
      );
}

/// 各階段的補充說明。回傳 null 代表這一階段沒有話要說。
String? _note(AppState s) => switch (s.instructorStage) {
      // **只在真的失敗時才說失敗。**
      //
      // 原本這一句是無條件的 —— 只要停在「初審中」就寫「AI 品質評分失敗」，
      // 不管評分到底成不成功。那是對使用者說了一件沒發生的事。
      //
      // 規格只要求他看到「評分處理中」；失敗那一句是額外的誠實，
      // 而誠實的前提是它真的發生了。
      InstructorStage.screening => s.qualityScoreError == null
          ? '評分處理中：系統正在分析你的歷史訓練紀錄。'
          : '評分處理中：AI 評分暫時失敗，系統會於隔日重跑，'
              '不會因此駁回你的申請。',
      InstructorStage.pendingReview =>
        '簡答題已送出，等管理員人工審核（7 個工作天內完成）。逾時不會自動通過。',
      InstructorStage.rejected => s.instructorRejectStage == null
          ? '申請已被駁回。'
          : '申請在「${s.instructorRejectStage}」這一關被駁回，'
              '距上次作答滿 14 天可再次申請。',
      _ => null,
    };
