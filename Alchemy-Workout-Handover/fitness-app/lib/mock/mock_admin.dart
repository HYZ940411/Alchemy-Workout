import '../domain/custom_plan.dart';
import '../domain/admin.dart';
import '../domain/models.dart';
import 'mock_data.dart';

/// n 組、每組同一個目標重量與次數（有氧時第二個數為秒數）。
List<PlannedSet> _s(int n, double w, int reps) =>
    List.generate(n, (_) => PlannedSet(w, reps));

DateTime _h(int hours) => DateTime.now().subtract(Duration(hours: hours));

const kCurrentAdmin = Admin(
  id: 'A-001',
  name: '你（管理員）',
  scopes: {
    AdminScope.contentReview,
    AdminScope.productManage,
    AdminScope.platformConfig,
  },
);

List<ReportCase> buildReports() => [
      ReportCase(
        id: 'R-2041',
        target: ReportTarget.comment,
        origin: CaseOrigin.userReport,
        content: '你這種身材也敢發文？回家躺著吧',
        reason: '人身攻擊',
        reporterCount: 4,
        accused: '不練會死',
        accusedViolations: 2,
        enteredAt: _h(200), // 已逾檢舉的 7 天時限
        state: CaseState.reviewing,
        handlerName: '管理員 陳',
      ),
      ReportCase(
        id: 'R-2043',
        target: ReportTarget.post,
        origin: CaseOrigin.autoFlag,
        content: '私訊我教你怎麼用禁藥快速增肌，效果保證',
        reason: '命中違規類別：管制藥品',
        reporterCount: 0,
        accused: 'Ryan',
        accusedViolations: 4,
        enteredAt: _h(11),
      ),
      ReportCase(
        id: 'R-2044',
        targetKey: 'message:c3',
        target: ReportTarget.message,
        origin: CaseOrigin.userReport,
        content: '加我賴，有便宜課程',
        reason: '廣告與招攬',
        reporterCount: 1,
        accused: '增肌中',
        accusedViolations: 6,
        enteredAt: _h(3),
      ),
      // 針對本人的檢舉 —— 供走完「檢舉 → 處罰 → 申訴 → 撤銷」整條線。
      ReportCase(
        id: 'R-2046',
        targetKey: 'post:me-1',
        target: ReportTarget.post,
        origin: CaseOrigin.userReport,
        content: '這種練法根本沒用，發這種文的人是不是沒讀過書',
        reason: '騷擾辱罵',
        reporterCount: 1,
        accused: '你',
        accusedViolations: 0,
        enteredAt: _h(6),
      ),
      ReportCase(
        id: 'R-2045',
        target: ReportTarget.account,
        origin: CaseOrigin.userReport,
        content: '帳號：假教練帳號',
        reason: '冒充他人身分',
        reporterCount: 2,
        accused: '假教練帳號',
        accusedViolations: 0,
        enteredAt: _h(30),
      ),
    ];

List<AppealCase> buildAppeals() => [
      AppealCase(
        id: 'AP-311',
        appellant: '林小美',
        target: AppealTarget.punishment,
        subject: '社群功能停權 7 天',
        reason: '那句話是在回覆自己的訓練夥伴，是玩笑不是攻擊，'
            '對方也留言說沒關係。希望重新審視。',
        filedAt: _h(20),
        daysSinceIncident: 4,
      ),
      AppealCase(
        id: 'AP-312',
        appellant: 'Yuki',
        target: AppealTarget.blockedContent,
        subject: '貼文遭自動攔截',
        reason: '我寫的是「不要用類固醇」，是在勸阻不是推廣。',
        filedAt: _h(90), // 已逾申訴的 72 小時時限
        daysSinceIncident: 4,
        state: CaseState.reviewing,
        handlerName: '管理員 王',
      ),
    ];

