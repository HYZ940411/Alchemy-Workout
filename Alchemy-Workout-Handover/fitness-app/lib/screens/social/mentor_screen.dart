import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/community.dart';
import '../../domain/inbound.dart';
import '../../state/app_state.dart';
import '../me/instructor_apply_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'inbox_screen.dart';
import 'mentor_chat_screen.dart';
import 'mentor_interaction_screen.dart';

/// 師徒：未解鎖 → 未拜師（教官清單）→ 已拜師（我的師徒頁）
class MentorScreen extends StatelessWidget {
  const MentorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.mentorUnlocked) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: AppColors.textDim),
                    SizedBox(width: 9),
                    Text('師徒功能尚未解鎖',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                // 逐項列出還差什麼 —— 只給一個進度條，使用者不知道該做什麼。
                const Text('五種社群行為各做過一次即解鎖：',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                const SizedBox(height: 8),
                for (final e in s.mentorUnlockProgress.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          e.value > 0
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          size: 15,
                          color: e.value > 0
                              ? C.statusSuccess
                              : AppColors.textFaint,
                        ),
                        const SizedBox(width: 8),
                        Text(e.key, style: T.body()),
                        const Spacer(),
                        Text(e.value > 0 ? '已完成' : '尚未做過',
                            style: T.caption()),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                ProgressBar(
                  value: s.mentorUnlockProgress.values
                          .where((v) => v > 0)
                          .length /
                      s.mentorUnlockProgress.length,
                ),
              ],
            ),
          ),
        ],
      );
    }
    // **有人想拜我為師，這一頁要講出來。**
    //
    // 拜師申請進的是 `inbox`，而收件匣的入口在「我的 → 收件匣」——
    // 師徒頁上**沒有任何跡象**。於是一位教官打開師徒頁，
    // 看到的是「我的學徒（0）」與一份拜師清單，
    // 而有人正在等他回應（使用者 2026-09-29 實測 T1 回報 C：
    // 「重整也沒有」—— 他看的是師徒頁，而那裡本來就不會顯示）。
    //
    // 回應仍然在收件匣做，這裡只負責**讓他知道有這件事**：
    // 接受／拒絕的判定（名額、停權、逾期）已經在那裡了，
    // 複製第二份就會有兩份慢慢長不一樣的規則。
    final applies = s.liveInbox
        .where((r) => r.kind == InboundKind.apprenticeApply)
        .toList();

    return Column(
      children: [
        if (applies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.base, S.base, S.base, 0),
            child: Panel(
              color: C.statusWarning.withValues(alpha: 0.08),
              border: C.statusWarning,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('有 ${applies.length} 位想拜你為師',
                      style: T.body(weight: FontWeight.w700)),
                  const SizedBox(height: S.xs),
                  Text(
                    applies.map((r) => r.from).join('、'),
                    style: T.caption(),
                  ),
                  const SizedBox(height: S.md),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: '去收件匣回應',
                      kind: BtnKind.secondary,
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const InboxScreen())),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // 教官身分者另有帶徒的一側
        if (s.isInstructor)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.base, S.base, S.base, 0),
            child: AppButton(
              label: '我的學徒（師徒互動頁）',
              kind: BtnKind.secondary,
              icon: Icons.school_outlined,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const MentorInteractionScreen())),
            ),
          ),
        Expanded(
          // **三種狀態，不是兩種。** `myInstructor == null` 既可能是
          // 「我還沒拜師」，也可能是「師徒那一塊還沒讀回來」——
          // 在此之前兩者都畫成拜師清單，等於在同步失敗時對著一位
          // 有教官的人說「你沒有教官」。而那不會報錯：師徒那一塊是
          // 各自 try、吞掉錯誤的，出問題時完全沒有跡象。
          child: s.myInstructor != null
              ? const _MyMentor()
              : s.mentorKnown
                  ? const _InstructorList()
                  : const _MentorUnknown(),
        ),
      ],
    );
  }
}

/// 師徒關係還沒讀回來。
///
/// 留白而不是猜一個答案（守則第 5 條：**填錯的數字比留白更糟**）。
/// 這一頁會退到這裡，代表登入時師徒那一塊失敗了 —— 通常是連線，
/// 也可能是安全規則。給一顆重試鍵，不必整個重新載入 App。
class _MentorUnknown extends StatefulWidget {
  const _MentorUnknown();

  @override
  State<_MentorUnknown> createState() => _MentorUnknownState();
}

class _MentorUnknownState extends State<_MentorUnknown> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: '師徒資料還沒讀到',
      message: '這不代表你沒有教官 —— 是這一次沒讀回來。',
      action: AppButton(
        label: _busy ? '重新讀取中' : '重新讀取',
        kind: BtnKind.secondary,
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                await s.refreshInbound();
                if (mounted) setState(() => _busy = false);
              },
      ),
    );
  }
}

