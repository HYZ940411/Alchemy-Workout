import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/commerce.dart';
import '../../domain/community.dart';
import '../../domain/novice_wrapup.dart';
import '../../domain/plan_duration.dart';
import '../../domain/platform_plan.dart';
import '../../domain/rewards.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../ai/ai_adjust_screen.dart';
import '../workout_screen.dart';
import 'exercise_detail_screen.dart';
import 'rate_experience_screen.dart';

/// 訓練計畫詳情 —— 〈Read Model：課表選擇頁〉每份課表的欄位，
/// 加上清單卡放不下的「課表內容」本身（逐動作 × 組數 × 目標重量與次數）。
///
/// 未解鎖的進階計畫**一併呈現，不隱藏**：未解鎖計畫是三種解鎖方式的唯一曝光點，
/// 使用者若看不到有哪些計畫可解，金幣購買與會員解鎖兩條路徑等同不存在。
class PlanDetailScreen extends StatelessWidget {
  final WorkoutPlan plan;
  const PlanDetailScreen({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // 三種解鎖方式為 OR 關係，任一成立即解鎖。
    final locked = !s.planUnlocked(plan);
    final srcFactor = planSourceFactor(plan.source);

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(
        backgroundColor: C.bgPage,
        surfaceTintColor: Colors.transparent,
        title: Text(plan.name, style: T.h3()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.md,
          S.base,
          S.scrollBottom,
        ),
        children: [
          Wrap(
            spacing: S.sm,
            runSpacing: S.sm,
            children: [
              Pill(planSourceNames[plan.source]!, color: AppColors.textDim),
              Pill(
                '${plan.exercises.length} 動作 · ${plan.totalSets} 組',
                color: AppColors.textDim,
              ),
              Pill('器材：${plan.equipmentTier}', color: AppColors.textDim),
              for (final e in plan.suitableExperience)
                Pill(e, color: AppColors.textDim),
              for (final g in plan.suitableGoals)
                Pill(g, color: AppColors.accentSoft),
              if (srcFactor != null)
                Pill(
                  '排行係數 ${(srcFactor * 100).round()}%',
                  color: AppColors.accentSoft,
                )
              else
                const Pill('不計入排行榜', color: AppColors.textFaint),
            ],
          ),
          // 同上：依訓練歷史推導。
          if (s.lastTrainedOf(plan) case final at?) ...[
            const SizedBox(height: S.md),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: StatField(
                      label: '上次訓練',
                      value: _ago(at),
                    ),
                  ),
                  // **依訓練歷史推導。** 2026-09-26 起結算時會把
                  // 「這場做了計畫的幾成」存進去；在那之前的場次沒有這個
                  // 數字，顯示「—」—— 那是誠實的，我們真的不知道。
                  Expanded(
                    child: StatField(
                      label: '上次完成度',
                      value: s.lastCompletionOf(plan) == null
                          ? '—'
                          : '${(s.lastCompletionOf(plan)! * 100).round()}',
                      unit: s.lastCompletionOf(plan) == null ? null : '%',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (plan.hasOptimizationSuggestion) ...[
            const SizedBox(height: S.md),
            _OptimizationCard(),
          ],
          if (locked) ...[
            const SizedBox(height: S.md),
            _UnlockCard(plan: plan, userRank: s.rank, isMember: s.isMember),
          ] else if (s.planMemberOnly(plan)) ...[
            // 靠會員權益解得開、但不是永久取得的那一批。計畫可以用了，
            // 購買入口卻不能跟著消失 —— 權益失效當天才發現買不到就太晚了。
            const SizedBox(height: S.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_outlined,
                        size: Sz.iconDense,
                        color: C.statusWarning,
                      ),
                      const SizedBox(width: S.sm),
                      Text('會員權益解鎖中', style: T.h3()),
                    ],
                  ),
                  const SizedBox(height: S.md),
                  if (plan.unlockCoins != null) _BuyButton(plan: plan),
                ],
              ),
            ),
          ],
          if (plan.disclaimer != null) ...[
            const SizedBox(height: S.md),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: Sz.iconDense,
                    color: C.statusWarning,
                  ),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(
                      plan.disclaimer!,
                      style: T.body(color: C.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 課表的說明性內容。**只有《健身計劃.csv》那 27 份有** ——
          // 七份示範用假課表沒有這些欄位，所以整段是條件呈現，
          // 不是每份課表都硬擠出一塊空白。
          // **內容全空的規格不呈現這一整段。**
          //
          // 2026-09-29 把四份官方課表從 `kPlans` 搬上雲之後，它們有了規格
          // （後台才改得動），但**沒有那六段說明性內容** —— 它們從來沒有過，
          // 而那不是編得出來的東西（尤其「學理依據」，見 `kLegacyPlanSpecs`）。
          //
          // 不加這個判斷的話，畫面會出現一張空白卡片加一個空的「依據」欄，
          // 那比沒有更糟：它看起來像壞掉，而不是像「還沒寫」。
          if (s.planSpecById[plan.id] case final spec? when _hasProse(spec)) ...[
            const SizedBox(height: S.lg),
            const SectionTitle('這份課表在做什麼'),
            if (spec.intro.trim().isNotEmpty)
              AppCard(child: Text(spec.intro, style: T.body())),
            for (final (title, text) in [
              ('怎麼練', spec.howTo),
              ('負荷大小', spec.load),
              ('訓練效果', spec.effect),
              ('技術重點', spec.technique),
            ])
              if (text.trim().isNotEmpty) ...[
                const SizedBox(height: S.md),
                _Section(title: title, text: text),
              ],
            const SizedBox(height: S.md),
            // 依據要單獨呈現，不塞在段落裡 ——
            // 一份說得出依據的課表與一份憑空編的，對使用者是兩件事。
            AppCard(
              color: C.bgPage,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.menu_book_outlined,
                        size: Sz.iconDense,
                        color: C.textSecondary,
                      ),
                      const SizedBox(width: S.sm),
                      Text('依據', style: T.caption(color: C.textSecondary)),
                      const Spacer(),
                      Pill(spec.level),
                    ],
                  ),
                  const SizedBox(height: S.sm),
                  Text(spec.reference, style: T.caption()),
                  const SizedBox(height: S.xs),
                  // 原本顯示 CSV 那一欄的原文，格式各寫各的，還有三筆
                  // 在產生時被引號截斷（`30 min (含熱身5'`）。
                  // 改用算出來的，與課表清單上那顆標籤同一個來源。
                  if (s.estimatedDurationOf(plan) case final d?)
                    Text('預估時長：${planDurationLabel(d)}（不含暖身與收操）',
                        style: T.caption()),
                ],
              ),
            ),
          ],
          const SizedBox(height: S.lg),
          const SectionTitle('課表內容'),
          if (plan.exercises.isEmpty)
            const AppCard(
              child: EmptyState(
                icon: Icons.playlist_add_rounded,
                title: '空白課表',
                message:
                    '沒有預先排好的內容。開始之後於訓練頁逐一加入動作，'
                    '總計畫組數自加入第一個動作起成立。',
              ),
            )
          else
            for (final pe in plan.exercises) ...[
              _PlanExerciseCard(pe: pe),
              const SizedBox(height: S.md),
            ],
          const SizedBox(height: S.xs),
          _RatingSection(plan: plan),
          if (!locked) ...[
            if (plan.exercises.isNotEmpty) ...[
              AppButton(
                label: 'AI 訓練前調整',
                kind: BtnKind.secondary,
                icon: Icons.auto_awesome_outlined,
                onPressed: () {
                  // 訓練前調整改的是**本次訓練課表快照**，故先選定課表把
                  // 快照產生出來。重複選同一份不會重建，調整不會被洗掉。
                  s.startWorkout(plan);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AiAdjustScreen(source: AiSource.beforeTraining),
                    ),
                  );
                },
              ),
              const SizedBox(height: S.md),
            ],
            AppButton(
              // 空白課表恆為已解鎖，且必須呈現 —— 自由訓練以它為入口。
              label: plan.exercises.isEmpty ? '開始自由訓練' : '開始訓練',
              onPressed: () {
                s.startWorkout(plan);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const WorkoutScreen()),
                );
              },
            ),
          ],
          const SizedBox(height: S.md),
        ],
      ),
    );
  }

  /// 這份規格帶不帶得出課表詳情頁要的說明性內容。
  ///
  /// 只看那六段，不看依據 —— 依據單獨呈現，也單獨判斷。
  static bool _hasProse(PlatformPlanSpec s) =>
      s.intro.trim().isNotEmpty ||
      s.howTo.trim().isNotEmpty ||
      s.load.trim().isNotEmpty ||
      s.effect.trim().isNotEmpty ||
      s.technique.trim().isNotEmpty ||
      s.reference.trim().isNotEmpty;

  static String _ago(DateTime d) {
    final n = appNow().difference(d).inDays;
    return n == 0 ? '今天' : '$n 天前';
  }
}