List<InstructorCase> buildInstructorCases() => [
      InstructorCase(
        id: 'IC-77',
        applicant: '早鳥訓練',
        aiScores: {'專業正確性': 82, '表達清晰度': 74, '安全意識': 91},
        weighted: 82.4,
        concerns: [],
        // **題目文字要與題庫一致。** 審核畫面以題目全文回查題庫來取出
        // 評分細則（見 `_Rubric`）—— 這裡如果寫的是自己編的題目，
        // 細則就回查不到，而那個功能在示範裡等於不存在。
        answers: [
          ('一位久坐上班族來找你，沒有運動習慣、沒有已知疾病。'
              '請說明你在替他安排第一個月之前，會先問哪些事、為什麼問，'
              '以及哪些回答會讓你先請他就醫。',
              '我會先問他有沒有正在服藥、過去有沒有受過傷、'
              '平常睡幾小時、每週能練幾次、在哪裡練。'
              '問用藥跟傷病是因為那會決定哪些動作先不要碰；'
              '問睡眠跟時間是因為課表排得再好，排在他做不到的時段也沒用。'
              '如果他說運動時胸口悶過、或最近體重莫名一直掉，'
              '我會先請他去看醫生，那兩件事不是我能判斷的。'),
          ('學員要求你開立每日飲食內容與補劑清單。'
              '請寫出你實際會對他說的話（可用對話形式），'
              '並說明你的界線畫在哪裡、為什麼。',
              '我會跟他說：「我可以跟你聊一般的原則，'
              '但幫你訂每天吃幾克、吃什麼補劑，那是營養師的範圍，我不能做。」'
              '然後幫他把想問的整理成幾個問題，讓他帶去問專業的人。'
              '界線在於個別化的處方 —— 一般衛教誰都可以講，'
              '但針對他一個人開的東西不行。'),
        ],
        enteredAt: _h(26),
      ),
      InstructorCase(
        id: 'IC-78',
        applicant: '硬舉狂魔',
        aiScores: {'專業正確性': 61, '表達清晰度': 88, '安全意識': 44},
        weighted: 62.1,
        concerns: ['安全意識分數偏低', '簡答提及「痛就是有練到」'],
        // 這一筆是**該被駁回**的示範：答案刻意踩中 sa03 的不通過條件
        // （「痛就是還不夠強」為處理方向、完全不提轉介）。
        // 題目文字同樣要與題庫一致，審核畫面才回查得到細則。
        answers: [
          ('學員在你指導期間反覆抱怨同一個部位不適，但你觀察'
              '動作沒有明顯問題。請依序說明你接下來的處理步驟。',
              '痛就是有練到，讓他戴腰帶繼續做，習慣就好了。'),
        ],
        enteredAt: _h(24 * 13), // 已逾教官簡答的 7 個工作天
      ),
    ];

List<PublicPlanCase> buildPublicPlanCases() => [
      PublicPlanCase(
        id: 'PP-19',
        author: 'CoreMax',
        exercises: ['棒式 3×60 秒', '死蟲 3×12', '鳥狗 3×12', '側棒式 2×45 秒'],
        appliedAt: _h(40),
      ),
      PublicPlanCase(
        id: 'PP-20',
        author: '深蹲王',
        exercises: ['深蹲 10×10 @85%', '硬舉 8×5 @90%', '早安式 5×8'],
        appliedAt: _h(8),
      ),
    ];

List<RatingSummary> buildRatingSummaries() => [
      RatingSummary(
        target: RatingTarget.trainingPlan,
        name: '推日：胸肩三頭',
        distribution: const [2, 3, 14, 46, 71],
        entries: [
          (5, '動作安排很順，暖身到主課表銜接得好', _h(30)),
          (4, null, _h(52)),
          (5, '時間剛好一小時', _h(70)),
        ],
      ),
      RatingSummary(
        target: RatingTarget.trainingPlan,
        name: '腿日：深蹲主導',
        distribution: const [9, 17, 22, 11, 6],
        entries: [
          (2, '組數太多，練完隔天走不動，一週練不了第二次', _h(12)),
          (1, '5 組 5 下對新手太重了', _h(28)),
          (3, '還可以但真的很累', _h(44)),
        ],
      ),
      RatingSummary(
        target: RatingTarget.noviceTask,
        name: '新手任務',
        distribution: const [1, 2, 9, 38, 62],
        entries: [
          (5, '三選一很好，不會有壓力', _h(18)),
          (4, null, _h(60)),
        ],
      ),
    ];

/// 管理員商品清單：含已下架者 —— 上架 Command 的對象正是已下架商品。
/// 一個商品規格（商品的子聚合）。價格與庫存皆屬規格層級，
/// 商品層級無單一價格與庫存。
class AdminProductSpec {
  final String name;

