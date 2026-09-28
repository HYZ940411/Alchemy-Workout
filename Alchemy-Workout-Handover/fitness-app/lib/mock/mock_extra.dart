import '../domain/ability.dart';
import '../domain/clock.dart';
import '../domain/commerce.dart';
import '../domain/community.dart';
import '../domain/task_pool.dart';
import '../domain/social.dart';
import 'mock_data.dart';

DateTime _ago(int days, {int h = 0}) =>
    DateTime.now().subtract(Duration(days: days, hours: h));

// --- 社群動態牆 ---
List<Post> buildPosts() => [
      Post(
        id: 'p1',
        author: '深蹲王',
        authorRank: 41,
        authorReputation: 320,
        text: '腿日結束，深蹲終於站起 140kg。核心撐住是關鍵，不要為了重量圓背。',
        at: _ago(0, h: 2),
        attachedWorkout: '腿日：深蹲主導　11 組　完成度 100%',
        likes: 48,
        comments: [
          Comment('林小美', '太強了吧！', _ago(0, h: 1)),
          Comment('增肌中', '請問你熱身怎麼安排？', _ago(0, h: 1)),
        ],
      ),
      Post(
        id: 'p2',
        author: '早鳥訓練',
        authorRank: 27,
        text: '連續 30 天簽到達成，習慣真的是靠環境不是靠意志力。',
        at: _ago(0, h: 6),
        likes: 23,
        comments: [Comment('Yuki', '同意，我也是把包包先放門口', _ago(0, h: 5))],
      ),
      Post(
        id: 'p3',
        author: 'CoreMax',
        authorRank: 55,
        authorReputation: 610,
        text: '很多人核心練不起來，是因為只做捲腹。抗伸展與抗旋轉才是核心的主要功能。',
        at: _ago(1),
        likes: 91,
        comments: [],
      ),
      // 本人的貼文。後台佇列的 R-2046 正是針對它 ——
      // 判定成立時它會被下架，供「檢舉 → 下架 → 處罰 → 申訴」整條線走得完。
      Post(
        id: 'me-1',
        author: '你',
        authorRank: 45,
        text: '這種練法根本沒用，發這種文的人是不是沒讀過書',
        at: _ago(1, h: 3),
        likes: 2,
        comments: [],
      ),
      Post(
        id: 'p4',
        author: '不練會死',
        authorRank: 18,
        text: '今天推日，臥推 62.5kg × 8 破紀錄了 💪',
        at: _ago(2),
        attachedWorkout: '推日：胸肩三頭　13 組　完成度 100%',
        likes: 15,
        comments: [],
      ),
    ];

// --- 團隊 ---
Team buildMyTeam() => Team(
      id: 't1',
      name: '晨型人訓練隊',
      isPublic: true,
      lockedGroupSize: 4,
      // 各成員的本隊已貢獻分數。加總即為月累計日常分數（9960）。
      // 可變 —— 成員每次得分時同額累加，不是一份固定數字。
      // 鍵是 `personKey` —— 示範資料的假隊友沒有 uid，所以是暱稱鍵。
      contributions: {
        personKey('你', null): 3120,
        personKey('早鳥訓練', null): 2980,
        personKey('Yuki', null): 2010,
        personKey('核心怪物', null): 1850,
      },
      timedScore: 620,
      dailyRankPos: 7,
      timedRankPos: 12,
      // 成員與待回應清單皆可變 —— 踢除、邀請會改動它們。
      members: [
        const TeamMember('你', 24, TeamRole.leader),
        const TeamMember('早鳥訓練', 27, TeamRole.member),
        const TeamMember('Yuki', 19, TeamRole.member),
        const TeamMember('核心怪物', 33, TeamRole.member),
      ],
      // 今日限時任務中，完成紀錄記在本隊帳上的成員。
      // 鍵是 `personKey` —— 示範資料的假隊友沒有 uid，所以是暱稱鍵。
      timedCredited: {personKey('早鳥訓練', null), personKey('Yuki', null)},
      invites: [PendingRequest('林小美', 22, DateTime.now().add(const Duration(days: 5)))],
      applications: [
        PendingRequest('增肌中', 15, DateTime.now().add(const Duration(days: 6))),
        PendingRequest('Ryan', 31, DateTime.now().add(const Duration(days: 2))),
      ],
    );

