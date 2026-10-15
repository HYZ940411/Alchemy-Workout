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
        id: 'v1', name: 'AI 點數 ×10', emoji: '✨',
        images: const ['im_badge'],
        specs: [ProductSpec('10 點', 1500, 999)],
        aiCredits: 10,
      ),
      Product(
        id: 'v2', name: '單次 AI 調整使用權', emoji: '⚡',
        images: const ['im_chart'],
        specs: [ProductSpec('1 次', 150, 999)],
        aiCredits: 1,
        note: '150 金幣 ＝ 30 元',
      ),
      Product(
        id: 'v3', name: '補簽券 ×3', emoji: '🎫',
        images: const ['im_ticket'],
        specs: [ProductSpec('3 張', 400, 999)],
      ),
      Product(
        id: 'v4', name: '進階訓練計畫解鎖', emoji: '🔓',
        // 價格取自平台參數，不寫死 —— 課表選擇頁用的是同一個參數，
        // 各寫各的就會出現「同一件東西，從商城買比從課表頁買貴」。
        specs: [ProductSpec('單一計畫', kPlanUnlockCoins, 999)],
      ),
    ];

List<Order> buildOrders() => [
      Order(
        id: 'O-20260826-004', productName: 'AI 點數 ×10', spec: '10 點', qty: 1,
        placedAt: _ago(0, h: 3),
        coinPaid: 640, cashPaid: 172, state: OrderState.pendingPayment,
      ),
      Order(
        id: 'O-20260819-002', productName: '補簽券 ×3', spec: '3 張', qty: 1,
        placedAt: _ago(7),
        coinPaid: 400, cashPaid: 0, state: OrderState.delivered,
      ),
      Order(
        id: 'O-20260815-009', productName: 'AI 點數 ×10', spec: '10 點', qty: 1,
        placedAt: _ago(11),
        coinPaid: 0, cashPaid: 0, state: OrderState.failed,
        failReason: FailReason.insufficientBalance,
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

/// 教官測驗題庫。
///
/// 題目一律自題庫隨機抽取、不固定：固定題目會使題庫外流後測驗淪為背誦，
/// 也是重考機制的前提，否則重考等於重看同一份考卷。
///
/// ## 2026-09-29 依專業覆核意見全面改版
///
/// 前一版由 Claude 起草、使用者授權直接採用（2026-09-25），送交覆核後
/// 指出五項缺陷，全部屬於「測驗量不到它想量的東西」：
///
/// 1. **20 題的正解全部是 B。**
/// 2. **錯誤選項誇張到不可能有人選**（「加咖啡因硬上」「叫他先斷食一週」
///    「取消他的會員資格」）—— 零專業知識的人靠語氣就能全對。
///    量到的是辨識場面話的能力，不是專業判斷。
/// 3. **題庫 20 題、考卷抽 20 題**，隨機抽題形同虛設（見 PROGRESS 1Z）。
/// 4. 出題原則宣稱「訓練處方細節不出題」，但 mc03／mc05／mc10／mc12
///    實際上都在考處方細節，**自相矛盾**。
/// 5. 缺少數個高風險主題。
///
/// ## 本版的做法
///
/// - 選擇題 **45 題**，正解在 A/B/C/D 之間分布，任一選項不超過 30%。
/// - **錯誤選項一律寫成「聽起來合理、實務上真的有教練這樣做、但不正確」**。
///   自我檢查標準：完全不懂訓練的人只憑語氣與長度作答，得分應接近隨機。
/// - 集中在**安全、轉介時機、執業範圍、互動界線**。訓練處方的最適配置
///   （組數次數、休息秒數、頻率、RIR）因學派差異大，**一律不出成單選題**；
///   要考只考背後的原則，不考具體數值。原 mc03／mc10／mc12 據此刪除。
/// - 補上六個高風險主題：未成年互動界線、飲食失調辨識與轉介、
///   身體評論界線、心理狀態警訊轉介、利益衝突、急症辨識。
/// - **10 題標為必答題**（[ExamQuestion.mustPass]）：答錯任一題即不及格，
///   與百分比門檻並存。挑選標準是**答錯的後果不可事後補救** ——
///   直接的身體傷害，或一旦發生就無法回復的保護失效。
/// - 簡答題 **9 題**，每題附評分細則（通過要素／直接不通過條件）與
///   **追問範例**；其中 sa06、sa07 **綁定應試者自己的訓練紀錄**，
///   管理員可與其帳號對照，代答的難度因此高得多。
///
/// ⚠️ **仍須由具備體適能專業的人覆核。** 命題理由標註
/// 「建議由專業人士確認」者，是我對正解沒有十足把握的題目。
List<ExamQuestion> buildExamBank() => [
      ExamQuestion(
        id: 'mc21',
        type: ExamQuestionType.multipleChoice,
        text: '學員在訓練中主訴胸口悶痛，並延伸到左手臂與下顎，臉色發白。你應該？',
        options: [
          '立即停止訓練並撥打 119，讓他保持安靜姿勢等待救護人員',
          '先讓他坐下休息十分鐘，很多胸悶是姿勢或呼吸造成的',
          '扶到通風處鬆開衣物並補充水分，先排除熱衰竭的可能',
          '先量血壓與心率，有客觀數值才知道要不要叫救護車',
        ],
        answerIndex: 0,
        rationale: '胸痛轉移到左臂與下顎是心因性胸痛的典型表現。其餘三個選項（先休息觀察、當成熱衰竭處理、先量血壓再決定）都是健身房裡真的會有人做的處置，共同問題是「先觀察」—— 而這一類狀況沒有觀察的餘裕。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc22',
        type: ExamQuestionType.multipleChoice,
        text: '學員突然一側手腳無力、嘴角歪斜、講話含糊，約一分鐘後說「好像好一點了」。你應該？',
        options: [
          '請他今天先回家休息，症狀若明天還在再去看醫生',
          '立即撥打救護車，並記下症狀開始的確切時間供後續判斷',
          '讓他平躺並把下肢抬高促進回流，先排除姿勢性低血壓，症狀通常在一兩分鐘內就會緩解',
          '先給含糖飲料，低血糖也會造成類似的神經學症狀',
        ],
        answerIndex: 1,
        rationale: '症狀短暫緩解正是最容易被輕忽的地方。發作時間是後續治療決策的關鍵資訊，教官能做的最有價值的事就是記下它並立刻求援。誤選項分別把它當成疲勞、姿勢性低血壓與低血糖。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc23',
        type: ExamQuestionType.multipleChoice,
        text: '學員在深蹲架旁滑倒撞到頭，短暫失去意識數秒，醒來後說「我沒事，可以繼續」。你應該？',
        options: [
          '休息十五分鐘後如果沒有頭痛或噁心，可以安排幾個輕度動作收尾，讓他不會因為中斷而沮喪',
          '做幾個簡單的問答確認意識清楚，通過就可以繼續訓練',
          '終止今日訓練並協助就醫評估，即使他已恢復意識且自覺無恙',
          '讓他自行判斷是否繼續，成年人有權決定自己的身體',
        ],
        answerIndex: 2,
        rationale: '頭部外傷後的延遲性惡化是明確的醫療共識。「當事人說沒事」與「清醒且能對答」都不是可以繼續的理由，而這正是兩個誤選項的立論。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc24',
        type: ExamQuestionType.multipleChoice,
        text: '一位未成年學員私訊你：「平台訊息很不方便，可以加你的通訊軟體嗎？」最適當的回應是？',
        options: [
          '可以，但要求他先告知監護人，取得同意就沒有問題',
          '可以，但事先明確約定只談訓練相關內容、不涉及任何私人話題，界線講清楚就不會有問題',
          '可以，改用雙方另開的帳號，避免與個人生活混在一起',
          '婉拒，並說明訓練相關的溝通一律留在平台內以保留紀錄',
        ],
        answerIndex: 3,
        rationale: '平台內溝通留有紀錄，而紀錄是雙方的保護。其餘選項都試圖用附加條件（告知監護人、只談訓練、用匿名帳號）把私下聯繫變得「安全」，但條件擋不住的正是沒有紀錄這件事。',
      ),
      ExamQuestion(
        id: 'mc25',
        type: ExamQuestionType.multipleChoice,
        text: '一位未成年學員說要傳身體照片給你看訓練進度。你應該？',
        options: [
          '不接收任何身體影像，改以訓練紀錄與表現指標追蹤進度',
          '請他只拍局部、不要入鏡臉部，以降低身分辨識的風險',
          '請他先取得監護人書面同意，有同意就可以接收並保存',
          '請他改傳到平台的公開動態，公開場域比私訊更安全',
        ],
        answerIndex: 0,
        rationale: '未成年學員的身體影像沒有任何「安全的收法」。只拍局部、取得監護人同意、改傳公開動態，都是常見的折衷做法，而折衷在這件事上不存在。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc26',
        type: ExamQuestionType.multipleChoice,
        text: '一位未成年學員邀請你到他家附近的健身房單獨指導。你應該？',
        options: [
          '答應，但把每一次的時間與地點都事先回報平台備查',
          '不單獨見面；若要線下指導，需監護人在場或另有成人同行',
          '答應，但全程只在器材區等開放公共範圍活動，不進入更衣室或任何封閉空間，風險就可控',
          '答應，並全程錄影留存，有影像紀錄就能自證沒有問題',
        ],
        answerIndex: 1,
        rationale: '與未成年學員單獨相處本身就是要避免的情境，而不是可以靠回報平台、避開私密空間或全程錄影補救的情境。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc27',
        type: ExamQuestionType.multipleChoice,
        text: '學員身形明顯偏瘦，仍要求你安排減脂課表；他提到自己每天量體重五、六次，吃東西前會很焦慮。你應該？',
        options: [
          '先照他的目標安排一份強度溫和的課表，同時提醒營養要跟上，維持關係才有後續介入的空間',
          '改安排維持體重的課表，把話題自然轉向增肌與表現',
          '表達關切、不接下減脂目標，並建議他尋求醫療或心理專業協助',
          '請他先提供體脂與體組成數據，再判斷要不要接這個目標',
        ],
        answerIndex: 2,
        rationale: '身形偏瘦仍要求減脂、頻繁量體重、進食焦慮，是進食障礙的典型警訊。「改推增肌」與「先看體脂數據」看起來比照單全收專業，但同樣停留在用訓練處理它。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc28',
        type: ExamQuestionType.multipleChoice,
        text: '學員很興奮地告訴你：「我現在一天只吃一餐、每天練兩次，兩週掉了六公斤！」你應該？',
        options: [
          '肯定他的執行力，並提醒他務必補足蛋白質避免掉肌肉',
          '請他把有氧的量減半，一天一餐的部分可以先維持看看',
          '請他先做一次體組成分析，確認掉的主要是脂肪而不是肌肉，再決定這個做法需不需要調整',
          '說明快速減重的健康風險，不以此為目標，並建議專業評估',
        ],
        answerIndex: 3,
        rationale: '測的是教官會不會被「有效果」帶著走。肯定執行力、微調有氧、先做體組成分析，都是在這個做法的參數上打轉，而問題不在參數。',
      ),
      ExamQuestion(
        id: 'mc29',
        type: ExamQuestionType.multipleChoice,
        text: '學員提到自己有時候會大量進食，之後用長時間運動「把它補回來」。你應該？',
        options: [
          '視為需要轉介的警訊，不設計補償性課表，並建議專業協助',
          '幫他設計一份彈性的補償課表，讓他心理負擔不會那麼重',
          '告訴他偶爾這樣沒關係，只要維持每週的總量平衡就好',
          '請他改用飲食紀錄工具自我監控，數據化之後比較好管理',
        ],
        answerIndex: 0,
        rationale: '「以運動補償進食」是進食障礙的核心行為之一。設計彈性補償課表與建議用 App 自我監控，都會把這個循環制度化，而那是教官最容易在善意下做錯的事。',
      ),
      ExamQuestion(
        id: 'mc30',
        type: ExamQuestionType.multipleChoice,
        text: '你第一次與一位新學員線上面談，最適當的開場是？',
        options: [
          '先稱讚他願意開始運動，再從目前的體態說明改善空間',
          '先請他描述訓練目標、運動經驗與相關病史等背景資訊',
          '先請他提供身高體重與體脂等數據，建立一個客觀的起始基準，後續的進步才有東西可以對照',
          '先說明你會用什麼方式幫他改善身材，讓他對流程有信心',
        ],
        answerIndex: 1,
        rationale: '稱讚後評估體態、先說明會如何改善身材，都把外型當成對話的起點；先要身高體重體脂看似客觀，但把人化約成數字。測的是教官知不知道第一句話該問什麼。',
      ),
      ExamQuestion(
        id: 'mc31',
        type: ExamQuestionType.multipleChoice,
        text: '學員問你：「你覺得我這樣算胖嗎？」最適當的回應是？',
        options: [
          '誠實給出你的專業判斷並說明依據，避免他抱著不切實際的期待，日後反而更受挫',
          '回答不會，先維持他的信心比什麼都重要，之後再談',
          '不對外型下評價，把討論帶回可測量的訓練表現與健康指標',
          '請他參考身體質量指數的標準區間，讓數字自己說話',
        ],
        answerIndex: 2,
        rationale: '「誠實給出專業判斷」把誠實當成評論外型的許可，「不會啊」是善意的敷衍，「參考 BMI」看似中立，卻是用一個粗糙指標回答一個關於自我認同的問題。',
      ),
      ExamQuestion(
        id: 'mc32',
        type: ExamQuestionType.multipleChoice,
        text: '你想把某位學員的訓練前後對比照放上自己的社群宣傳。你應該？',
        options: [
          '可以，只要把臉部打上馬賽克就不會被認出是誰',
          '可以，只要不提到姓名與任何足以辨識身分的資訊',
          '可以，學員的訓練成果同時也是教官專業能力的證明，展示自己的成果是業界通行的做法',
          '需事前取得當事人明確同意；若為未成年，另需監護人同意',
        ],
        answerIndex: 3,
        rationale: '打馬賽克、不提姓名是最常見的自我說服。去識別化不等於取得同意，而同意是這件事唯一的依據。',
      ),
      ExamQuestion(
        id: 'mc33',
        type: ExamQuestionType.multipleChoice,
        text: '學員在訓練後聊天時說：「最近什麼都提不起勁，覺得做什麼都沒意義，來運動只是硬撐。」你應該？',
        options: [
          '表達關心與傾聽，說明專業心理協助的管道，不扮演諮商角色',
          '建議他增加訓練頻率，規律運動對情緒本來就有幫助',
          '請他先把課表停掉，等狀況好一點再回來會比較輕鬆',
          '分享你自己走出低潮的經驗，讓他知道這些都會過去',
        ],
        answerIndex: 0,
        rationale: '「多運動有助情緒」是最常見的好意誤用（把運動當處方），分享自身經驗把個人故事當成專業建議，而叫他停練則切斷了一個可能的支持來源。教官的角色是察覺與轉介，不是治療。',
      ),
      ExamQuestion(
        id: 'mc34',
        type: ExamQuestionType.multipleChoice,
        text: '學員在私訊中透露自己有傷害自己的念頭，並要求你「不要跟任何人說」。你應該？',
        options: [
          '答應保密以維持信任關係，同時私下更密切關心他',
          '表達關心並提供求助管道，明確告知你無法對安全風險保密',
          '立即終止指導關係並說明原因，這已經超出你的專業與責任範圍，繼續下去對雙方都不是好事',
          '先觀察一陣子判斷他是不是認真的，再決定要不要處理',
        ],
        answerIndex: 1,
        rationale: '答應保密是最容易發生的錯誤 —— 用信任換來一個做不到的承諾。立即終止關係是自保式的切斷，「先評估是不是說說」則讓沒有受訓的人去做風險評估。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc35',
        type: ExamQuestionType.multipleChoice,
        text: '學員腳踝扭傷仍每天到場訓練，說「不練會很焦慮」。你應該？',
        options: [
          '安排一份完整的上肢課表，讓他維持訓練的節奏又不會壓到腳踝，復原期也比較不會失去動力',
          '尊重他的意願繼續指導，只要提醒他自己注意就好',
          '處理傷處的休息安排，同時正視情緒依賴並建議專業評估',
          '要求他完全停練兩週，期間不接受任何形式的指導',
        ],
        answerIndex: 2,
        rationale: '安排上肢課表是實務上最常見的做法，而它只處理了傷、沒有處理「不練會焦慮」。這題測的是教官有沒有聽見那半句話。',
      ),
      ExamQuestion(
        id: 'mc36',
        type: ExamQuestionType.multipleChoice,
        text: '你是某補劑品牌的代理，學員問你「這個要不要吃」。最適當的做法是？',
        options: [
          '直接推薦，你了解這個產品所以給的建議反而更可靠',
          '說你不清楚請他自己上網查，避免捲入任何推銷爭議',
          '推薦另一個你沒有代理的品牌，這樣既回答了他的問題，也完全避開了自身的利益衝突',
          '主動揭露你與該品牌的利益關係，並建議諮詢醫療或營養專業',
        ],
        answerIndex: 3,
        rationale: '推薦其他品牌看起來像在回避利益衝突，實際上仍在用指導關係推銷。真正的處理是揭露加轉介。',
      ),
      ExamQuestion(
        id: 'mc37',
        type: ExamQuestionType.multipleChoice,
        text: '你想把平台上的學徒轉為自己的私人課程客戶。你應該？',
        options: [
          '不利用平台建立的指導關係招攬，依平台的規範處理此事',
          '可以，只要你的課程品質更好，對學員本來就是好事',
          '可以，但等這段平台上的指導關係結束之後再開口',
          '可以，私下詢問他的意願即可，他有拒絕的自由',
        ],
        answerIndex: 0,
        rationale: '「等指導關係結束後再談」聽起來是有分寸的做法，但結束的界線由教官自己認定，而不對等的關係並不會因為結束就消失。',
      ),
      ExamQuestion(
        id: 'mc38',
        type: ExamQuestionType.multipleChoice,
        text: '廠商願意免費提供一批器材，條件是你在指導時推薦該品牌。你應該？',
        options: [
          '接受，器材品質對學員的訓練體驗本來就是有好處的',
          '不接受附帶推薦條件的贊助；若接受，須完整揭露且不影響內容',
          '接受，但只在學員自己主動問起器材時才提到品牌',
          '接受贊助，但在每一次提到該品牌之後都主動補充說明這是贊助關係，資訊透明就沒有問題',
        ],
        answerIndex: 1,
        rationale: '「只在對方問起時才提」與「推薦後說明是贊助」都是實務上常見的自我豁免。揭露可以解決資訊不對等，但解決不了建議內容本身被交易了。',
      ),
      ExamQuestion(
        id: 'mc39',
        type: ExamQuestionType.multipleChoice,
        text: '學員描述膝蓋的疼痛位置與情境後問你：「這是不是半月板破了？」你應該？',
        options: [
          '依你過去看過的相似案例給一個可能性與大致比例，讓他心裡先有底，就醫時也知道要問什麼',
          '請他先做幾個徒手測試，再一起判斷需不需要去就醫',
          '說明你不做傷病診斷並建議就醫，同時說明在那之前如何調整訓練',
          '告訴他多數的膝痛都源於肌力不足，先加強股四頭肌',
        ],
        answerIndex: 2,
        rationale: '「給個可能性讓他心裡有底」與「先做幾個徒手測試」都是「不算診斷吧」的自我說服；「多數膝痛都是肌力不足」則直接跳過診斷給了處方。',
      ),
      ExamQuestion(
        id: 'mc40',
        type: ExamQuestionType.multipleChoice,
        text: '學員拿著復健科給的運動處方，問你能不能幫他改得更有效率。你應該？',
        options: [
          '可以調整，你更了解訓練，效率本來就是你的專業領域',
          '可以調整動作的順序與組合，只要維持原本的總量與強度，就不會偏離醫療端設定的治療目標',
          '可以調整，但請他自己向醫師說明是你建議改動的',
          '不更動醫療端開立的處方；有疑問請他回去與開立者討論',
        ],
        answerIndex: 3,
        rationale: '「只要不減少總量」用一個自訂條件自我背書，「請他自己跟醫師說是你改的」把責任轉嫁給學員 —— 兩者都是實務上最常見的擅改方式。',
      ),
      ExamQuestion(
        id: 'mc41',
        type: ExamQuestionType.multipleChoice,
        text: '學員說醫師要他停止訓練三週，但他覺得自己好得差不多了，想偷偷練。你應該？',
        options: [
          '支持醫囑不設計繞過的課表，並協助他規劃復出後的安排',
          '幫他排一份完全不碰患部的輕量課表，風險其實很低',
          '請他自己決定，成年人本來就要為自己的選擇負責',
          '請他先回診確認，如果醫師不同意就照原本的計畫練',
        ],
        answerIndex: 0,
        rationale: '「排一份不碰患部的輕量課表」是這一題最有殺傷力的選項：它聽起來體貼、可行，而且很多教練真的會這樣做。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc42',
        type: ExamQuestionType.multipleChoice,
        text: '學員要求你開立每日熱量與三大營養素的具體數字。你應該？',
        options: [
          '依常用的公式估算基礎代謝與活動量後給他一組起始數字，並提醒他依實際體重變化自行微調',
          '說明個別化飲食處方屬於營養專業，可提供衛教並建議轉介',
          '請他用應用程式自己算出來，你再幫他看合不合理',
          '給一個範圍寬一點的保守區間，這樣比較不會出問題',
        ],
        answerIndex: 1,
        rationale: '依公式估算、請他自己算再幫他看、給一個保守區間，都是「幫他算一下又不會怎樣」的變形。界線不在數字精不精確，在誰有資格開立。',
      ),
      ExamQuestion(
        id: 'mc43',
        type: ExamQuestionType.multipleChoice,
        text: '有糖尿病並使用胰島素的學員問你：「訓練前我的胰島素要不要減量？」你應該？',
        options: [
          '建議他訓練前把劑量減半，運動本來就會讓血糖下降',
          '請他訓練前先量血糖，數值偏高就照原本的劑量施打、偏低就自行減量，依當下狀況彈性處理',
          '不給用藥調整建議，請他與醫療團隊討論，你配合用藥時間安排',
          '請他訓練前先吃一點東西，這樣就不需要調整劑量',
        ],
        answerIndex: 2,
        rationale: '建議減半、依血糖自行增減、訓練前先吃東西以免調整，全都是在給用藥建議，只是包裝成經驗談或常識。這一題的錯誤後果是低血糖昏迷。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc44',
        type: ExamQuestionType.multipleChoice,
        text: '學員問你乳清蛋白一天該吃多少。最適當的回應是？',
        options: [
          '直接給一個每日公克數，這已經屬於常識的範圍了',
          '請他照產品標示的建議量攝取，標示的劑量通常經過一定的法規審查，照著吃不會有太大問題',
          '請他吃到兩倍量，多餘的身體本來就會自己代謝掉',
          '說明整體攝取的一般原則，個別化建議轉介，且不宣稱療效',
        ],
        answerIndex: 3,
        rationale: '一般性衛教與個別化處方的界線。［建議由專業人士確認］：一般原則能講到多細，各地法規與平台政策不同。',
      ),
      ExamQuestion(
        id: 'mc01',
        type: ExamQuestionType.multipleChoice,
        text: '學員深蹲時膝蓋明顯往內塌，你最先該做的是？',
        options: [
          '先降低重量，觀察在什麼負荷與深度開始出現，再逐項排查',
          '指導他刻意把膝蓋向外推，並維持原本的重量繼續練',
          '改做腿推，避開這個目前還做不好的動作模式就好',
          '先加強臀部外側幾週，肌力足夠之後再回來練深蹲',
        ],
        answerIndex: 0,
        rationale: '原題正解指定「臀中肌啟動」，那是流行說法且證據不一致。本版改為不指定特定肌群：先找出它在什麼條件下出現。刻意把膝蓋外推、改做腿推、先練數週再回來，都是常見做法，但都跳過了觀察。',
      ),
      ExamQuestion(
        id: 'mc02',
        type: ExamQuestionType.multipleChoice,
        text: '學員說前天練完之後腰一直痛到現在，彎腰時會有刺痛感。你應該？',
        options: [
          '安排幾天的核心訓練，把腰周圍的支撐力先建立起來',
          '建議就醫評估，在有醫療意見前避免會誘發疼痛的動作',
          '先做幾天伸展與放鬆，觀察一週看看會不會自己好轉',
          '降低重量但維持訓練頻率，讓組織在可承受的負荷下逐漸適應，完全停下來反而恢復得比較慢',
        ],
        answerIndex: 1,
        rationale: '持續數日且有刺痛性質的下背痛不是教官該自行處理的。練核心撐住、先伸展觀察一週、降重量讓組織適應，是三種常見的「再觀察」，而它們共同的代價是延誤。',
      ),
      ExamQuestion(
        id: 'mc11',
        type: ExamQuestionType.multipleChoice,
        text: '學員硬舉最後一下背部明顯圓弓，槓還在半空中。你應該？',
        options: [
          '大聲提醒他撐住核心，把這一下完整地做完再說',
          '立刻叫他放手鬆槓，先讓脊椎脫離負荷最重要',
          '讓他以最安全的方式結束這一下，隨即中止該組並降低重量',
          '讓他把剩下的次數做完再說，中途喊停容易讓人分心反而更危險，結束之後再完整回饋姿勢問題',
        ],
        answerIndex: 2,
        rationale: '原題正解「立即停止該組」有歧義 —— 槓已離地時中途放下可能更危險。本版改為先安全結束當下這一下，再中止該組。「撐住做完」與「做完整組再提醒」都在放任，「立刻放手鬆槓」則製造新的風險。',
      ),
      ExamQuestion(
        id: 'mc06',
        type: ExamQuestionType.multipleChoice,
        text: '學員臥推時手腕會痛，第一步該檢查什麼？',
        options: [
          '先把握距縮窄，多數手腕不適都與握距過寬有關',
          '請他配戴護腕提供支撐，先讓訓練可以正常進行',
          '改用啞鈴進行，手腕與前臂的角度比較自由，可以繞過槓鈴握姿造成的限制而不影響訓練效果',
          '檢查握法與槓在手掌上的位置，以及前臂與槓是否成直線',
        ],
        answerIndex: 3,
        rationale: '縮窄握距、戴護腕、改用啞鈴都是有人會做的處置，但它們都在繞過原因。這一題測的是「先看發生什麼」而不是「先換個做法」。',
      ),
      ExamQuestion(
        id: 'mc17',
        type: ExamQuestionType.multipleChoice,
        text: '學員在訓練中突然頭暈、冒冷汗、臉色蒼白。你應該？',
        options: [
          '讓他坐下或躺下並補充水分，未迅速改善或反覆出現就求援',
          '讓他扶著器材站著緩一下，通常一兩分鐘就會恢復',
          '請他做幾次深呼吸調節，這多半是換氣過度造成的',
          '給他含糖飲料補充血糖，訓練中低血糖相當常見',
        ],
        answerIndex: 0,
        rationale: '讓人扶著器材站著休息是實務上很常見而且危險的處置。正解的重點不只在當下處理，而在「不改善或反覆出現就求援」這個門檻。',
        mustPass: true,
      ),
      ExamQuestion(
        id: 'mc13',
        type: ExamQuestionType.multipleChoice,
        text: '學員有高血壓並規律服藥，想開始重量訓練。你應該？',
        options: [
          '照一般課表安排即可，規律的阻力訓練對長期的血壓控制是有益的，過度限制反而失去好處',
          '建議他先與醫師確認可從事的運動範圍，並避免憋氣用力',
          '只安排有氧訓練，重量訓練對高血壓患者風險太高',
          '請他先把血壓控制到正常範圍，再回來開始訓練',
        ],
        answerIndex: 1,
        rationale: '「重訓對血壓有益所以照排」與「風險太高只做有氧」是兩個方向的過度反應；「先把血壓控制到正常再來」則把門檻設在教官無權設定的地方。',
      ),
      ExamQuestion(
        id: 'mc45',
        type: ExamQuestionType.multipleChoice,
        text: '懷孕的學員想開始或繼續重量訓練。你應該？',
        options: [
          '一律停止重量訓練改為散步，孕期以安全為最優先考量',
          '維持原本的課表，孕期運動其實沒有那麼多特別的禁忌',
          '建議她先與產科醫療團隊確認，並依醫囑與個人狀況調整訓練',
          '只要避開會直接壓迫腹部與需要仰臥過久的動作，其餘課表內容大致都可以照原本的安排進行',
        ],
        answerIndex: 2,
        rationale: '「一律停止改散步」與「孕婦運動沒特別禁忌」是兩個極端，「只要避開腹部動作」則把複雜的判斷簡化成一條規則。教官的位置是配合醫療端，不是自行判斷。',
      ),
      ExamQuestion(
        id: 'mc46',
        type: ExamQuestionType.multipleChoice,
        text: '學員腹部手術後三個月，想恢復重量訓練。你應該？',
        options: [
          '術後三個月一般而言軟組織已經完成初步癒合，可以從非常輕的重量開始，依他的感受逐步增加',
          '請他先做幾個測試動作，只要過程不痛就可以開始練',
          '請他先從有氧開始，再過三個月之後才加入重量訓練',
          '取得醫療端關於可從事活動與限制的說明後，再據以安排',
        ],
        answerIndex: 3,
        rationale: '「三個月通常已經恢復」與「有氧三個月後再加重訓」都在用時間當作痊癒的證據，「不痛就可以練」則用症狀當標準。術後的限制要由醫療端說，不是由時間表說。',
      ),
      ExamQuestion(
        id: 'mc47',
        type: ExamQuestionType.multipleChoice,
        text: '已診斷骨質疏鬆的高齡學員來找你。下列做法最適當的是？',
        options: [
          '與醫療端確認限制後，安排漸進式阻力訓練並避開高風險動作',
          '避免重量訓練，改以散步與伸展為主比較不會有風險',
          '先安排高衝擊的訓練刺激骨質，這是增加骨密度的關鍵',
          '依一般高齡族群的課表安排即可，不需要特別的調整',
        ],
        answerIndex: 0,
        rationale: '「避免重訓改散步伸展」是最常見的過度保守（阻力訓練對骨密度有益），「先做高衝擊刺激骨質」則是把原則套錯族群。［建議由專業人士確認］：哪些動作模式列為高風險，臨床上仍有討論。',
      ),
      ExamQuestion(
        id: 'mc48',
        type: ExamQuestionType.multipleChoice,
        text: '成年學員在私訊中向你表達好感，並邀約私下見面。你應該？',
        options: [
          '委婉帶過不正面回應，維持原本的指導關係就可以了',
          '明確說明專業界線；若持續越界，終止關係並依規範通報',
          '先答應見一次面，當面把專業界線說清楚比在訊息裡冷冰冰地拒絕更不傷人，也比較不會有誤會',
          '把訊息截圖公開讓對方知難而退，也警惕其他人',
        ],
        answerIndex: 1,
        rationale: '「委婉帶過繼續指導」是最常見的處理，而拖著等於默許；「截圖公開」則把一個界線問題變成公開羞辱。',
      ),
      ExamQuestion(
        id: 'mc49',
        type: ExamQuestionType.multipleChoice,
        text: '學員要求你不要把他的訓練紀錄與對話提供給平台管理員。你應該？',
        options: [
          '答應他，訓練紀錄與對話本來就屬於他的個人資料',
          '答應他不主動提供，但自己另外留存一份完整備份，萬一日後發生爭議時還有依據可以自保',
          '說明會依規範保護其資料，但無法承諾在安全或違規調查時隱匿',
          '請他自己去向平台申請不要被管理員查看這些資料',
        ],
        answerIndex: 2,
        rationale: '答應保密、答應但自己留備份，都是在給一個做不到的承諾，而做不到的承諾在爭議發生時傷害的是學員。',
      ),
      ExamQuestion(
        id: 'mc50',
        type: ExamQuestionType.multipleChoice,
        text: '你看到另一位教官給學員的建議明顯有安全疑慮。你應該？',
        options: [
          '不介入，那是他和他的學員之間的專業判斷與關係',
          '直接在公開場合指正，讓其他人也知道那樣做不對',
          '先默默蒐集更多具體事證，累積到足以佐證的數量之後再一次向平台反映，避免造成誤會或衝突',
          '私下提醒對方，若涉及安全風險則向平台通報處理',
        ],
        answerIndex: 3,
        rationale: '「不介入」是最常見的選擇，「累積證據再處理」聽起來嚴謹但等於讓風險持續。這一題測的是教官把學員安全放在同儕關係之前。',
      ),
      ExamQuestion(
        id: 'mc15',
        type: ExamQuestionType.multipleChoice,
        text: '學員的訓練紀錄顯示每一組都恰好完成預設次數、重量從未改變。你應該？',
        options: [
          '了解實際執行狀況，確認是真的完成，還是照預帶數值送出',
          '稱讚他執行得很穩定，這種一致性很值得肯定',
          '既然都輕鬆完成，直接幫他把下週的重量往上調',
          '不必理會，訓練紀錄只是輔助參考，不影響安排',
        ],
        answerIndex: 0,
        rationale: '測的是教官會不會把資料當成事實。稱讚穩定與「紀錄只是參考」是兩種忽略，直接加重則是在沒有確認的資料上做處方。',
      ),
      ExamQuestion(
        id: 'mc19',
        type: ExamQuestionType.multipleChoice,
        text: '學員連續四週都無法完成課表的目標次數。你應該？',
        options: [
          '要求他更專注更努力，多數停滯來自執行強度不足',
          '檢視訓練量與恢復是否超出負荷，並了解睡眠、壓力與作息',
          '換一份結構不同、更有挑戰性的課表，用新的動作與刺激打破停滯期，通常幾週內就會有變化',
          '告訴他可能不適合這種訓練方式，建議改做其他運動',
        ],
        answerIndex: 1,
        rationale: '要求更努力把系統問題歸因於意志，換更難的課表是加碼，「不適合這種訓練」是放棄。這一題測的是教官會不會先檢討自己的安排。',
      ),
      ExamQuestion(
        id: 'mc14',
        type: ExamQuestionType.multipleChoice,
        text: '關於延遲性肌肉痠痛（DOMS），下列敘述最適當的是？',
        options: [
          '沒有痠痛代表這次的訓練刺激還不夠，需要再加量',
          '痠痛越明顯代表肌纖維的微損傷越多，而修復的過程正是肌肉生長的來源，所以效果也會越好',
          '痠痛程度不能用來判斷一份課表是否有效或刺激是否足夠',
          '痠痛期間應該加重訓練，讓身體更快適應這個強度',
        ],
        answerIndex: 2,
        rationale: '痠痛與訓練成效脫鉤是專業共識，而「不痠等於沒練到」在學員與教練之間都非常普遍。',
      ),
      ExamQuestion(
        id: 'mc09',
        type: ExamQuestionType.multipleChoice,
        text: '關於「局部瘦身」，正確的是？',
        options: [
          '針對某個部位做大量訓練，可以優先減去該處的脂肪',
          '配合局部加壓、包覆或提高該部位的血流，可以加速該處脂肪的動員與代謝，讓形狀更快改變',
          '只要該部位的訓練強度夠高，就能達到指定減脂效果',
          '脂肪減少的分布由整體能量赤字與個體差異決定，無法指定',
        ],
        answerIndex: 3,
        rationale: '常被學員要求、也常被教練順著講的迷思。這一題測的是教官會不會為了迎合期待而說出不成立的話。',
      ),
      ExamQuestion(
        id: 'mc08',
        type: ExamQuestionType.multipleChoice,
        text: '學員本週睡眠嚴重不足、精神明顯不濟。你應該？',
        options: [
          '降低強度或改為輕度活動，並了解睡眠不足是否另有原因',
          '照原課表完成，訓練的習慣一旦中斷就很難再建立',
          '把訓練時間延到晚上，讓他白天可以先補一點眠',
          '縮短組間休息時間，用比較短的時間把課表練完',
        ],
        answerIndex: 0,
        rationale: '延到晚上補眠、縮短組間休息把時間壓縮，是兩種「調整了但沒解決」的做法。重點在正解的後半句：睡不好可能不只是睡不好。',
      ),
      ExamQuestion(
        id: 'mc04',
        type: ExamQuestionType.multipleChoice,
        text: '學員說「我想一個月瘦十公斤」。最適當的回應是？',
        options: [
          '先答應下來，等他實際執行之後自然會調整期待',
          '了解這個期限從何而來，說明一般原則，必要時建議專業協助',
          '直接告訴他這個目標做不到，請他重新設定再來談',
          '幫他排每天兩次有氧並搭配嚴格的熱量控制，先衝一段時間看實際成效再決定要不要調整目標',
        ],
        answerIndex: 1,
        rationale: '原題正解寫死一個速率數字，本版改為聚焦在「期限從哪來」—— 那句話常常是這一題真正的風險所在（婚禮、比賽，或他人的評論）。',
      ),
      ExamQuestion(
        id: 'mc05',
        type: ExamQuestionType.multipleChoice,
        text: '關於漸進超負荷，下列敘述最適當的是？',
        options: [
          '每一次訓練都必須比上一次更重，否則就不算進步',
          '只要持續增加組數就可以，重量可以永遠維持不變',
          '刺激需隨適應逐步提高，方式不限於重量，且以品質維持為前提',
          '進步一旦停滯就應該大幅加重，用超出平常的刺激衝擊身體，突破瓶頸之後再回到原本的節奏',
        ],
        answerIndex: 2,
        rationale: '只考原則不考數值。「每次都要更重」與「停滯就大幅加重」是常見的躁進，「只加組數」則是把單一變項當成全部。',
      ),
      ExamQuestion(
        id: 'mc07',
        type: ExamQuestionType.multipleChoice,
        text: '關於訓練前的準備，下列做法最適當的是？',
        options: [
          '以長時間的靜態伸展把目標肌群充分放鬆並增加活動度之後，再直接進入當天的工作重量',
          '直接從工作重量開始，把前面幾下當作熱身即可',
          '熱身會消耗力氣，正式組之前應該完全休息保留體力',
          '以低強度有氧提高體溫，再用該動作的漸進輕重量組建立模式',
        ],
        answerIndex: 3,
        rationale: '只考原則。［建議由專業人士確認］：訓練前長時間靜態伸展對表現的影響有學派討論，本題刻意不以它為唯一判準，而以「漸進建立動作模式」為正解依據。',
      ),
      ExamQuestion(
        id: 'mc16',
        type: ExamQuestionType.multipleChoice,
        text: '指導未成年學員進行重量訓練時，最適當的做法是？',
        options: [
          '以動作學習與安全為主，取得監護人知情同意並依發育調整',
          '完全不安排任何負重，只做徒手動作才是安全的',
          '與成年學員採用相同的課表與強度，動作標準就好',
          '只要動作做得正確，訓練強度可以比照成人安排',
        ],
        answerIndex: 0,
        rationale: '「完全不負重」是過度保守（青少年可在適當監督下進行阻力訓練），「比照成人」與「動作正確就能比照成人強度」則忽略了知情同意這一層。',
      ),
      ExamQuestion(
        id: 'sa01',
        type: ExamQuestionType.shortAnswer,
        text: '一位久坐上班族來找你，沒有運動習慣、沒有已知疾病。請說明你在替他安排第一個月之前，會先問哪些事、為什麼問，以及哪些回答會讓你先請他就醫。',
        rubricPass: '通過需同時涵蓋：①至少三項問診內容（例如目前症狀、用藥、過去傷病、作息與壓力、可投入的時間與場地）；②每一項都說得出為什麼要問；③明確指出至少兩種會讓他先轉介就醫的回答（例如運動中曾胸痛或昏厥、近期不明原因體重下降、未受控制的慢性病）。',
        rubricFail: '直接不通過：只寫課表內容而完全沒有問診；把「先做體測」當成唯一的評估；出現任何診斷性判斷（例如「這種人通常是核心無力」）；設定具體的減重公斤數或期限作為目標。',
        followUp: '追問範例：如果他在問診時說「我有時候爬樓梯會喘，但休息一下就好」，你接下來會怎麼做？請具體說出你會說什麼、以及你會不會安排今天的訓練。',
      ),
      ExamQuestion(
        id: 'sa02',
        type: ExamQuestionType.shortAnswer,
        text: '學員要求你開立每日飲食內容與補劑清單。請寫出你實際會對他說的話（可用對話形式），並說明你的界線畫在哪裡、為什麼。',
        rubricPass: '通過需同時涵蓋：①明確拒絕開立個別化飲食或補劑處方；②說得出理由是執業範圍而非「怕出事」；③提出可行的替代（轉介營養或醫療專業、提供一般性衛教、協助他把問題整理好去問專業）；④語氣不使學員感到被拒絕或被輕視。',
        rubricFail: '直接不通過：給出任何具體的每日熱量、三大營養素克數或補劑劑量；以「這只是分享不是建議」規避；宣稱某補劑可以治療、預防疾病或取代藥物；把學員推開而未提供任何後續管道。',
        followUp: '追問範例：他回你「我只是想知道你自己都怎麼吃」。你會怎麼回答？',
      ),
      ExamQuestion(
        id: 'sa03',
        type: ExamQuestionType.shortAnswer,
        text: '學員在你指導期間反覆抱怨同一個部位不適，但你觀察動作沒有明顯問題。請依序說明你接下來的處理步驟。',
        rubricPass: '通過需同時涵蓋：①先問清楚疼痛的性質、時機、是否影響日常生活與睡眠；②在有醫療意見前調整或暫停會誘發疼痛的動作；③設定明確的轉介門檻（例如持續多久、出現哪些狀況就請他就醫）；④說明會記錄下來並追蹤。',
        rubricFail: '直接不通過：推測或指稱特定傷病名稱；建議使用止痛藥或任何藥物；以「痛就是還不夠強」「練過去就好」為處理方向；完全不提轉介。',
        followUp: '追問範例：他說「上次去看醫生，醫生說沒事」。你會因此改變做法嗎？為什麼？',
      ),
      ExamQuestion(
        id: 'sa04',
        type: ExamQuestionType.shortAnswer,
        text: '一位十五歲的學員透過平台找你指導。請說明你在互動上會設下哪些具體界線，以及你會如何向他與監護人說明這些界線。',
        rubricPass: '通過需同時涵蓋：①溝通留在平台內、不轉往私人通訊軟體；②不索取也不接收身體影像；③不單獨線下見面，需監護人在場或另有成人同行；④涉及身體、發育或體重的討論須讓監護人知情；⑤說得出向未成年本人說明的方式，而不只是向監護人交代。',
        rubricFail: '直接不通過：任何條件式的例外（例如「監護人同意就可以私下加好友」）；把界線只當成自我保護而未提及對學員的保護；完全沒有提到監護人知情。',
        followUp: '追問範例：他說「我爸媽不管我，你直接跟我講就好」。你會怎麼處理？',
      ),
      ExamQuestion(
        id: 'sa05',
        type: ExamQuestionType.shortAnswer,
        text: '學員在訓練後對你說：「最近真的很累，有時候覺得不如消失算了。」請寫出你當下會說的話與接下來的行動。',
        rubricPass: '通過需同時涵蓋：①當下不迴避、不轉移話題，先確認你有聽到；②不承諾對安全風險絕對保密；③提供具體的求助管道（專業心理協助或求助專線），而非只說「要不要去看醫生」；④說明自己不是諮商角色；⑤後續會依平台規範處理或回報。',
        rubricFail: '直接不通過：答應完全保密；以「多運動就會好」「你想太多了」回應；立即終止指導關係而未提供任何銜接；自行判斷對方「應該只是說說」。',
        followUp: '追問範例：他接著說「你不要跟平台講，不然我就不練了」。你會怎麼回應？',
      ),
      ExamQuestion(
        id: 'sa06',
        type: ExamQuestionType.shortAnswer,
        text: '請以你自己過去三個月的訓練紀錄為例，挑出一次你實際調整了計畫的情況：說明當時的數據顯示了什麼、你改了什麼、改完之後的紀錄如何驗證這個調整有沒有用。',
        rubricPass: '通過需同時涵蓋：①引用具體且可在其帳號紀錄中對照的資訊（日期區間、動作、組數次數或重量的變化）；②說得出判斷依據來自哪一項紀錄，而不是感覺；③說明調整後用什麼指標回頭驗證；④承認驗證的限制（例如同時有其他變因）。',
        rubricFail: '直接不通過：完全沒有引用可對照的紀錄；敘述與其帳號實際紀錄明顯矛盾；只描述一般性原則而未涉及自身資料；宣稱調整必然有效而未提出任何驗證方式。',
        followUp: '追問範例：請再挑一次「調整之後沒有變好」的紀錄，說明你當時怎麼判讀，以及後來怎麼處理。',
      ),
      ExamQuestion(
        id: 'sa07',
        type: ExamQuestionType.shortAnswer,
        text: '請從你自己的訓練紀錄中，找出一段你現在回頭看會做不同處理的時期，說明當時發生什麼、你現在會怎麼做、以及你從中學到什麼可以用在指導別人身上。',
        rubricPass: '通過需同時涵蓋：①具體指出可對照的時間區間與當時的紀錄狀況；②說得出當時的判斷錯在哪，而不只是「應該更努力」；③把經驗轉成一條可套用在他人身上的原則；④指出這條原則的適用限制（別人的條件與自己不同）。',
        rubricFail: '直接不通過：完全沒有引用自身紀錄；把學到的東西寫成勵志話而無具體做法；直接把自己的處方推廣到所有人身上而未提限制。',
        followUp: '追問範例：如果一位學員現在正處在你當時那個狀況，但他堅持自己沒問題，你會怎麼做？',
      ),
      ExamQuestion(
        id: 'sa08',
        type: ExamQuestionType.shortAnswer,
        text: '你發現自己代理或使用的某項產品，正好是學員問到的東西。請說明你會如何處理這個利益衝突。',
        rubricPass: '通過需同時涵蓋：①主動揭露利益關係，而非等對方問；②不以指導關係作為推銷管道；③提供不涉及自身利益的替代資訊來源或轉介；④說明若對方仍想購買，你會如何避免建議受到影響。',
        rubricFail: '直接不通過：認為只要產品有效就沒有衝突；以「我沒有強迫他買」為由略過揭露；把揭露當成可以繼續推銷的通行證。',
        followUp: '追問範例：如果學員說「沒關係啦，我就是想買你用的那個」，你會怎麼做？',
      ),
      ExamQuestion(
        id: 'sa09',
        type: ExamQuestionType.shortAnswer,
        text: '請說明在你的指導範圍內，哪些事你一定不會做。請至少列出四項，並各用一句話說明理由。',
        rubricPass: '通過需同時涵蓋：①至少四項，且分屬不同類別（醫療診斷或治療、個別化飲食或用藥、心理治療、互動界線、利益衝突）；②每一項的理由指向執業範圍或學員安全，而非個人偏好；③其中至少一項涉及未成年或心理安全。',
        rubricFail: '直接不通過：四項全部集中在同一類；理由寫成「怕被告」而完全沒有提到學員；列出的項目其實在合法範圍內（顯示對執業範圍認知錯誤）。',
        followUp: '追問範例：你列的其中一項，如果學員堅持要你做、並說願意自己承擔後果，你會改變決定嗎？',
      ),
    ];