/// 我對這份課表的評分。
///
/// **這一段存在的理由是「評完就不見了」。** 結算頁那張評分卡的條件是
/// 「還沒評過才顯示」，所以評完之後整個 App 沒有任何地方看得到自己評了
/// 什麼、更沒有地方改 —— 而 `RateExperienceScreen` 從第一天起就支援
/// 讀回既有評分並修改，缺的只是一個入口（同「經驗值只有刪帳號頁看得到」）。
///
/// 三種狀態：
/// - **評過** → 顯示星等與評語，可以改
/// - **沒評過、但練過這份** → 給一個補評的入口
/// - **沒評過也沒練過** → 什麼都不顯示
///
/// 最後一條是刻意的：沒做過的課表評不出「做起來如何」，而這份資料的
/// 唯一讀者（管理員的評分彙總）要回答的是「哪一份課表該改」。
/// 讓人評沒做過的課表，等於往那張表裡倒雜訊。
///
/// **練過與否以課表名稱比對** —— `HistoryEntry` 存的是 `planName` 而非
/// 課表 ID。同名的自訂課表會被算成練過，那是可接受的誤差（方向是讓人
/// 多評得到，而不是少）；真要修得先給訓練歷史加上課表 ID。
class _RatingSection extends StatelessWidget {
  final WorkoutPlan plan;
  const _RatingSection({required this.plan});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final mine = s.ratingFor(RatingTarget.trainingPlan, plan.id);
    final trained = s.history.any((h) => h.planName == plan.name);
    if (mine == null && !trained) return const SizedBox.shrink();