/// 公開團隊。成員名單與簡介都給滿 —— 團隊詳情頁要決定的是「要不要申請加入」，
/// 只給隊名與人數答不出這個問題。
///
/// 分數刻意跨三個組別，好讓排行榜看得出「只跟同組別比」。
List<PublicTeam> buildPublicTeams() => [
      PublicTeam(
        '鐵人俱樂部',
        3,
        kTeamCapacity,
        id: 'p1',
        viaFollowing: true,
        intro: '每週三、六固定團練，歡迎硬舉 1.5 倍體重以上的夥伴加入。',
        members: const [
          TeamMember('吳佩珊', 41, TeamRole.leader),
          TeamMember('黃志明', 33, TeamRole.member),
          TeamMember('蔡宗翰', 29, TeamRole.member),
        ],
        dailyScore: 12540,
        timedScore: 430,
      ),
      PublicTeam(
        '週三練胸團',
        4,
        kTeamCapacity,
        id: 'p2',
        viaFollowing: true,
        intro: '推日為主，收下班後練得動的人。不強制出席，但請回報。',
        members: const [
          TeamMember('劉思妤', 38, TeamRole.leader),
          TeamMember('阿哲', 22, TeamRole.member),
          TeamMember('小柯', 17, TeamRole.member),
          TeamMember('Wei', 30, TeamRole.member),
        ],
        dailyScore: 14280,
        timedScore: 610,
      ),
      PublicTeam(
        '增肌不增脂',
        5,
        kTeamCapacity,
        id: 'p3',
        intro: '滿員了，之後有人退出會再開。',
        members: const [
          TeamMember('Bruce', 52, TeamRole.leader),
          TeamMember('Anna', 44, TeamRole.member),
          TeamMember('阿宏', 36, TeamRole.member),
          TeamMember('小玉', 25, TeamRole.member),
          TeamMember('Kevin', 20, TeamRole.member),
        ],
        dailyScore: 16900,
        timedScore: 780,
      ),
      PublicTeam(
        '新手友善隊',
        2,
        kTeamCapacity,
        id: 'p4',
        intro: '剛開的隊，還在找人。不看等級，能持續就好。',
        members: const [
          TeamMember('小魚', 8, TeamRole.leader),
          TeamMember('阿祥', 5, TeamRole.member),
        ],
        dailyScore: 2100,
        timedScore: 80,
      ),
      PublicTeam(
        '硬舉愛好會',
        4,
        kTeamCapacity,
        id: 'p5',
        isPublic: false,
        intro: '私密隊，只收熟人。',
        members: const [
          TeamMember('大熊', 47, TeamRole.leader),
          TeamMember('阿凱', 35, TeamRole.member),
          TeamMember('Tina', 28, TeamRole.member),
          TeamMember('小豪', 26, TeamRole.member),
        ],
        dailyScore: 9800,
        timedScore: 520,
      ),
      PublicTeam(
        '北區重訓團',
        4,
        kTeamCapacity,
        id: 'p8',
        intro: '固定在同一間健身房，方便互相補位。',
        members: const [
          TeamMember('宗翰', 39, TeamRole.leader),
          TeamMember('小林', 27, TeamRole.member),
          TeamMember('Ivy', 24, TeamRole.member),
          TeamMember('阿倫', 18, TeamRole.member),
        ],
        dailyScore: 12200,
        timedScore: 480,
      ),
      PublicTeam(
        '初學者互助會',
        4,
        kTeamCapacity,
        id: 'p9',
        intro: '大家都是新手，一起把姿勢練對。',
        members: const [
          TeamMember('小安', 11, TeamRole.leader),
          TeamMember('阿丞', 9, TeamRole.member),
          TeamMember('Nina', 7, TeamRole.member),
          TeamMember('小杰', 6, TeamRole.member),
        ],
        dailyScore: 10440,
        timedScore: 260,
      ),
      // 曾達 5 人、月底跌到 3 人 —— 分組與資格都看週期內最高值，
      // 所以它仍在 5 人組，不會因臨時踢人變成 3 人組成績。
      PublicTeam(
        '週末戰士',
        3,
        kTeamCapacity,
        id: 'p6',
        intro: '週末練兩天，平日各自。',
        members: const [
          TeamMember('阿德', 40, TeamRole.leader),
          TeamMember('Ken', 31, TeamRole.member),
          TeamMember('小婷', 23, TeamRole.member),
        ],
        dailyScore: 8720,
        timedScore: 350,
        peakSize: 5,
      ),
      // 本月從未成局（最高 2 人）—— 排除於排行榜與獎勵之外，但分數照常累積。
      PublicTeam(
        '深蹲同好會',
        2,
        kTeamCapacity,
        id: 'p7',
        intro: '兩個人也是練。',
        members: const [
          TeamMember('阿俊', 12, TeamRole.leader),
          TeamMember('Momo', 9, TeamRole.member),
        ],
        dailyScore: 6880,
        timedScore: 190,
      ),
    ];

/// 限時任務：全平台統一，一個指派日一組。
TimedTask buildTimedTask() {
  // 指派時戳取「現在」，使其必定落在當前的業務日內。
  // 寫死 04:00 會在當地 00:00–03:59 被換日規則判為前一個業務日而顯示已失效。
  return TimedTask(
    title: '10 分鐘全身循環',
    detail: '深蹲 15 下 ＋ 伏地挺身 10 下 ＋ 棒式 30 秒，做完三輪。'
        '訓練類項目照常走訓練紀錄流程，連續天數與能力值全部照常累計。',
    assignedOn: DateTime.now(),
    completedBy: {personKey('早鳥訓練', null), personKey('Yuki', null)},
  );
}