  /// 售價，單位為**金幣**。與 [ProductSpec.coinPrice] 是同一個數。
  int price;
  int stock;
  AdminProductSpec(this.name, this.price, this.stock);
}

class AdminProduct {
  final String id;
  String name;
  final String emoji;

  VirtualSubtype? subtype;

  /// 解鎖標的。僅權限解鎖類有值，指向該商品所解鎖的訓練計畫。
  String? unlockTarget;

  /// 商品圖片（圖片集合）。
  List<String> images;
  ListingState listing;
  final List<AdminProductSpec> specs;

  AdminProduct({
    required this.id,
    required this.name,
    required this.emoji,
    required this.listing,
    required this.specs,
    this.subtype,
    this.unlockTarget,
    List<String>? images,
  }) : images = images ?? [];

  /// 已設定完商品資訊 —— 上架 Precondition 的前半。
  /// 名稱與圖片皆有值才算設定完；權限解鎖類另須指定解鎖標的。
  bool get infoComplete =>
      name.trim().isNotEmpty &&
      images.isNotEmpty &&
      (subtype != VirtualSubtype.unlock || (unlockTarget?.isNotEmpty ?? false));

  /// 權限解鎖類不適用庫存：解鎖為冪等狀態，非可消耗的資源。
  bool get stockApplies => subtype != VirtualSubtype.unlock;

  /// 上架 Precondition 的後半：至少一個規格的庫存 > 0。
  bool get hasStock => !stockApplies || specs.any((x) => x.stock > 0);

  /// 上架的完整 Precondition。
  bool get canList => infoComplete && hasStock;

  /// 售完不自動下架 —— 這裡只是呈現用的判斷。
  bool get soldOut => stockApplies && specs.every((x) => x.stock == 0);
}

List<AdminProduct> buildAdminProducts() => [
      AdminProduct(
        id: 'v1', name: 'AI 點數 ×10', emoji: '✨',
        subtype: VirtualSubtype.consumable,
        listing: ListingState.listed,
        images: ['im_ticket'],
        specs: [AdminProductSpec('10 點', 1500, 999)],
      ),
      AdminProduct(
        id: 'v2', name: '單次 AI 調整使用權', emoji: '⚡',
        subtype: VirtualSubtype.consumable,
        listing: ListingState.listed,
        images: ['im_chart'],
        specs: [AdminProductSpec('1 次', 150, 999)],
      ),
      AdminProduct(
        id: 'v3', name: '補簽券 ×3', emoji: '🎫',
        subtype: VirtualSubtype.consumable,
        listing: ListingState.listed,
        images: ['im_ticket'],
        specs: [AdminProductSpec('3 張', 400, 999)],
      ),
      AdminProduct(
        id: 'v5', name: '限量點數包（春季）', emoji: '🎁',
        subtype: VirtualSubtype.consumable,
        listing: ListingState.delisted,
        images: ['im_badge'],
        specs: [AdminProductSpec('5 點', 300, 0)],
      ),
      AdminProduct(
        id: 'v4', name: '進階訓練計畫解鎖', emoji: '🔓',
        subtype: VirtualSubtype.unlock,
        listing: ListingState.listed,
        images: ['im_plan'],
        unlockTarget: '推日：胸肩三頭',
        specs: [AdminProductSpec('單一計畫', 800, 999)],
      ),
    ];