/// Read Model：教官清單
class _InstructorList extends StatelessWidget {
  const _InstructorList();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      children: [
        // **自己也能當教官** —— 入口原本只在「我的」→ 更多底下，
        // 而會想當教官的人正是在這一頁看別人的教官檔案的人
        //（使用者裁決 2026-09-26）。
        //
        // 已經是教官的不顯示：那一頁對他只剩「你已通過」一句話。
        // **與團隊頁的「你目前沒有團隊」同一張卡**（2026-09-28 使用者要求：
        // 「希望跟團隊的『建立團隊』按鈕跟標題方式長得一樣」）。
        //
        // 兩處是同一件事：這一頁對還沒加入的人是空的，而空的時候要講得出
        // 「你可以做什麼」。長相不一樣只會讓人以為是兩種不同的東西。
        if (!s.isInstructor) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('你還不是教官',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  '通過初審與測驗後可以帶學徒。門檻是階級 '
                  '${s.instructorGate.requiredRank} 與累積訓練 '
                  '${s.instructorGate.requiredWorkouts} 次，'
                  '你目前是階級 ${s.rank}、${s.totalWorkouts} 次。',
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: '我要成為教官',
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const InstructorApplyScreen())),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.base),
        ],
        for (final i in s.instructors) _InstructorCard(instructor: i),
      ],
    );
  }
}