    void open() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RateExperienceScreen(
              target: RatingTarget.trainingPlan,
              targetId: plan.id,
              targetName: plan.name,
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: S.lg),
        const SectionTitle('我的評分'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (mine == null)
                Text('你練過這份課表，但還沒評分過。',
                    style: T.body(color: C.textSecondary))
              else ...[
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Icon(
                        i <= mine.stars ? Icons.star : Icons.star_border,
                        size: Sz.iconDense,
                        color: C.accentDeep,
                      ),
                    const SizedBox(width: S.sm),
                    Text('${mine.stars} 星', style: T.caption()),
                  ],
                ),
                if (mine.feedback case final f? when f.trim().isNotEmpty) ...[
                  const SizedBox(height: S.sm),
                  Text(f, style: T.body()),
                ],
              ],
              const SizedBox(height: S.md),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: mine == null ? '評分這份課表' : '修改評分',
                  kind: BtnKind.secondary,
                  onPressed: open,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 三種解鎖方式的當前狀態。金幣價格為空值者不呈現該項。
class _UnlockCard extends StatelessWidget {
  final WorkoutPlan plan;
  final int userRank;
  final bool isMember;
  const _UnlockCard({
    required this.plan,
    required this.userRank,
    required this.isMember,
  });

  @override
  Widget build(BuildContext context) {
    final gap = plan.requiredRank! - userRank;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: Sz.iconDense,
                color: C.textSecondary,
              ),
              const SizedBox(width: S.sm),
              Text('尚未解鎖', style: T.h3()),
            ],
          ),
          const SizedBox(height: S.md),
          _Way(
            icon: Icons.trending_up_rounded,
            title: '階級達標',
            detail: '尚差 $gap 階（目前 $userRank 階，需 ${plan.requiredRank} 階）',
          ),
          if (plan.unlockCoins != null)
            _Way(
              icon: Icons.paid_outlined,
              title: '金幣提前購買',
              detail: '${plan.unlockCoins} 金幣．永久取得',
            ),
          if (plan.memberUnlockable)
            _Way(
              icon: Icons.workspace_premium_outlined,
              title: '會員身分',
              // 會員解鎖為續約生效，權益失效即回退 —— 說「可直接使用」
              // 會讓人以為和另外兩條一樣是永久的。
              detail: isMember ? '你是會員，權益生效中可用' : '會員可用',
            ),
          if (plan.unlockCoins != null) ...[
            const SizedBox(height: S.xs),
            _BuyButton(plan: plan),
          ],
        ],
      ),
    );
  }
}