// --- 教官 ---
Map<Dim, int> _ab(int c, int b, int l, int s, int a, int co) => {
      Dim.chest: c, Dim.back: b, Dim.legs: l,
      Dim.shoulders: s, Dim.arms: a, Dim.core: co,
    };

List<Instructor> buildInstructors() => [
      Instructor(
        name: 'CoreMax', rank: 55, reputation: 610,
        apprentices: 3, apprenticeCap: 5,
        ability: _ab(700, 720, 660, 640, 610, 780),
        specialties: const ['核心穩定', '姿勢矯正'],
        avgRating: 4.8, ratingCount: 42,
      ),
      Instructor(
        name: '深蹲王', rank: 41, reputation: 320,
        apprentices: 2, apprenticeCap: 4,
        ability: _ab(560, 610, 840, 520, 500, 640),
        specialties: const ['下肢力量', '競技備賽', '飲食規劃'],
        avgRating: 4.5, ratingCount: 18,
      ),
      Instructor(
        name: '硬舉狂魔', rank: 62, reputation: 780,
        apprentices: 5, apprenticeCap: 5,
        ability: _ab(640, 860, 820, 600, 640, 700),
        specialties: const ['爆發力訓練'],
        avgRating: 4.9, ratingCount: 67,
      ),
      Instructor(
        name: 'Ashley', rank: 38, reputation: 240,
        apprentices: 1, apprenticeCap: 4,
        ability: _ab(480, 500, 560, 470, 450, 590),
        specialties: const ['產後恢復', '徒手訓練'],
        avgRating: 4.6, ratingCount: 11,
      ),
    ];

List<MentorTask> buildMentorTasks() => [
      MentorTask(
        title: '本週補足核心訓練',
        detail: '你的核心是六維中最弱的一環，本週請完成 2 次含核心動作的訓練。',
      ),
      MentorTask(
        title: '臥推降重量練姿勢',
        detail: '下次推日把重量降到 50kg，專注肩胛後收與腳踩地。',
        state: MentorTaskState.done,
      ),
    ];

List<MentorQuestion> buildQuestions() => [
      MentorQuestion(
        from: '你',
        text: '深蹲到底部的時候膝蓋會往內夾，是柔軟度問題還是肌力問題？',
        at: _ago(1),
        answer: '多半是臀中肌無力加上腳踝背屈受限。先做側走彈力帶暖身，'
            '再把重量降到能全程膝蓋外推的程度。',
      ),
      MentorQuestion(from: '你', text: '一週練四天的話，怎麼分部位比較好？', at: _ago(0, h: 3)),
    ];

List<Apprentice> buildApprentices() => [
      Apprentice(
        name: '增肌中', rank: 15,
        ability: _ab(280, 250, 310, 220, 240, 150),
        recentWorkouts: const ['08/24 推日 100%', '08/22 拉日 70%', '08/20 腿日 100%'],
        scoredThisWeek: 1,
      ),
      Apprentice(
        name: 'Yuki', rank: 19,
        ability: _ab(320, 340, 380, 290, 300, 260),
        recentWorkouts: const ['08/25 全身循環 100%', '08/23 推日 100%'],
        scoredThisWeek: 2,
      ),
    ];

// --- 私訊 ---
List<Conversation> buildConversations() => [
      Conversation(
        id: 'c1', peer: 'CoreMax', peerRank: 55, peerIsInstructor: true,
        messages: [
          ChatMessage(false, '這週的任務有做嗎？', _ago(0, h: 5)),
          ChatMessage(true, '有，核心做了兩次', _ago(0, h: 4)),
          ChatMessage(false, '很好，下週我們加抗旋轉的動作', _ago(0, h: 3), read: false),
        ],
      ),
      Conversation(
        id: 'c2', peer: '早鳥訓練', peerRank: 27,
        messages: [
          ChatMessage(true, '明天六點還去嗎', _ago(1)),
          ChatMessage(false, '去，老地方', _ago(1)),
        ],
      ),
      // 陌生訊息：分類寫在**訊息**上，不是對話上 ——
      // 分類於發送當下固定，一段對話的前後可能屬不同分類。
      Conversation(
        id: 'c3', peer: '增肌中', peerRank: 15,
        category: MessageCategory.stranger,
        messages: [
          ChatMessage(false, '你好，看到你的貼文想請教一下訓練安排', _ago(2),
              read: false, category: MessageCategory.stranger),
          // 後台佇列的 R-2044 針對此則；判定成立時只有這一則被下架，
          // 上面那句正常的往來留著。
          ChatMessage(false, '加我賴，有便宜課程', _ago(2),
              read: false, category: MessageCategory.stranger),
        ],
      ),
    ];

