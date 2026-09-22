import '../../domain/clock.dart';
import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../design/tokens.dart';
import '../../domain/registration.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'choice_grid.dart';
import 'launch_screen.dart';
import 'login_screen.dart';
import 'phone_verify_screen.dart';
import 'plan_recommend_screen.dart';

/// 註冊流程
///
/// 啟動頁 → 入口二選一（手機簡訊驗證 / 第三方登入授權）→ 同意服務條款
/// → 建立帳號 → 10 項個人資料逐欄填寫 → 完成註冊 → 發放註冊獎勵
/// → 訓練計畫已推薦。
/// 任務型頁面：底部導覽列隱藏（§8.4）。
class SignUpScreen extends StatefulWidget {
  /// 走完之後要做什麼。空值代表這是被推上來的示範，走完就 pop 回去。
  ///
  /// 首次啟動時它是 App 的根畫面，**沒有東西可以 pop** ——
  /// 由呼叫端傳一個回呼進來，切換到主畫面。
  final VoidCallback? onFinish;

  /// 這是真正的第一次註冊，不是從「流程示範」點進來看的。
  ///
  /// 差別在完成前那一道確認：示範時要問「這會覆蓋你現在的帳號」，
  /// 第一次註冊時沒有東西可覆蓋，問了只會讓人以為自己要弄壞什麼。
  final bool firstRun;

  /// 這台裝置登入過 —— 登入頁講「歡迎回來」而不是「建立帳號」。
  /// 由 [AuthGate] 從裝置層的記事本讀出來。
  final bool returning;

  /// 已經在 App 外面授權過的電子郵件（目前只有 Google 登入會給）。
  ///
  /// 有值代表「入口這一關已經過了」——[AuthGate] 已經收到登入事件，
  /// 才會把這個畫面畫出來。不帶著它走的話，使用者剛授權完成，
  /// 畫面卻還停在要他選登入方式的那一頁。
  final String? authorizedEmail;

  /// 第三方登入帶回來的名字，**預帶於暱稱欄、可改**。
  ///
  /// 不直接拿來當顯示名稱：Google 帳號的姓名多為實名，直接用等於替使用者
  /// 做了一次不可逆的公開（見〈註冊流程〉2026-09-16 的裁決）。
  final String? suggestedName;

  /// 帳號。空值代表這次沒接後端，第三方登入按鈕走假路徑。
  final AuthService? auth;

  const SignUpScreen({
    super.key,
    this.onFinish,
    this.firstRun = false,
    this.authorizedEmail,
    this.suggestedName,
    this.auth,
    this.returning = false,
  });
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late SignUpDraft d;

  /// -4 啟動頁、-3 登入頁、-2 手機驗證、-1 條款、
  /// 0..[SignUpDraft.total]-1 十個欄位、
  /// [SignUpDraft.total] 完成註冊、其後一步為訓練計畫推薦。
  int step = -4;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    d = AppScope.of(context).signUpDraft;

    // 外部已授權：入口這一關由 Firebase 過了，草稿要跟上。
    // 放在續填判斷之前，這樣 `entryDone` 才會是真，接著就從條款頁開始。
    final authorized = widget.authorizedEmail;
    if (authorized != null && !d.entryDone) {
      d.entry = SignUpEntry.thirdParty;
      d.email = authorized;
      step = -1; // 條款頁
    }