/// 「金幣提前購買」不能只是一行字 —— 它是三條解鎖路徑中唯一能當場走完的一條。
class _BuyButton extends StatelessWidget {
  final WorkoutPlan plan;
  const _BuyButton({required this.plan});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final price = plan.unlockCoins!;
    final short = price - (s.coins >= price ? price : s.coins);
    final cash = cashForShortfall(short);
    // 僅以會員身分解鎖者仍可購買 —— 用途正是在權益失效前轉為永久取得。
    final memberOnly = s.planMemberOnly(plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (memberOnly) ...[
          Text(
            '你現在是靠會員權益使用這份計畫，權益失效就會鎖回去。'
            '買下來即為永久取得。',
            style: T.caption(),
          ),
          const SizedBox(height: S.sm),
        ],
        // 補差額寫在按鈕外 —— 按鈕標籤塞得下的長度有限，
        // 塞進去在 375 寬就會爆版。
        if (cash > 0) ...[
          Text(
            '金幣餘額 ${s.coins}，不足 $short 金幣，將以現金補 $cash 元。',
            style: T.caption(),
          ),
          const SizedBox(height: S.sm),
        ],
        AppButton(
          label: '以 $price 金幣購買解鎖',
          kind: BtnKind.secondary,
          icon: Icons.paid_outlined,
          onPressed: () async {
            final ok = await showAppDialog(
              context,
              title: '購買「${plan.name}」？',
              message: cash > 0
                  ? '金幣餘額 ${s.coins}，不足 $short 金幣，'
                        '將以現金補差額 $cash 元（1 元 ＝ $kCoinsPerNtd 金幣）。'
                        '永久取得，不因會員權益失效而回退。'
                  : '將扣除 $price 金幣，餘額 ${s.coins} → ${s.coins - price}。'
                        '永久取得，不因會員權益失效而回退。',
              confirmLabel: '確認購買',
            );
            if (ok != true || !context.mounted) return;
            final fail = s.purchasePlan(plan);
            if (!context.mounted) return;
            showToast(
              context,
              fail == null ? '已解鎖「${plan.name}」，永久取得' : '購買失敗',
            );
          },
        ),
      ],
    );
  }
}