// --- 商城 ---
List<Product> buildProducts() => [
      Product(
        id: 'g1', name: '健金術 訓練 T', kind: ProductKind.physical, emoji: '👕',
        images: const ['im_tee'],
        specs: [
          ProductSpec('S', 900, 12),
          ProductSpec('M', 900, 4),
          ProductSpec('L', 900, 0),
          ProductSpec('XL', 950, 7),
        ],
      ),
      Product(
        id: 'g2', name: '助力帶', kind: ProductKind.physical, emoji: '🧤',
        images: const ['im_strap'],
        specs: [ProductSpec('單一尺寸', 600, 25)],
      ),
      Product(
        id: 'g3', name: '搖搖杯', kind: ProductKind.physical, emoji: '🥤',
        images: const ['im_shaker'],
        specs: [ProductSpec('700ml', 350, 40)],
      ),
      Product(
        id: 'v1', name: 'AI 點數 ×10', kind: ProductKind.virtual, emoji: '✨',
        images: const ['im_badge'],
        specs: [ProductSpec('10 點', 1500, 999)],
        aiCredits: 10,
      ),
      Product(
        id: 'v2', name: '單次 AI 調整使用權', kind: ProductKind.virtual, emoji: '⚡',
        images: const ['im_chart'],
        specs: [ProductSpec('1 次', 150, 999)],
        aiCredits: 1,
        note: '150 金幣 ＝ 30 元',
      ),
      Product(
        id: 'v3', name: '補簽券 ×3', kind: ProductKind.virtual, emoji: '🎫',
        images: const ['im_ticket'],
        specs: [ProductSpec('3 張', 400, 999)],
      ),
      Product(
        id: 'v4', name: '進階訓練計畫解鎖', kind: ProductKind.virtual, emoji: '🔓',
        // 價格取自平台參數，不寫死 —— 課表選擇頁用的是同一個參數，
        // 各寫各的就會出現「同一件東西，從商城買比從課表頁買貴」。
        specs: [ProductSpec('單一計畫', kPlanUnlockCoins, 999)],
      ),
    ];

List<Order> buildOrders() => [
      Order(
        id: 'O-20260824-001', productName: '健金術 訓練 T', spec: 'M', qty: 1,
        kind: ProductKind.physical, placedAt: _ago(2),
        coinPaid: 900, cashPaid: 0, state: OrderState.shipped,
        trackingNo: 'TW882410037',
        shipping: const ShippingInfo(
          name: '王小明',
          phone: '0912345678',
          zip: '110',
          address: '台北市信義區松高路 1 號 5 樓',
        ),
      ),
      Order(
        id: 'O-20260826-004', productName: 'AI 點數 ×10', spec: '10 點', qty: 1,
        kind: ProductKind.virtual, placedAt: _ago(0, h: 3),
        coinPaid: 640, cashPaid: 172, state: OrderState.pendingPayment,
      ),
      // 待付款的實體訂單：庫存已預扣，保留中 —— 供檢視倒數、取消與付款。
      Order(
        id: 'O-20260902-013', productName: '搖搖杯', spec: '700ml', qty: 1,
        kind: ProductKind.physical, placedAt: _ago(0, h: 0),
        coinPaid: 350, cashPaid: 0, state: OrderState.pendingPayment,
        holdUntil: DateTime.now().add(const Duration(minutes: 11)),
        shipping: const ShippingInfo(
          name: '王小明',
          phone: '0912345678',
          zip: '110',
          address: '台北市信義區松高路 1 號 5 樓',
        ),
      ),
      Order(
        id: 'O-20260819-002', productName: '助力帶', spec: '單一尺寸', qty: 2,
        kind: ProductKind.physical, placedAt: _ago(7),
        // 實體訂單的終止狀態是**已出貨**，不是已發放（那是虛擬的）。
        // 出貨時一併記錄物流單號，系統其後不再追蹤物流狀態。
        coinPaid: 1200, cashPaid: 0, state: OrderState.shipped,
        trackingNo: 'TW881903552',
      ),
      Order(
        id: 'O-20260815-009', productName: '搖搖杯', spec: '700ml', qty: 1,
        kind: ProductKind.physical, placedAt: _ago(11),
        coinPaid: 0, cashPaid: 0, state: OrderState.failed,
        failReason: FailReason.soldOut,
      ),
    ];

List<CreditEntry> buildCreditHistory() => [
      CreditEntry(at: _ago(0, h: 4), kind: CreditChange.deduct, delta: -1,
          monthlyAfter: 14, permanentAfter: 6, source: '訓練前調整'),
      CreditEntry(at: _ago(1), kind: CreditChange.deduct, delta: -1,
          monthlyAfter: 15, permanentAfter: 6, source: '訓練中調整'),
      CreditEntry(at: _ago(2), kind: CreditChange.refund, delta: 1,
          monthlyAfter: 16, permanentAfter: 6, source: '訓練前課表調整'),
      CreditEntry(at: _ago(3), kind: CreditChange.deduct, delta: -1,
          monthlyAfter: 15, permanentAfter: 6, source: '訓練前課表調整'),
      CreditEntry(at: _ago(9), kind: CreditChange.purchase, delta: 6,
          monthlyAfter: 18, permanentAfter: 6),
      CreditEntry(at: _ago(26), kind: CreditChange.monthlyGrant, delta: 20,
          monthlyAfter: 20, permanentAfter: 0),
    ];