    // 續填：自未完成的欄位開始，已填資料不清空。
    // 已走過入口與條款者不必再看啟動頁與登入頁。
    if (d.entryDone && d.termsAgreed) {
      step = d.complete ? SignUpDraft.total : d.resumeIndex;
    }
  }

  Future<void> _confirmLeave() async {
    // 10 項未填完即離開 → 註冊資料填寫已中斷
    if (step >= 0 && step < SignUpDraft.total && !d.complete) {
      final leave = await showAppDialog(
        context,
        title: '要先離開嗎？',
        message:
            '已填的 ${d.filledCount} / ${SignUpDraft.total} 項會保留，'
            '下次可以從沒填完的地方接著填。',
        confirmLabel: '離開',
        cancelLabel: '繼續填',
        destructive: true,
      );
      if (leave != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(
          title: Text(switch (step) {
            -4 => '',
            -3 => '建立帳號',
            -2 => '驗證手機號碼',
            -1 => '服務條款',
            SignUpDraft.total => '完成註冊',
            const (SignUpDraft.total + 1) => '訓練計畫推薦',
            _ => '個人資料',
          }),
          leading: switch (step) {
            // 啟動頁沒有可返回的地方。
            -4 => null,
            // 手機驗證頁退回去改號碼；條款頁退回入口重選註冊方式。
            -2 => _back(() => step = -3),
            -1 => _back(() => step = d.entry == SignUpEntry.phone ? -2 : -3),
            // 問卷的「上一步」在底部按鈕列；頂部的鍵一律是離開。
            _ => IconButton(
              onPressed: _confirmLeave,
              icon: const Icon(Icons.close, size: Sz.iconDense),
            ),
          },
        ),
        body: Column(
          children: [
            // 註冊問卷的進度條變體（§8.7）
            if (step >= 0 && step < SignUpDraft.total)
              Container(
                color: C.bgSurface,
                padding: const EdgeInsets.fromLTRB(
                  S.base,
                  S.base,
                  S.base,
                  S.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                        child: BareProgress(
                            value: (step + 1) / SignUpDraft.total)),
                    const SizedBox(width: S.md),
                    // 文字寬度固定，避免數字變動時進度條長度跳動
                    SizedBox(
                      width: 56,
                      child: Text(
                        '第 ${step + 1}／${SignUpDraft.total}',
                        style: T.caption(),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _body(s)),
          ],
        ),
      ),
    );
  }

  Widget _back(VoidCallback go) => IconButton(
    onPressed: () => setState(go),
    icon: const Icon(Icons.arrow_back, size: Sz.iconDense),
  );

  Widget _body(AppState s) {
    switch (step) {
      case -4:
        return LaunchScreen(
          onDone: () {
            if (mounted) setState(() => step = -3);
          },
        );
      case -3:
        return LoginPane(
          returning: widget.returning,
          onPhone: (phone) => setState(() {
            d.entry = SignUpEntry.phone;
            d.phone = phone;
            step = -2;
          }),
          onThirdParty: (email) => setState(() {
            d.entry = SignUpEntry.thirdParty;
            // 第三方登入者於授權時帶入電子郵件。
            d.email = email;
            step = -1;
          }),
          // 接了帳號才有真的 Google 授權；沒接就讓按鈕退回上面那條假路徑，
          // 流程示範與既有測試的行為完全不變。
          //
          // 授權成功後**不在這裡換頁**：[AuthGate] 收到登入事件會重建整個
          // 子樹，並把 email 當作 authorizedEmail 傳回來，畫面自然會落在條款頁。
          onGoogle: widget.auth?.signInWithGoogle,
        );
      case -2:
        return PhoneVerifyPane(
          phone: d.phone ?? '',
          onVerified: () => setState(() {
            d.phoneVerified = true;
            step = -1;
          }),
        );
      case -1:
        return _Terms(
          draft: d,
          onAgree: () => setState(() {
            d.termsAgreed = true;
            step = 0;
          }),
        );
      case SignUpDraft.total:
        return _Done(
          draft: d,
          state: s,
          firstRun: widget.firstRun,
          onNext: () => setState(() => step = SignUpDraft.total + 1),
        );
      case const (SignUpDraft.total + 1):
        return PlanRecommendPane(
          draft: d,
          onStart: () {
            final done = widget.onFinish;
            if (done != null) {
              done();
            } else {
              Navigator.of(context).pop();
            }
          },
        );
      default:
        // 每一欄各自一個 State —— 否則切換步驟時 Flutter 重用同一個 State，
        // initState 的預設值只會帶到第一欄。
        return _Question(
          key: ValueKey(step),
          draft: d,
          index: step,
          suggestedName: widget.suggestedName,
          onNext: () => setState(() => step++),
          onBack: step == 0 ? null : () => setState(() => step--),
        );
    }
  }
}

class _Terms extends StatefulWidget {
  final SignUpDraft draft;
  final VoidCallback onAgree;
  const _Terms({required this.draft, required this.onAgree});
  @override
  State<_Terms> createState() => _TermsState();
}

class _TermsState extends State<_Terms> {
  bool checked = false;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(S.base),
          children: [
            Text('服務條款與隱私權政策　${widget.draft.termsVersion}',
                style: T.h3()),
            const SizedBox(height: S.md),
            // 逐節一張卡，而不是一整塊文字牆 —— 這一頁有五節近兩千字，
            // 擠成一段沒有人會讀，而「已閱讀並同意」那個勾選就成了純粹的形式。
            for (final (heading, body) in kTermsSections) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (heading.isNotEmpty) ...[
                      Text(heading, style: T.body(weight: FontWeight.w700)),
                      const SizedBox(height: S.sm),
                    ],
                    Text(body, style: T.body()),
                  ],
                ),
              ),
              const SizedBox(height: S.md),
            ],
          ],
        ),
      ),
      _Footer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AppSwitch(
                  value: checked,
                  onChanged: (v) => setState(() => checked = v),
                ),
                const SizedBox(width: S.md),
                Expanded(child: Text('我已閱讀並同意服務條款', style: T.body())),
              ],
            ),
            const SizedBox(height: S.md),
            AppButton(
              label: '同意並建立帳號',
              onPressed: checked ? widget.onAgree : null,
            ),
          ],
        ),
      ),
    ],
  );
}

