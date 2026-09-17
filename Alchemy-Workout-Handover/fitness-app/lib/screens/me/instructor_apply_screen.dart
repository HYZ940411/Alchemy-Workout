import 'package:flutter/material.dart';

import '../../domain/community.dart';
import '../../domain/platform_config.dart';
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
    final qualified = g.passed;

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
                  label: '我的階級 / 需求階級',
                  value: '${s.rank} / ${g.requiredRank}',
                  ok: g.rankOk,
                ),
                const Divider(height: 22, color: AppColors.line),
                _Condition(
                  // 品質分達折抵門檻者，需求次數改用折抵後的值；階級門檻不折抵。
                  label: g.discounted
                      ? '累積訓練次數 / 需求次數（已折抵）'
                      : '累積訓練次數 / 需求次數',
                  value: '${s.totalWorkouts} / ${g.requiredWorkouts}',
                  ok: g.workoutsOk,
                ),
                const Divider(height: 22, color: AppColors.line),
                _Condition(
                  label: '訓練品質評分 / 通過門檻',
                  value: '${s.qualityScore} / '
                      '${platformConfig.i('instructorGate', 'qualityPass')}',
                  ok: g.qualityOk,
                ),
                const Divider(height: 22, color: AppColors.line),
                _Condition(
                  // 一票否決獨立於加權平均：該單項低於門檻即駁回。
                  label: '紀錄合理性 / 一票否決門檻',
                  value: '${s.sanityScore} / '
                      '${platformConfig.i('instructorGate', 'veto')}',
                  ok: !g.vetoed,
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
                _ => '推進到下一階段（Demo）',
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
                _ => (qualified &&
                        (s.instructorStage != InstructorStage.notApplied ||
                            s.specialtyBlockedReason == null))
                    ? s.advanceInstructorApplication
                    : null,
              },
            ),
          ),
          if (s.isInstructor) ...[
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
Future<void> _takeExam(BuildContext context, AppState s) async {
  final total = platformConfig.i('exam', 'mcCount');
  var correct = (total * 0.9).round();
  final ok = await showAppDialog(
    context,
    title: '作答教官測驗',
    confirmLabel: '交卷',
    content: StatefulBuilder(
      builder: (context, setInner) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$total 題選擇題 ＋ ${platformConfig.i('exam', 'saCount')} 題簡答。'
            'Demo 直接拉答對題數：交卷後選擇題即時判定，簡答題等管理員審。',
            style: T.caption(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: S.base),
          Text('答對 \$correct / \$total 題', style: T.numberM()),
          Slider(
            value: correct.toDouble(),
            min: 0,
            max: total.toDouble(),
            divisions: total,
            onChanged: (v) => setInner(() => correct = v.round()),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  s.submitExam(correct);
  showToast(context, '已交卷，簡答題送人工審核');
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
      InstructorStage.screening => '評分處理中：AI 品質評分失敗，待隔日重跑。',
      InstructorStage.pendingReview =>
        '簡答題已送出，等管理員人工審核（7 個工作天內完成）。'
            '逾時不會自動通過 —— 教官是具權限的身分。',
      InstructorStage.rejected => s.instructorRejectStage == null
          ? '申請已被駁回。'
          : '申請在「${s.instructorRejectStage}」這一關被駁回，'
              '距上次作答滿 14 天可再次申請。',
      _ => null,
    };