class _InstructorCard extends StatelessWidget {
  final Instructor instructor;
  const _InstructorCard({required this.instructor});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: AppColors.surfaceAlt,
                  child: Text(instructor.name.characters.first,
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(instructor.name,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        // 教官現在的階級，不是建立師徒關係當下那個。
                        '${s.rankOf(instructor.name, uid: instructor.uid, fallback: instructor.rank)} 階　·　'
                        '綜合 ${overallGrade(instructor.ability)}　·　'
                        '聲望 ${instructor.reputation}',
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                // **沒有評分就說沒有評分。** 原本一律畫出星號與
                // 「0.0（0 則）」—— 那看起來像「被評過、但分數是 0」，
                // 而拜師就是看這個數字挑人的。
                if (instructor.ratingCount == 0)
                  Text('尚無評分',
                      style: const TextStyle(
                          color: AppColors.textFaint, fontSize: 11))
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: C.accentDeep),
                          const SizedBox(width: 3),
                          Text(instructor.avgRating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      Text('${instructor.ratingCount} 則',
                          style: const TextStyle(
                              color: AppColors.textFaint, fontSize: 10)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sp in instructor.specialties)
                  Pill(sp, color: AppColors.blue),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < Dim.values.length; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(dimNames[Dim.values[i]]!,
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 10)),
                        const SizedBox(height: 3),
                        Text(
                          majorGradeOf(instructor.ability[Dim.values[i]]!),
                          style: TextStyle(
                            color: C.gradeFill(
                                majorGradeOf(instructor.ability[Dim.values[i]]!)),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 22, color: AppColors.line),
            Row(
              children: [
                Expanded(
                  // **這個數字就是「他實際帶著幾位學徒」。**
                  //
                  // 2026-09-29 使用者裁決：待回應的申請不再佔名額
                  // （見 `AppState.apprenticeCountOf`）。在那之前送出申請的
                  // 當下數字就 +1，而對方還沒答應 —— 那行字在說一件
                  // 不是事實的事。
                  child: Text(
                    '學徒 ${s.apprenticeCountOf(instructor)} / '
                    '${instructor.apprenticeCap}',
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12),
                  ),
                ),
                Builder(builder: (context) {
                  final blocked = s.mentorApplyBlockedReason(instructor);
                  final sent = s.mentorApplications
                      .any((a) => a.name == instructor.name);
                  // **送出之後這顆不再是主要動作。**
                  //
                  // 原本送出後仍是 `BtnKind.primary`（亮色），而且**按得下去**
                  // —— 按下去跑的是 `acceptMentorApplication()`，也就是
                  // 「對方已接受」。那是**示範用的捷徑接在正式畫面上**：
                  // 真使用者按一下，師徒關係就單方面建立了，教官那側
                  // 從頭到尾沒有同意過。使用者 2026-09-29 指出顏色不對，
                  // 查下去發現顏色只是表層。
                  //
                  // 示範模式保留那個捷徑 —— 沒有第二個人可以按「接受」，
                  // 拿掉的話那條流程在示範裡走不完。
                  if (sent) {
                    return AppButton(
                      label: '已申請',
                      kind: BtnKind.secondary,
                      onPressed: s.demo
                          ? () => s.acceptMentorApplication(instructor)
                          : null,
                    );
                  }
                  return AppButton(
                    label: blocked != null ? '不可申請' : '申請師徒關係',
                    onPressed: blocked != null
                        ? null
                        : () {
                            s.applyMentor(instructor);
                            showToast(context, '已送出申請，7 天內未回應即逾期');
                          },
                    kind: BtnKind.primary,
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Read Model：我的師徒頁（學徒方）
class _MyMentor extends StatelessWidget {
  const _MyMentor();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ins = s.myInstructor!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      children: [
        Panel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.surfaceAlt,
                child: Text(ins.name.characters.first,
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 17)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ins.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final sp in ins.specialties)
                          Pill(sp, color: AppColors.blue),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.md),
        if (!s.mentorReleased)
          AppButton(
            label: '解除師徒關係',
            kind: BtnKind.secondary,
            onPressed: () => _release(context, s, ins),
          ),
        const SizedBox(height: S.md),
        AppButton(
          label: '與 ${ins.name} 對話',
          kind: BtnKind.secondary,
          icon: Icons.forum_outlined,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MentorChatScreen(instructor: ins))),
        ),
        const SectionLabel('本週互動摘要'),
        Panel(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: '提問 / 回覆',
                      value: '${s.weeklyQuestionCount} / ${s.weeklyAnswerCount}',
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: '任務指派 / 完成',
                      value: '${s.weeklyAssigned} / ${s.weeklyCompleted}',
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, color: AppColors.line),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.ratedThisWeek
                          ? '本週已評分'
                          : '本週尚未評分　·　距週一重置剩 ${7 - appNow().weekday + 1} 天',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  AppButton(
                    label: s.ratedThisWeek ? '已評分' : '評分該週互動',
                    onPressed: s.ratedThisWeek
                        ? null
                        : () => _rateWeek(context, s),
                    kind: BtnKind.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 未評分時聲望無變動，不視為差評。
              Text(
                '每週最多評一次，且該週雙方要有互動才評得了。'
                '不評不算差評 —— 教官聲望目前 ${s.instructorReputation}，'
                '帶徒上限 ${s.apprenticeCap} 人。',
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),

        // 終止路徑：解除為單方面，恢復需雙方同意 —— 兩者刻意不對稱，
        // 避免一方反覆解除又拉回。
        if (s.mentorReleased) ...[
          const SectionLabel('師徒關係已解除', trailing: '3 天內可挽回'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '解除原因：${mentorReleaseReasonNames[s.mentorReleaseReason]}。'
                  '冷卻期剩 ${s.mentorCooldownLeft.inHours} 小時 —— '
                  '期間雙方都不能與別人建立師徒關係，未完成的任務已作廢。',
                  style: const TextStyle(fontSize: 12.5, height: 1.6),
                ),
                const SizedBox(height: 12),
                if (s.mentorRestorePending)
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: '拒絕恢復',
                          kind: BtnKind.secondary,
                          onPressed: () {
                            s.rejectRestore();
                            showToast(context, '已拒絕，3 天內可再次提出');
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          label: '同意恢復',
                          onPressed: () {
                            s.acceptRestore();
                            showToast(context, '師徒關係已恢復');
                          },
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: '提出恢復師徒關係',
                      kind: BtnKind.secondary,
                      onPressed: !s.canRestoreMentor
                          ? null
                          : () {
                              s.proposeRestore();
                              showToast(context, '已提出，等對方同意');
                            },
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (s.mentorDisclaimerNeeded) ...[
          const SectionLabel('師徒免責聲明', trailing: '僅首次建立關係時出現'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '教官是平台配對給你的一般使用者，不是持照專業人員。'
                  '平台展示他的聲望、專長與六維能力值，但不為他的指導內容擔保。'
                  '訓練請量力而為，身體不適請立即停止。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: '我已了解',
                    onPressed: () {
                      s.confirmMentorDisclaimer();
                      showToast(context, '已確認，現在可以提問了');
                    },
                    kind: BtnKind.primary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('未確認前不能提問，也不能完成師徒任務。',
                    style: TextStyle(
                        color: AppColors.textFaint, fontSize: 11, height: 1.4)),
              ],
            ),
          ),
        ],
        const SectionLabel('待完成的師徒任務'),
        for (final t in s.mentorTasks) _TaskCard(task: t),
        const SectionLabel('提問'),
        for (final q in s.questions) _QuestionCard(q: q),
        const SizedBox(height: 10),
        _AskBox(),
      ],
    );
  }
}

/// 學徒已評分該週互動 —— 幅度 −2／0／+4／+8／+12，直接連動教官聲望。
Future<void> _rateWeek(BuildContext context, AppState s) async {
  var stars = 4;
  final ok = await showAppDialog(
    context,
    title: '評這一週的互動',
    confirmLabel: '送出',
    content: StatefulBuilder(
      builder: (context, setInner) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('評的是這一整週，不是最近一次對話。摘要就在上面，看著紀錄評。',
              style: T.caption(), textAlign: TextAlign.center),
          const SizedBox(height: S.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () => setInner(() => stars = i),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      stars >= i ? Icons.star : Icons.star_border,
                      size: 30,
                      color: stars >= i ? AppColors.accent : AppColors.textFaint,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text('$stars 星', style: T.caption()),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  s.rateWeeklyInteraction(stars);
  showToast(context, '已評分，教官聲望 ${s.instructorReputation}');
}

/// 師徒關係已解除。**需經多次確認，避免誤觸**；任一方皆可單方面解除。
Future<void> _release(
    BuildContext context, AppState s, Instructor ins) async {
  final first = await showAppDialog(
    context,
    title: '解除與 ${ins.name} 的師徒關係？',
    message: '未完成的師徒任務會作廢，且解除後 3 天內雙方都不能與別人建立師徒關係。',
    confirmLabel: '繼續',
    destructive: true,
  );
  if (first != true || !context.mounted) return;
  final second = await showAppDialog(
    context,
    title: '再確認一次',
    message: '3 天內你們任一方都可以提出恢復，但恢復需要雙方同意。',
    confirmLabel: '確定解除',
    destructive: true,
  );
  if (second != true || !context.mounted) return;
  s.releaseMentor(MentorReleaseReason.byApprentice);
  showToast(context, '已解除，3 天內可挽回');
}

class _TaskCard extends StatelessWidget {
  final MentorTask task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(task.title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                if (task.state == MentorTaskState.voided)
                  // 師徒關係解除時，未完成的任務轉為已作廢（終止狀態）。
                  const Pill('已作廢', color: AppColors.textFaint)
                else if (task.state == MentorTaskState.claimed)
                  const Pill('已領取', color: AppColors.textFaint)
                else if (task.state == MentorTaskState.done)
                  GestureDetector(
                    onTap: () {
                      final r = s.claimMentorTask(task)!;
                      showToast(
                          context,
                          r.exp == 0
                              ? '本週獎勵已達上限，任務照樣算完成'
                              : '已領取 ${r.exp} EXP、${r.coins} 金幣');
                    },
                    child: const Pill('領取獎勵',
                        color: AppColors.accent, filled: true),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      if (!s.completeMentorTask(task)) {
                        showToast(context, s.completeBlockedReason);
                      }
                    },
                    child: const Pill('標記完成', color: AppColors.accent),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.detail,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.6, color: AppColors.textDim)),
            const SizedBox(height: 8),
            Text(
              '獎勵：經驗值 $kMentorTaskExp ＋ 金幣 $kMentorTaskCoin　·　'
              '本週已發 ${s.mentorRewardsThisWeek} / $kMentorTaskRewardWeeklyCap 次',
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
            // 學徒已評分該次師徒任務 → 教官聲望已變動。
            // 逐次問答不評分，尺度太敏感且多為兩端情緒樣本；改由任務評分承擔。
            if (task.state != MentorTaskState.assigned &&
                task.state != MentorTaskState.voided) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(task.rating == null ? '評這次任務：' : '你給了 ${task.rating} 星：',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textDim)),
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () {
                        s.rateMentorTask(task, i);
                        showToast(
                            context,
                            s.taskRatingsThisWeek > kMentorTaskRatingWeeklyCap
                                ? '已評分，本週計入聲望的次數已用完'
                                : '已評分，教官聲望 ${s.instructorReputation}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          (task.rating ?? 0) >= i
                              ? Icons.star
                              : Icons.star_border,
                          size: 18,
                          color: (task.rating ?? 0) >= i
                              ? AppColors.accent
                              : AppColors.textFaint,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final MentorQuestion q;
  const _QuestionCard({required this.q});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.help_outline, size: 15, color: AppColors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(q.text,
                        style: const TextStyle(fontSize: 13, height: 1.6)),
                  ),
                ],
              ),
              if (q.answer != null) ...[
                const Divider(height: 20, color: AppColors.line),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.forum_outlined,
                        size: 15, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(q.answer!,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.65,
                              color: AppColors.textDim)),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                const Pill('等待教官回答', color: AppColors.textFaint),
              ],
            ],
          ),
        ),
      );
}

class _AskBox extends StatefulWidget {
  @override
  State<_AskBox> createState() => _AskBoxState();
}

class _AskBoxState extends State<_AskBox> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: '向教官提問…',
              hintStyle:
                  const TextStyle(color: AppColors.textFaint, fontSize: 12.5),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: AppColors.line),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            if (s.askQuestion(ctrl.text)) {
              ctrl.clear();
            } else {
              showToast(context, s.askBlockedReason);
            }
          },
          icon: const Icon(Icons.send_rounded, color: AppColors.accent),
        ),
      ],
    );
  }
}