class _Footer extends StatelessWidget {
  final Widget child;
  const _Footer({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: C.bgSurface,
      border: Border(top: BorderSide(color: C.lineDivider)),
    ),
    padding: EdgeInsets.fromLTRB(
      S.base,
      S.md,
      S.base,
      MediaQuery.of(context).padding.bottom + S.base,
    ),
    child: child,
  );
}

class _Question extends StatefulWidget {
  final SignUpDraft draft;
  final int index;
  final String? suggestedName;
  final VoidCallback onNext;

  /// 回上一題。第一題沒有上一題，故為空值。
  final VoidCallback? onBack;
  const _Question({
    super.key,
    required this.draft,
    required this.index,
    required this.onNext,
    this.suggestedName,
    this.onBack,
  });
  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  SignUpDraft get d => widget.draft;

  /// 暱稱輸入框。只有第 0 題用得到，但 State 是一題一個（見 ValueKey），
  /// 所以不必為它另開一個 widget。
  final _nick = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 數值欄位一進畫面就帶入預設值 ——
    // 否則畫面上看得到數字，「下一步」卻是停用的。
    switch (widget.index) {
      case 0:
        // 暱稱不給預設值：預設值會被整批接受，於是又回到「全部叫你」。
        // 但第三方登入帶回來的名字**預帶於輸入框**，可改 ——
        // 直接拿來當顯示名稱等於替使用者做了一次不可逆的公開。
        _nick.text = d.nickname ?? widget.suggestedName ?? '';
      case 1:
        d.heightCm ??= 170;
      case 2:
        d.weightKg ??= 65;
      case 7:
        d.daysPerWeek ??= 3;
    }
  }

  @override
  void dispose() {
    // 離開這一題時一律寫回草稿，包含**從頂部的關閉鍵中途離開** ——
    // 規則是「已填資料不清空」，只在「下一步」寫的話，
    // 打完名字就按離開的人回來會發現白打了。
    _commit();
    _nick.dispose();
    super.dispose();
  }

  static const _titles = [
    '要怎麼稱呼你？',
    '你的身高？',
    '你的體重？',
    '你的性別？',
    '你的生日？',
    '你的健身目標？',
    '你的健身經驗？',
    '每週想練幾天？',
    '每次想練多久？',
    '你有哪些器材？',
  ];

  bool get _canNext => switch (widget.index) {
    0 => isValidNickname(_nick.text),
    1 => d.heightCm != null,
    2 => d.weightKg != null,
    3 => d.gender != null,
    4 => d.birthday != null && d.ageValid,
    5 => d.commonGoal != null,
    6 => d.experience != null,
    7 => d.daysPerWeek != null,
    8 => d.duration != null,
    _ => d.equipment.isNotEmpty,
  };

  /// 離開這一題時才寫進草稿 —— 逐字寫的話，中途清空會把已填的抹掉。
  void _commit() {
    if (widget.index == 0) d.nickname = _nick.text.trim();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(S.base),
          children: [
            Text(_titles[widget.index], style: T.h2()),
            const SizedBox(height: S.lg),
            ..._fields(),
          ],
        ),
      ),
      _Footer(
        // 第一題沒有上一題 —— 那時的「返回」是離開註冊，由頂部的關閉鍵承擔。
        child: widget.onBack == null
            ? AppButton(
                label: _isLast ? '完成' : '下一步',
                onPressed: _canNext ? _next : null,
              )
            : ButtonRow(
                left: AppButton(
                  label: '上一步',
                  kind: BtnKind.secondary,
                  onPressed: () {
                    _commit();
                    widget.onBack!();
                  },
                ),
                right: AppButton(
                  label: _isLast ? '完成' : '下一步',
                  onPressed: _canNext ? _next : null,
                ),
              ),
      ),
    ],
  );

  bool get _isLast => widget.index == SignUpDraft.total - 1;

  void _next() {
    _commit();
    widget.onNext();
  }

  /// 各值域的示意圖示。鍵為值域字串本身 ——
  /// 值域由後台維護，查不到時退回中性圖示，不讓畫面開天窗。
  static const _icons = <String, IconData>{
    // 性別
    '男': Icons.male_rounded,
    '女': Icons.female_rounded,
    // 常見目標
    '增肌': Icons.fitness_center_rounded,
    '減重': Icons.monitor_weight_outlined,
    '培養運動習慣': Icons.event_repeat_rounded,
    '提升體能': Icons.bolt_rounded,
    // 動機
    '健康陪伴家人': Icons.favorite_outline_rounded,
    '堅持夢想': Icons.flag_outlined,
    '自信外型': Icons.auto_awesome_outlined,
    '紓壓': Icons.spa_outlined,
    // 健身經驗
    '新手（未滿 6 個月）': Icons.eco_outlined,
    '中階（6 個月–2 年）': Icons.trending_up_rounded,
    '進階（2 年以上）': Icons.workspace_premium_outlined,
    // 每次時長
    '30 分鐘以下': Icons.timer_outlined,
    '30–60 分鐘': Icons.schedule_rounded,
    '60–90 分鐘': Icons.hourglass_bottom_rounded,
    '90 分鐘以上': Icons.all_inclusive_rounded,
    // 器材
    '健身房（全器材）': Icons.fitness_center_rounded,
    '居家器材（彈力繩、小啞鈴等）': Icons.home_outlined,
    '徒手': Icons.accessibility_new_rounded,
  };

  /// 單選欄位的「已選集合」——沒選就是空集合。
  static Set<String> _one(String? v) => v == null ? const {} : {v};

  Widget _grid(
    List<String> values,
    Set<String> selected,
    ValueChanged<String> onTap, {
    double tileHeight = 112,
  }) => ChoiceGrid(
    options: [
      for (final v in values)
        ChoiceOption.split(v, _icons[v] ?? Icons.circle_outlined),
    ],
    selected: selected,
    onTap: onTap,
    tileHeight: tileHeight,
  );

  List<Widget> _fields() {
    switch (widget.index) {
      case 0:
        return [
          // 樣式沿用登入頁的手機號碼欄，那是這個流程裡唯一的另一個輸入框。
          TextField(
            controller: _nick,
            autofocus: true,
            maxLength: kNicknameMaxLength,
            textInputAction: TextInputAction.done,
            style: T.body(),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_canNext) _next();
            },
            decoration: InputDecoration(
              hintText: '例如：阿昶',
              hintStyle: T.body(color: C.textDisabled),
              counterText: '',
              filled: true,
              fillColor: C.bgSurface,
              contentPadding: const EdgeInsets.all(S.base),
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
                borderSide: const BorderSide(color: C.actionOutline, width: 2),
              ),
            ),
          ),
          const SizedBox(height: S.sm),
          Text(
            '社群動態、隊伍成員、私訊、排行榜看到的都是這個名字。'
            '最多 $kNicknameMaxLength 個字，之後可以在設定裡改。',
            style: T.caption(),
          ),
        ];
      case 1:
        return [
          _NumberStepper(
            value: d.heightCm ?? 170,
            unit: 'cm',
            min: 50,
            max: 250,
            onChanged: (v) => setState(() => d.heightCm = v),
          ),
        ];
      case 2:
        return [
          _NumberStepper(
            value: d.weightKg ?? 65,
            unit: 'kg',
            min: 20,
            max: 300,
            onChanged: (v) => setState(() => d.weightKg = v),
          ),
        ];
      case 3:
        // 只有兩個選項，格子放大一點才不會顯得空。
        return [
          _grid(
            const ['男', '女'],
            _one(d.gender),
            (v) => setState(() => d.gender = v),
            tileHeight: 140,
          ),
        ];
      case 4:
        return [
          _BirthdayPicker(
            value: d.birthday,
            onChanged: (v) => setState(() => d.birthday = v),
          ),
          if (d.birthday != null && !d.ageValid) ...[
            const SizedBox(height: S.sm),
            Text('須滿 $kMinAge 歲才能註冊。', style: T.caption(color: C.statusError)),
          ],
        ];
      case 5:
        return [
          Text('常見目標（必填，1 項）', style: T.caption()),
          const SizedBox(height: S.sm),
          _grid(
            kCommonGoals,
            _one(d.commonGoal),
            (v) => setState(() => d.commonGoal = v),
          ),
          const SizedBox(height: S.lg),
          Text('動機（選填，最多 1 項）', style: T.caption()),
          const SizedBox(height: S.sm),
          // 再點一次可取消 —— 它是選填的，沒有「選了就回不去」的道理。
          _grid(
            kMotiveGoals,
            _one(d.motiveGoal),
            (v) => setState(() => d.motiveGoal = d.motiveGoal == v ? null : v),
          ),
        ];
      case 6:
        return [
          _grid(
            kExperience,
            _one(d.experience),
            (v) => setState(() => d.experience = v),
          ),
        ];
      case 7:
        return [
          Text('每週想練幾天', style: T.caption()),
          const SizedBox(height: S.sm),
          // 一排 1–7：步進器要按六次才到得了 7。
          ChipRow(
            labels: const ['1', '2', '3', '4', '5', '6', '7'],
            selected: d.daysPerWeek?.toString(),
            onTap: (i) => setState(() => d.daysPerWeek = i + 1),
          ),
        ];
      case 8:
        return [
          _grid(
            kDurations,
            _one(d.duration),
            (v) => setState(() => d.duration = v),
          ),
        ];
      default:
        return [
          Text('可複選，無數量上限', style: T.caption()),
          const SizedBox(height: S.sm),
          _grid(
            kEquipmentTiers,
            d.equipment,
            (v) => setState(
              () => d.equipment.contains(v)
                  ? d.equipment.remove(v)
                  : d.equipment.add(v),
            ),
          ),
        ];
    }
  }
}