List<MailReward> buildMailbox() => [
      MailReward(source: '排行榜週期結算', coins: 300, exp: 120, at: _ago(1)),
      MailReward(source: '每日任務未領取', coins: 6, at: _ago(2)),
      MailReward(
          source: '限時任務未領取', coins: 50, makeupTickets: 1, at: _ago(3)),
      MailReward(
          source: '補簽當日簽到獎勵',
          coins: 10,
          exp: 10,
          at: _ago(5),
          claimed: true),
    ];

Punishment? buildPunishment() => null; // 一般狀態為無處罰

/// 〈每日簽到紀錄 Aggregate〉的假資料。
///
/// **只存已簽到的日子** —— 未簽到之日不存在對應紀錄，
/// 「查無此筆」即代表該日未簽到。這正是補簽 Precondition
/// 「該日確實未簽到」的驗證來源。
Map<DateTime, CheckInMethod> buildCheckInRecords() {
  // **用展示時鐘與換日規則，不用原始日曆日。**
  // clock.dart 開宗明義：判定或寫入狀態的地方一律走 appNow()。
  // 而「今天」必須與 checkIn() 寫入時用的 businessDate 是同一天 ——
  // 不一致的話，當地 00:00–03:59 這四個小時內，假資料的「今天」
  // 會比 App 認定的「今天」晚一天，簽到相關的測試整批紅。
  final base = businessDate(appNow());
  // 距今 1–14 天的簽到史，不含今日。true 為當日有簽到。
  const signed = [
    true, true, false, true, false, true, true,
    false, true, true, false, true, false, true,
  ];
  return {
    for (var i = 0; i < signed.length; i++)
      if (signed[i]) base.subtract(Duration(days: i + 1)): CheckInMethod.real,
  };
}

/// 一次訓練裡某個動作的明細。**排除已取消的組紀錄** ——
/// 已取消者不實體刪除，但回顧時不呈現取消痕跡。
class HistoryExercise {
  final String name;

  /// 動作 ID。快照的逐組帶入以它為鍵 —— 用名稱比對，動作一改名就對不上，
  /// 使用者只會發現預帶值莫名回到課表初始值。
  final String? id;

  /// 逐組的實績：重量與次數。徒手動作的重量為 0。
  /// **只收已完成的組** —— 未完成的組不作為帶入來源。
  final List<(double weight, int reps)> sets;

  /// 徒手計時動作（如棒式）以秒為單位，改寫成「60 秒」而非「0 kg × 60」。
  final bool isTimed;

  const HistoryExercise(this.name, this.sets, {this.isTimed = false, this.id});

  /// 以動作 ID 建立 —— 名稱由平台動作庫取得，兩者不會對不起來。
  factory HistoryExercise.of(
    String id,
    List<(double, int)> sets, {
    bool isTimed = false,
  }) =>
      HistoryExercise(ex(id).name, sets, id: id, isTimed: isTimed);

  double get volume =>
      isTimed ? 0 : sets.fold(0.0, (a, s) => a + s.$1 * s.$2);
}

/// 訓練歷史（結算後凍結，永久保存）
class HistoryEntry {
  final DateTime date;
  final String planName;
  final double volume;
  final int minutes;
  final int calories;
  final List<HistoryExercise> exercises;

  /// 這一場做了計畫的幾成（0–1）。空白課表沒有計畫組數，故可為空值。
  ///
  /// **2026-09-26 新增。** 課表卡片上的「上次完成度」原本靠 `kPlans` 裡
  /// **寫死的假值**頂著；拿掉之後那一格變成「—」，因為訓練歷史從來沒有
  /// 存過這個數字 —— 只存了做了哪幾組，沒存「計畫有幾組」。
  final double? completion;

  const HistoryEntry(this.date, this.planName, this.volume, this.minutes,
      this.calories, this.exercises, {this.completion});

  int get totalSets => exercises.fold(0, (a, e) => a + e.sets.length);
}

List<(double, int)> _same(int n, double w, int r) =>
    List.generate(n, (_) => (w, r));