class _Way extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _Way({required this.icon, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: S.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: Sz.iconDense, color: C.textSecondary),
        const SizedBox(width: S.sm),
        // 解鎖說明可能很長（「尚差 18 階（目前 37 階，需 55 階）」），
        // 與標題同一行會爆版 —— 改為上下兩行。
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.body()),
              const SizedBox(height: 2),
              Text(detail, style: T.caption()),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OptimizationCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Pill('新的優化建議', color: AppColors.cool),
              const SizedBox(height: S.sm),
              // 2026-09-28 之前這句話是**假的** —— 按下「查看」之後畫面
              // 反過來問使用者要調哪個方向，什麼都還沒調。
              // 現在系統真的會先算好（`AppState.aiAutoPropose`）。
              Text('AI 會依你的紀錄判斷該怎麼調，點「查看」看建議。'
                  '常駐標記，未處理前一直存在。', style: T.caption()),
            ],
          ),
        ),
        const SizedBox(width: S.md),
        AppButton(
          label: '查看',
          kind: BtnKind.secondary,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const AiAdjustScreen(source: AiSource.autoOptimize),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PlanExerciseCard extends StatelessWidget {
  final PlanExercise pe;
  const _PlanExerciseCard({required this.pe});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.card),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExerciseDetailScreen(exercise: pe.exercise),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(S.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(pe.exercise.name, style: T.h3())),
                    Text('休息 ${s.restSecondsFor(pe)} 秒', style: T.caption()),
                    const SizedBox(width: S.xs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
                if (pe.replacedFrom != null) ...[
                  const SizedBox(height: S.xs),
                  Row(
                    children: [
                      Text('AI 已替換：', style: T.caption()),
                      // §8.20：刪除線文字只出現在已替換動作檢視，不抽成共用元件。
                      Text(
                        pe.replacedFrom!.name,
                        style: T
                            .caption(color: C.textDisabled)
                            .copyWith(decoration: TextDecoration.lineThrough),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: S.sm),
                Text(pe.exercise.equipment, style: T.caption()),
                const SizedBox(height: S.md),
                Wrap(
                  spacing: S.sm,
                  runSpacing: S.sm,
                  children: [
                    for (final (i, set) in pe.planned.indexed)
                      _SetChip(index: i + 1, set: set, timed: pe.isTimed),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetChip extends StatelessWidget {
  final int index;
  final PlannedSet set;

  /// 這一組以秒計還是以次計。
  ///
  /// **原本是看「目標重量是 0」來猜的** —— 而平台課表的目標重量一律是 0
  /// （以 RPE 開處方），徒手動作也是 0。於是「引體向上 3 組 × 8 下」
  /// 被顯示成「8 秒」、「棒式 40 秒」與「深蹲 12 下」長得一模一樣。
  /// 單位現在由 `PlanExercise.unit` 一路帶進來，不用猜。
  final bool timed;
  const _SetChip({required this.index, required this.set, required this.timed});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: 6),
    decoration: BoxDecoration(
      color: C.bgPage,
      borderRadius: BorderRadius.circular(R.child),
    ),
    child: Text(_label(), style: T.caption(color: C.textPrimary)),
  );

  String _label() {
    if (timed) return '第 $index 組　${set.targetReps} 秒';
    // 目標重量 0 的意思是「不指定公斤數」，不是「零公斤」——
    // 寫成「0 kg × 12」會讓人以為那是個要照做的數字。
    if (set.targetWeight == 0) return '第 $index 組　${set.targetReps} 下';
    return '第 $index 組　${_kg(set.targetWeight)} kg × ${set.targetReps}';
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// 課表說明的一節。長文字要能收合 —— 使用說明平均 295 字，
/// 全部展開的話「課表內容」會被推到很下面，而那才是要按開始的地方。
class _Section extends StatefulWidget {
  final String title;
  final String text;
  const _Section({required this.title, required this.text});

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    // 短的就不必收合 —— 一個只有兩行的段落配一顆「展開」很蠢。
    final long = widget.text.length > 90;
    return AppCard(
      onTap: long ? () => setState(() => open = !open) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(widget.title, style: T.body(weight: FontWeight.w600)),
              const Spacer(),
              if (long)
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: Sz.iconDense,
                  color: C.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: S.sm),
          Text(
            widget.text,
            style: T.caption(),
            maxLines: (long && !open) ? 3 : null,
            overflow: (long && !open) ? TextOverflow.ellipsis : null,
          ),
        ],
      ),
    );
  }
}