/// 自訂訓練的假資料。前 5 筆為本人的，後 2 筆為他人送審中的課表 ——
/// 管理員的待審佇列兩者都要看得到。
List<CustomPlan> buildCustomPlans() => [
      CustomPlan(
        id: 'cp1',
        name: '我的核心日',
        myUses: 6,
        state: CustomPlanState.published,
        visibleToFollowers: true,
        exercises: [
          PlanExercise(exercise: ex('plank'), planned: _s(3, 0, 60)),
          PlanExercise(exercise: ex('crunch'), planned: _s(4, 8, 15)),
        ],
      ),
      CustomPlan(
        id: 'cp2',
        name: '週末全身循環',
        myUses: 12,
        state: CustomPlanState.public,
        visibleToFollowers: true,
        exercises: [
          PlanExercise(exercise: ex('squat'), planned: _s(4, 80, 8)),
          PlanExercise(exercise: ex('bench'), planned: _s(4, 60, 8)),
          PlanExercise(exercise: ex('row'), planned: _s(4, 55, 8)),
          PlanExercise(exercise: ex('ohp'), planned: _s(3, 35, 10)),
          PlanExercise(exercise: ex('plank'), planned: _s(3, 0, 45)),
        ],
      ),
      CustomPlan(
        id: 'cp3',
        name: '出差旅館版',
        myUses: 3,
        state: CustomPlanState.pendingPublic,
        appliedAt: _d(5),
        exercises: [
          PlanExercise(exercise: ex('dip'), planned: _s(4, 0, 15)),
          PlanExercise(exercise: ex('squat'), planned: _s(4, 0, 20)),
          PlanExercise(exercise: ex('plank'), planned: _s(3, 0, 60)),
          PlanExercise(exercise: ex('crunch'), planned: _s(3, 0, 30)),
        ],
      ),
      CustomPlan(
        id: 'cp4',
        name: '新的推日草案',
        myUses: 0,
        state: CustomPlanState.saved,
        exercises: [
          PlanExercise(exercise: ex('bench'), planned: _s(4, 55, 8)),
          PlanExercise(exercise: ex('ohp'), planned: _s(3, 30, 10)),
          PlanExercise(exercise: ex('dip'), planned: _s(3, 0, 12)),
        ],
      ),
      CustomPlan(
        id: 'cp5',
        name: '高強度間歇',
        myUses: 1,
        author: '核心怪物',
        isMine: false,
        state: CustomPlanState.rejected,
        rejectReason: '課表包含未經驗證的高風險動作組合，請調整後重新送審。',
        exercises: [
          PlanExercise(exercise: ex('squat'), planned: _s(6, 100, 5)),
          PlanExercise(exercise: ex('bench'), planned: _s(5, 80, 5)),
          PlanExercise(exercise: ex('row'), planned: _s(5, 70, 5)),
          PlanExercise(exercise: ex('ohp'), planned: _s(4, 45, 6)),
          PlanExercise(exercise: ex('curl'), planned: _s(3, 20, 10)),
          PlanExercise(exercise: ex('plank'), planned: _s(3, 0, 40)),
        ],
      ),
      // 他人送審中的課表 —— 其中一筆已逾 14 天審核時限。
      CustomPlan(
        id: 'cp6',
        name: '核心強化四週',
        myUses: 0,
        author: 'CoreMax',
        isMine: false,
        state: CustomPlanState.pendingPublic,
        appliedAt: _d(2),
        exercises: [
          PlanExercise(exercise: ex('plank'), planned: _s(3, 0, 60)),
          PlanExercise(exercise: ex('crunch'), planned: _s(3, 10, 12)),
          PlanExercise(exercise: ex('crunch'), planned: _s(3, 25, 12)),
          PlanExercise(exercise: ex('plank'), planned: _s(2, 0, 45)),
        ],
      ),
      CustomPlan(
        id: 'cp7',
        name: '大重量週期',
        myUses: 0,
        author: '深蹲王',
        isMine: false,
        state: CustomPlanState.pendingPublic,
        appliedAt: _d(17),
        exercises: [
          PlanExercise(exercise: ex('squat'), planned: _s(10, 120, 10)),
          PlanExercise(exercise: ex('deadlift'), planned: _s(8, 140, 5)),
          PlanExercise(exercise: ex('row'), planned: _s(5, 80, 8)),
        ],
      ),
    ];

DateTime _d(int days) => DateTime.now().subtract(Duration(days: days));

/// 管理員帳號清單（〈管理員本身的維護〉）。停用者不實體刪除 ——
/// 其既往的判定紀錄仍須可稽核。
List<Admin> buildAdmins() => [
      kCurrentAdmin,
      const Admin(
        id: 'A-002',
        name: '審核組 · 林',
        scopes: {AdminScope.contentReview},
      ),
      const Admin(
        id: 'A-003',
        name: '商務組 · 陳',
        scopes: {AdminScope.productManage, AdminScope.contentReview},
      ),
      const Admin(
        id: 'A-004',
        name: '前審核組 · 黃',
        scopes: {AdminScope.contentReview},
        status: AdminStatus.disabled,
      ),
    ];