/// 訓練歷史。
///
/// **日期必須撐得起 [AppState.trainingStreakDays]**：首頁寫「連續訓練 12 天」，
/// 訓練歷史頁卻列出 8/28、8/30、9/2 這種隔日的日期，兩個畫面對同一件事
/// 給出不同答案。故最近 12 天逐日各一場，再往前才拉開間隔。
///
/// 最新一場為**昨天**，不是今天 —— 今天還沒練，首頁那顆「開始訓練」
/// 才站得住腳；[AppState.lastTrainedDate] 也由這裡推導。
List<HistoryEntry> buildHistory() {
  const plans = ['推日：胸肩三頭', '拉日：背二頭', '腿日：深蹲主導'];
  const sets = [
    [
      ('bench', 60.0, 8, 4),
      ('db_press', 22.0, 10, 3),
      ('ohp', 35.0, 8, 3),
      ('pushdown', 25.0, 12, 3),
    ],
    [
      ('row', 50.0, 8, 4),
      ('latpull', 45.0, 10, 3),
      ('curl', 15.0, 12, 3),
    ],
    [
      ('squat', 80.0, 5, 5),
      ('legpress', 120.0, 10, 3),
      ('crunch', 10.0, 15, 3),
    ],
  ];

  final out = <HistoryEntry>[];
  // 最近 12 天逐日一場，撐起「連續訓練 12 天」。
  for (var d = 1; d <= 12; d++) {
    final k = (d - 1) % 3;
    // 最後一組刻意與前面不同 —— 力竭後下修或衝一下是常態，
    // 而「逐組帶入」帶的正是上次**該組**的實際重量，
    // 每組都一樣的話那條規則測不出東西。
    final ex = [
      for (final (id, w, r, n) in sets[k])
        HistoryExercise.of(id, [..._same(n - 1, w, r), (w + 2.5, r - 1)]),
    ];
    final volume = sets[k].fold<double>(
        0, (a, e) => a + e.$2 * e.$3 * (e.$4 - 1) + (e.$2 + 2.5) * (e.$3 - 1));
    out.add(HistoryEntry(
      _ago(d),
      plans[k],
      volume,
      55 + (d % 4) * 5,
      340 + (d % 5) * 30,
      ex,
    ));
  }
  // 再往前是斷斷續續的舊紀錄。
  out.add(HistoryEntry(_ago(15), '我的核心日', 980, 32, 180, [
    HistoryExercise.of('plank', _same(3, 0, 60), isTimed: true),
    HistoryExercise.of('crunch', _same(4, 8, 15)),
  ]));
  return out;
}


// --- 社群關係與通知 ---

/// **不可以是 `const` 清單。** `applyPublicProfiles` 會把雲端讀回來、
/// 本機還沒有的使用者 `add` 進來，而 `const` 清單是不可修改的 ——
/// 那會在第一位新使用者到達時拋 `Cannot add to an unmodifiable list`。
List<SocialUser> buildSocialUsers() => [
      const SocialUser(name: '深蹲王', rank: 41, grade: 'B'),
      const SocialUser(name: 'CoreMax', rank: 55, grade: 'A'),
      const SocialUser(name: '早鳥訓練', rank: 27, grade: 'C'),
      const SocialUser(name: '硬舉狂魔', rank: 62, grade: 'A'),
      const SocialUser(name: 'Yuki', rank: 19, grade: 'C'),
      const SocialUser(name: '核心怪物', rank: 33, grade: 'B'),
      const SocialUser(name: 'Ashley', rank: 38, grade: 'B'),
    ];

List<String> buildFollowers() =>
    ['早鳥訓練', 'Yuki', '核心怪物', 'Ashley', '硬舉狂魔'];

/// 被封鎖者以匿名代稱呈現 —— 封鎖之後不該再把對方的名字擺在你眼前。
List<BlockedUser> buildBlockedUsers() => [
      BlockedUser('匿名使用者 A', _ago(21)),
      BlockedUser('匿名使用者 B', _ago(36)),
      BlockedUser('匿名使用者 C', _ago(91)),
    ];

/// 通知。今日刻意放 4 則推播 —— 同日總量上限為 3，
/// 才看得出「依優先序由低至高捨棄」這條規則。
List<AppNotification> buildNotifications() {
  final now = DateTime.now();
  DateTime today(int h, int m) => DateTime(now.year, now.month, now.day, h, m);
  return [
    AppNotification(
      id: 'n1',
      sourceEvent: '中斷預告已發送',
      title: '連續訓練快中斷了',
      body: '距上次訓練已 28 小時',
      at: today(8, 0),
      kind: NotifyKind.push,
      priority: NotifyPriority.expiring,
    ),
    AppNotification(
      id: 'n2',
      sourceEvent: '連簽中斷預告已發送',
      title: '該簽到囉',
      body: '今天還沒簽到，連續 12 天別斷了',
      at: today(9, 0),
      kind: NotifyKind.push,
      priority: NotifyPriority.expiring,
    ),
    AppNotification(
      id: 'n3',
      sourceEvent: '退步預告已發送',
      title: '能力值即將退步',
      body: '胸的訓練已停 96 小時',
      at: today(10, 0),
      kind: NotifyKind.push,
      priority: NotifyPriority.expiring,
    ),
    AppNotification(
      id: 'n4',
      sourceEvent: '每日登入提醒已發送',
      title: '每日登入提醒',
      body: '今天的任務等你完成',
      at: today(20, 0),
      kind: NotifyKind.push,
      priority: NotifyPriority.routine,
    ),
    // 今天的 App 內通知。刻意排在所有推播之前 ——
    // 若上限誤把它算進去，就會擠掉一則真正的推播。
    AppNotification(
      id: 'n7',
      sourceEvent: '成就已解鎖',
      title: '成就已解鎖',
      body: '連續訓練 10 天',
      at: today(7, 0),
      kind: NotifyKind.inApp,
    ),
    AppNotification(
      id: 'n5',
      sourceEvent: '商品已出貨',
      title: '你的訂單已出貨',
      body: '健金術 訓練 T　·　物流單號 TW882410037',
      at: _ago(30),
      kind: NotifyKind.inApp,
      read: true,
    ),
    AppNotification(
      id: 'n6',
      sourceEvent: '成就已解鎖',
      title: '成就已解鎖',
      body: '連續簽到 100 天',
      at: _ago(52),
      kind: NotifyKind.inApp,
      read: true,
    ),
  ];
}