class _NumberStepper extends StatelessWidget {
  final double value;
  final String unit;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  const _NumberStepper({
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: Sz.tapTarget),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(R.control),
      border: Border.all(color: C.actionOutline, width: 2),
    ),
    child: Row(
      children: [
        _StepBtn(
          icon: Icons.remove,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Center(
            child: ValueUnit(
              value: value.toStringAsFixed(0),
              unit: unit,
              style: T.numberM(),
            ),
          ),
        ),
        _StepBtn(
          icon: Icons.add,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    ),
  );
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      width: Sz.tapTarget,
      height: Sz.tapTarget,
      child: Icon(
        icon,
        size: Sz.iconDense,
        color: onTap == null ? C.textDisabled : C.textPrimary,
      ),
    ),
  );
}

/// 日期選擇器（§8.9）：年 : 月 : 日 ＝ 4 : 3 : 3，點任一欄從底部抽屜彈出選項。
class _BirthdayPicker extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  const _BirthdayPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = appNow();
    final y = value?.year ?? now.year - 25;
    final m = value?.month ?? 1;
    final day = value?.day ?? 1;
    final daysInMonth = DateTime(y, m + 1, 0).day;

    Future<void> pick(
      String title,
      List<int> options,
      int current,
      ValueChanged<int> set,
    ) async {
      final picked = await showAppSheet<int>(
        context,
        title: title,
        child: Column(
          children: [
            for (final o in options)
              ListRow(
                title: '$o',
                trailing: o == current
                    ? const Icon(
                        Icons.check,
                        size: Sz.iconDense,
                        color: C.actionOutline,
                      )
                    : null,
                onTap: () => Navigator.pop(context, o),
                showDivider: o != options.last,
              ),
          ],
        ),
      );
      if (picked != null) set(picked);
    }

    Widget field(int flex, String text, VoidCallback onTap) => Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.control),
        child: Container(
          constraints: const BoxConstraints(minHeight: Sz.buttonMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: S.md),
          decoration: BoxDecoration(
            color: C.bgSurface,
            borderRadius: BorderRadius.circular(R.control),
            border: Border.all(color: C.lineDivider),
          ),
          child: Row(
            children: [
              Expanded(child: Text(text, style: T.body())),
              const Icon(
                Icons.expand_more,
                size: Sz.iconDense,
                color: C.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );

    int clampDay(int yy, int mm, int dd) =>
        dd.clamp(1, DateTime(yy, mm + 1, 0).day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('生日', style: T.caption()),
        const SizedBox(height: S.xs),
        Row(
          children: [
            // 年份需要 4 位數，月日只要 2 位數，所以年欄較寬
            field(
              4,
              '$y',
              () => pick(
                '年',
                [for (var i = now.year; i >= now.year - 100; i--) i],
                y,
                (v) => onChanged(DateTime(v, m, clampDay(v, m, day))),
              ),
            ),
            const SizedBox(width: S.md),
            field(
              3,
              m.toString().padLeft(2, '0'),
              () => pick(
                '月',
                [for (var i = 1; i <= 12; i++) i],
                m,
                (v) => onChanged(DateTime(y, v, clampDay(y, v, day))),
              ),
            ),
            const SizedBox(width: S.md),
            // 日的選項隨年月變動：2 月不出現 30、31；閏年才有 2/29
            field(
              3,
              day.toString().padLeft(2, '0'),
              () => pick(
                '日',
                [for (var i = 1; i <= daysInMonth; i++) i],
                day,
                (v) => onChanged(DateTime(y, m, v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  final SignUpDraft draft;
  final AppState state;
  final VoidCallback onNext;

  /// 真正的第一次註冊。詳見 [SignUpScreen.firstRun]。
  final bool firstRun;

  const _Done({
    required this.draft,
    required this.state,
    required this.onNext,
    this.firstRun = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.base, S.xl, S.base, S.base),
          children: [
            const Icon(Icons.check_circle, size: 64, color: C.statusSuccess),
            const SizedBox(height: S.lg),
            Center(child: Text('註冊完成', style: T.h1())),
            const SizedBox(height: S.sm),
            Center(
              child: Text('${SignUpDraft.total} 項個人資料已填畢',
                  style: T.body(color: C.textSecondary)),
            ),
            const SizedBox(height: S.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('註冊獎勵', style: T.h3()),
                  const SizedBox(height: S.md),
                  Row(
                    children: [
                      Expanded(
                        child: StatField(label: '金幣', value: '$kSignUpCoins'),
                      ),
                      Expanded(
                        child: StatField(
                          label: '補簽券',
                          value: '$kSignUpMakeupTickets',
                          unit: '張',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('接著為你推薦訓練計畫', style: T.h3()),
                  const SizedBox(height: S.sm),
                  Text(
                    '依據：${draft.experience}、${draft.commonGoal}、'
                    '每週 ${draft.daysPerWeek} 天、${draft.duration}、'
                    '${draft.equipment.join('、')}',
                    style: T.caption(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _Footer(
        child: AppButton(
          label: '看推薦的訓練計畫',
          // **沒填完就按不下去。**
          // completeSignUp() 開頭是 `if (!draft.complete) return;` ——
          // 沒有這道 gate 的話，它會靜靜地什麼都不做，
          // 而畫面照樣跳出「帳號已建立」並往下走。
          // 一個會說謊的成功訊息，比一顆按不下去的按鈕糟得多。
          onPressed: !draft.complete
              ? null
              : () async {
                  // 「使用者帳號已建立」會把帳號層級的計數器全部歸位 ——
                  // 這正是「從未訓練者」該有的起點，但它會清掉示範資料，
                  // 所以先問過。不可復原的事一律先問。
                  // 第一次註冊沒有東西可以覆蓋 —— 那道確認只在
                  // 從「流程示範」點進來、身上已經有一個帳號時才有意義。
                  if (!firstRun) {
                    final ok = await showAppDialog(
                      context,
                      title: '以新帳號完成註冊？',
                      // 原本這段先講「模型定義帳號建立時一併產生兩個
                      // Aggregate」才講後果 —— 那是給讀規格的人看的順序。
                      // 對話框要先講會發生什麼事（`[QA-02m]`）。
                      message: '這會把目前帳號的階級、金幣、能力值、訓練與簽到'
                          '紀錄全部歸零，變成一個真正的新帳號：'
                          '六維點數回到 10，上次訓練日期與各維最後訓練日'
                          '都改成今天。\n\n'
                          '示範用途：這樣才看得到「從未訓練的人」如何走完'
                          '四道門檻並收到回歸任務。此操作不可復原。',
                      confirmLabel: '以新帳號繼續',
                      destructive: true,
                    );
                    if (ok != true || !context.mounted) return;
                  }
                  // 「訓練計畫已推薦」的 Precondition 是「使用者已完成註冊」——
                  // 故獎勵先發，推薦頁才進得去。
                  state.completeSignUp();
                  // **不發 toast。** 它是浮動式的、貼在畫面底部，而下一頁
                  // （訓練計畫推薦）的主按鈕也在底部 —— 浮層會蓋住它並且
                  // 攔截點擊，使用者按了沒反應，兩秒後才突然通了。
                  //
                  // 而且它也沒說出新東西：這一頁本來就寫著「帳號已建立」
                  // 並列出金幣 100 與補簽券，畫面換頁本身就是回饋。
                  onNext();
                },
        ),
      ),
    ],
  );
}