/// 每日任務池的初始內容。個人項供每日任務抽取，團隊項供限時任務指派 ——
/// 同一份清單，以「適用對象」區分。
List<TaskPoolItem> buildTaskPool() => [
      TaskPoolItem(
          id: 'tp1', name: '完成一次訓練', sourceEvent: '訓練已結算', target: 1),
      TaskPoolItem(
          id: 'tp2', name: '按讚 3 則貼文', sourceEvent: '互動者已按讚貼文', target: 3),
      TaskPoolItem(id: 'tp3', name: '今日簽到', sourceEvent: '使用者已簽到', target: 1),
      TaskPoolItem(
          id: 'tp4', name: '留言 1 則', sourceEvent: '互動者已留言', target: 1),
      TaskPoolItem(
          id: 'tp5', name: '完成 12 組訓練', sourceEvent: '使用者已完成該組', target: 12),
      TaskPoolItem(
        id: 'tp6',
        name: '10 分鐘全身循環',
        sourceEvent: '訓練已結算',
        target: 1,
        audience: TaskAudience.team,
      ),
      TaskPoolItem(
        id: 'tp7',
        name: '各自完成一次深蹲訓練',
        sourceEvent: '訓練已結算',
        target: 1,
        audience: TaskAudience.team,
      ),
    ];

/// 教官測驗題庫。題目一律隨機抽取，不固定 ——
/// 固定題目會使題庫外流後測驗淪為背誦，重考也失去意義。
///
/// **2026-09-25 補足到規格要求的題數**（選擇題 20、簡答 3，見
/// `教官申請流程.md`）。在此之前只有 3 題選擇題 ＋ 2 題簡答 ——
/// 而作答畫面是一個拉桿，根本沒去抽題，所以從來沒人發現不夠。
///
/// **這批題目由 Claude 起草，使用者授權直接採用（2026-09-25）。**
/// 方向刻意集中在**安全、轉介時機與執業範圍** —— 那是教官做錯會傷到
/// 學徒的地方，也是不需要專業體適能認證就判斷得出對錯的地方。
/// 訓練處方的細節（組數次數的最適配置等）刻意不出題：那有學派差異，
/// 出成單選題只會考出「背過我們這套」而不是「懂不懂」。
///
/// ⚠️ **上線前建議由具備體適能專業的人覆核一次。** 這份題庫決定誰能
/// 帶別人訓練，而我不是那個專業。
List<ExamQuestion> buildExamBank() => [
      ExamQuestion(
        id: 'mc01',
        type: ExamQuestionType.multipleChoice,
        text: '學徒反映深蹲時膝蓋內夾，最先該處理什麼？',
        options: [
          '加重量讓他更專心',
          '檢查足踝活動度與臀中肌啟動',
          '改練腿推避開問題',
          '增加組數練到會為止',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc02',
        type: ExamQuestionType.multipleChoice,
        text: '學徒說訓練後兩天腰仍在痛，你應該？',
        options: [
          '請他熱身久一點再練',
          '請他就醫，該部位暫停訓練',
          '換成硬舉練強一點',
          '加強核心把腰撐住',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc03',
        type: ExamQuestionType.multipleChoice,
        text: '新手第一週的合理訓練頻率為何？',
        options: [
          '每天兩練趁有熱情',
          '每週 2–3 次',
          '每週 6 次快速見效',
          '看心情，想練才練',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc04',
        type: ExamQuestionType.multipleChoice,
        text: '學徒說「我想一個月瘦 10 公斤」，最適當的回應是？',
        options: [
          '幫他排每天兩次有氧',
          '說明合理速率約每週體重的 0.5–1%，並問清楚期限從哪來',
          '叫他先斷食一週',
          '答應他，先做再說',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc05',
        type: ExamQuestionType.multipleChoice,
        text: '漸進超負荷最合理的做法是？',
        options: [
          '每次訓練都加重',
          '在動作品質維持的前提下，逐步增加重量、次數或組數',
          '每週把重量加倍',
          '只增加組數，重量永遠不變',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc06',
        type: ExamQuestionType.multipleChoice,
        text: '學徒臥推時手腕會痛，第一步該檢查什麼？',
        options: [
          '直接換成啞鈴',
          '握法與手腕角度，以及槓是否壓在掌根',
          '叫他戴護腕就好',
          '減少到只做一組',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc07',
        type: ExamQuestionType.multipleChoice,
        text: '關於訓練前的熱身，下列何者最適當？',
        options: [
          '靜態伸展拉到極限',
          '以低強度有氧與該動作的漸進輕重量組暖身',
          '直接上工作重量',
          '熱身會浪費力氣，可略過',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc08',
        type: ExamQuestionType.multipleChoice,
        text: '學徒本週睡眠嚴重不足且精神不濟，你會？',
        options: [
          '照原課表練完',
          '降低強度或改為輕度活動，並了解原因',
          '加咖啡因硬上',
          '取消他的會員資格',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc09',
        type: ExamQuestionType.multipleChoice,
        text: '對於「局部瘦身」的說法，正確的是？',
        options: [
          '練腹肌就能瘦肚子',
          '脂肪減少的分布由全身能量赤字與個體差異決定，無法指定部位',
          '每天做 500 下捲腹最有效',
          '用束腹帶包住就會瘦該處',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc10',
        type: ExamQuestionType.multipleChoice,
        text: '學徒想在訓練中「練到力竭」每一組，最適當的建議是？',
        options: [
          '每組都力竭效果最好',
          '保留一定的預備次數，僅在少數組別接近力竭，以控制疲勞與風險',
          '力竭與否無所謂',
          '只有新手需要保留',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc11',
        type: ExamQuestionType.multipleChoice,
        text: '硬舉時學徒背部明顯圓弓，你應該？',
        options: [
          '請他撐住再多做幾下',
          '立即停止該組，降重量並重建脊椎中立的動作模式',
          '改成更重的重量逼他繃緊',
          '叫他繫腰帶就能解決',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc12',
        type: ExamQuestionType.multipleChoice,
        text: '關於休息時間，下列敘述何者較合理？',
        options: [
          '所有動作都休息 30 秒',
          '大重量多關節動作通常需要較長休息，孤立動作可較短',
          '休息越短效果越好',
          '休息時間不影響訓練品質',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc13',
        type: ExamQuestionType.multipleChoice,
        text: '學徒是高血壓患者並正在服藥，你應該？',
        options: [
          '照一般課表安排即可',
          '建議他先諮詢醫師，並避開憋氣用力等會使血壓驟升的方式',
          '讓他只做有氧就好',
          '拒絕指導所有慢性病患者',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc14',
        type: ExamQuestionType.multipleChoice,
        text: '對於延遲性肌肉痠痛（DOMS），正確的是？',
        options: [
          '沒有痠痛代表沒效',
          '痠痛程度不等於訓練成效，不該用它當作課表是否有效的指標',
          '越痛越有效',
          '痠痛時應該練更重',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc15',
        type: ExamQuestionType.multipleChoice,
        text: '學徒的訓練紀錄顯示每組都恰好 10 下、重量從不改變，你會？',
        options: [
          '稱讚他很穩定',
          '了解實際執行狀況，確認是否真的完成或只是照抄預帶值',
          '直接幫他加重',
          '忽略，紀錄不重要',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc16',
        type: ExamQuestionType.multipleChoice,
        text: '指導未成年學徒時，最適當的做法是？',
        options: [
          '與成人採用完全相同的課表',
          '以動作學習與安全為主，並取得監護人知情同意',
          '完全不能做任何重量訓練',
          '只做徒手訓練即可，不需其他考量',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc17',
        type: ExamQuestionType.multipleChoice,
        text: '學徒在訓練中感到頭暈、冒冷汗，你應該？',
        options: [
          '請他休息一下再繼續',
          '立即停止訓練，讓他坐下補充水分，必要時尋求醫療協助',
          '給他一顆糖繼續練',
          '請他自行決定',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc18',
        type: ExamQuestionType.multipleChoice,
        text: '關於伸展的時機，較適當的是？',
        options: [
          '訓練前做長時間靜態伸展',
          '訓練前以動態伸展為主，長時間靜態伸展安排在訓練後或獨立時段',
          '伸展完全沒有必要',
          '只在受傷後才需要伸展',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc19',
        type: ExamQuestionType.multipleChoice,
        text: '學徒連續四週都無法完成課表的目標次數，你應該？',
        options: [
          '要求他更努力',
          '檢視課表強度是否過高，並調整訓練量或恢復安排',
          '換一個更難的課表',
          '告訴他不適合健身',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'mc20',
        type: ExamQuestionType.multipleChoice,
        text: '作為教官，下列何者超出你的執業範圍？',
        options: [
          '示範動作與修正姿勢',
          '診斷傷病並開立治療處方',
          '安排訓練課表',
          '說明訓練原則',
        ],
        answerIndex: 1,
      ),
      ExamQuestion(
        id: 'sa01',
        type: ExamQuestionType.shortAnswer,
        text: '請說明你會如何為一位久坐上班族安排第一個月的課表，並說明理由。',
      ),
      ExamQuestion(
        id: 'sa02',
        type: ExamQuestionType.shortAnswer,
        text: '學徒要求你開立飲食與補劑處方，你會怎麼回應？',
      ),
      ExamQuestion(
        id: 'sa03',
        type: ExamQuestionType.shortAnswer,
        text: '學徒在你指導期間反覆抱怨同一部位不適，但檢查動作沒有明顯問題。請說明你接下來的處理步驟。',
      ),
    ];
