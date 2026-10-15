import 'platform_config.dart';

// --- 商品與訂單 ---

/// 金幣對法幣比率（1 元 ＝ N 金幣）。
int get kCoinsPerNtd => platformConfig.i('commerce', 'coinsPerNtd');

/// 進階訓練計畫的解鎖金幣價格。**統一定價，不逐計畫區分**
/// （〈虛擬商品購買流程〉2026-08-20 定案：600 金幣 ＝ 120 元）。
/// 為平台級可調參數；調整不追溯已購買的訂單。
int get kPlanUnlockCoins => platformConfig.i('commerce', 'planUnlockCoins');

/// 補差額試算：金幣不足 [shortCoins] 時所需支付的法幣金額。
int cashForShortfall(int shortCoins) =>
    shortCoins <= 0 ? 0 : (shortCoins / kCoinsPerNtd).ceil();

class ProductSpec {
  final String name;
  final int coinPrice;

  /// 可售庫存（消耗品類虛擬商品）。確認購買時扣減，取消或失敗時回補。
  /// 權限解鎖類商品不適用庫存（〈虛擬商品購買流程〉）。
  int stock;
  ProductSpec(this.name, this.coinPrice, this.stock);
  bool get inStock => stock > 0;
}

/// 商城商品。**只有虛擬商品**：2026-10-15 使用者裁決移除實體商品
/// （收貨資訊、出貨、庫存預扣逾時都隨之移除；消耗品類虛擬商品仍有庫存，
/// 見〈虛擬商品購買流程〉）。
class Product {
  final String id;
  final String name;
  final String emoji;

  /// 圖片集合。清單與詳情頁取第一張。
  final List<String> images;
  final List<ProductSpec> specs;
  final String? note;

  /// 這件商品發放幾點**永久** AI 點數。不發點數的（補簽券、計畫解鎖）為 0。
  ///
  /// **發放的是數額，不是名稱。** 靠商品名稱去猜要發什麼，改個名字
  /// 就發不出來了 —— 比照獎勵信箱只存數額不存顯示文字的既有設計。
  final int aiCredits;
  Product({
    required this.id,
    required this.name,
    required this.emoji,
    required this.specs,
    this.note,
    this.aiCredits = 0,
    List<String>? images,
  }) : images = images ?? const [];
}

/// 訂單狀態。虛擬商品的終止狀態是「已發放」（道具入庫）。
///
/// 原本另有實體商品的「已出貨」「已退款」，隨實體商品一起移除。
enum OrderState { pendingPayment, paid, delivered, cancelled, failed }

const orderStateNames = <OrderState, String>{
  OrderState.pendingPayment: '待付款',
  OrderState.paid: '已付款',
  OrderState.delivered: '已發放',
  OrderState.cancelled: '已取消',
  OrderState.failed: '已失敗',
};

enum FailReason { insufficientBalance, soldOut, other }

const failReasonNames = <FailReason, String>{
  FailReason.insufficientBalance: '餘額不足',
  FailReason.soldOut: '商品售完',
  FailReason.other: '其他',
};

class Order {
  final String id;
  final String productName;
  final String spec;
  final int qty;
  final DateTime placedAt;
  /// 支付明細：金幣扣除數與法幣支付額分列，併用者兩者皆有值。
  final int coinPaid;
  final int cashPaid;
  OrderState state;
  final FailReason? failReason;

  /// 本筆訂單應發放的永久 AI 點數（已乘上數量）。
  ///
  /// **在確認購買當下凍結**，不在發放時回頭查商品 —— 商品的發放量
  /// 事後被管理員改動，不該回溯影響已成立的訂單。
  final int aiCredits;

  /// 取消是否由系統發起（商品下架）——
  /// 我的訂單頁須與使用者自行取消區別。
  bool cancelledBySystem;

  /// 商品發放已失敗的重試次數。系統自動重試，**上限 3 次**。
  ///
  /// 發放為非同步，與交易成立是兩個不同事實：錢已收、貨還沒到手。
  /// 失敗時**不改變訂單狀態**，訂單於發放成功前維持已付款 ——
  /// 不自動退款，虛擬貨幣與真實金流併用時的雙向退款複雜度高於重試。
  int deliveryRetries;

  /// 達重試上限仍失敗者轉人工處理。
  bool deliveryManual;

  /// 最後一次發放失敗的原因。
  String? deliveryFailReason;
  Order({
    required this.id,
    required this.productName,
    required this.spec,
    required this.qty,
    required this.placedAt,
    required this.coinPaid,
    required this.cashPaid,
    required this.state,
    this.failReason,
    this.cancelledBySystem = false,
    this.deliveryRetries = 0,
    this.deliveryManual = false,
    this.deliveryFailReason,
    this.aiCredits = 0,
  });

  /// 發放尚未完成：已付款、尚未發放。
  bool get awaitingDelivery => state == OrderState.paid;

  /// 取消入口僅狀態為待付款時可用。
  bool get cancellable => state == OrderState.pendingPayment;
}

// --- AI 點數 ---

enum CreditChange { deduct, refund, monthlyGrant, purchase, gift }

const creditChangeNames = <CreditChange, String>{
  CreditChange.deduct: '扣除',
  CreditChange.refund: '退還',
  CreditChange.monthlyGrant: '月度配發',
  CreditChange.purchase: '購買',
  CreditChange.gift: '贈送',
};

class CreditEntry {
  final DateTime at;
  final CreditChange kind;
  final int delta;
  final int monthlyAfter;
  final int permanentAfter;
  final String? source; // 訓練前調整 / 訓練中調整 / 訓練前課表調整
  const CreditEntry({
    required this.at,
    required this.kind,
    required this.delta,
    required this.monthlyAfter,
    required this.permanentAfter,
    this.source,
  });
}

// --- 會員訂閱 ---

enum MembershipState { none, active, cancelledPending, expired }

const membershipStateNames = <MembershipState, String>{
  MembershipState.none: '未訂閱',
  MembershipState.active: '生效中',
  MembershipState.cancelledPending: '已取消待到期',
  MembershipState.expired: '已失效',
};

// 三者為〈會員權益〉的平台級可調參數，由 Command「設定會員權益」維護。
// 調整不影響已生效的訂閱。
int get kMonthlyPrice => platformConfig.i('membership', 'monthly');
int get kYearlyPrice => platformConfig.i('membership', 'yearly');
int get kMonthlyAiCredits => platformConfig.i('membership', 'credits');

// --- 處罰與申訴 ---

enum PunishmentKind { none, warning, communitySuspended, permanent }

const punishmentKindNames = <PunishmentKind, String>{
  PunishmentKind.none: '無',
  PunishmentKind.warning: '警告',
  PunishmentKind.communitySuspended: '社群功能停權',
  PunishmentKind.permanent: '永久停權',
};

enum AppealState { pending, reviewing, upheld, dismissed }

const appealStateNames = <AppealState, String>{
  AppealState.pending: '待審視',
  AppealState.reviewing: '審視中',
  AppealState.upheld: '已成立',
  AppealState.dismissed: '已駁回',
};

/// 功能對照表的功能分類。見 02_Aggregate定義.md〈各處罰級距的功能對照〉。
///
/// 申訴刻意不列入：它是永久停權者**唯一可用的功能**，任何級距都不封鎖，
/// 列進來只會多出一個永遠回傳 false 的分支。
enum PunishedFeature {
  /// 訓練與記錄、能力值累積、階級／經驗值、成就、金幣獎勵。
  training,

  /// 發文／留言／按讚、私訊、關注、團隊、師徒。
  community,

  /// 商城購買與會員訂閱。
  commerce,
}

/// 各功能被哪些級距封鎖。**警告不做任何功能處置，僅記次**，故不出現在任何一列。
///
/// 社群功能停權不影響訓練與所有累積 —— 被禁的是社群互動，不是訓練。
/// 永久停權 ＝ 所有功能皆不可用，僅可申訴。
const _blockedBy = <PunishedFeature, Set<PunishmentKind>>{
  PunishedFeature.training: {PunishmentKind.permanent},
  PunishedFeature.community: {
    PunishmentKind.communitySuspended,
    PunishmentKind.permanent,
  },
  PunishedFeature.commerce: {PunishmentKind.permanent},
};

/// 該處罰級距是否封鎖此功能。
bool punishmentBlocks(PunishmentKind kind, PunishedFeature f) =>
    _blockedBy[f]!.contains(kind);

/// 處罰是否為停權以上（社群功能停權或永久停權）。
/// 教官資格的一併撤銷以此為界 —— **警告不撤銷**。
bool isSuspension(PunishmentKind kind) =>
    kind == PunishmentKind.communitySuspended ||
    kind == PunishmentKind.permanent;

class Punishment {
  final PunishmentKind kind;
  final DateTime? expiresAt; // 永久停權為空值
  final String reason;
  final String evidence;
  final DateTime issuedAt;
  final int violationCount;
  final String nextConsequence;
  bool appealed;
  AppealState? appealState;
  Punishment({
    required this.kind,
    required this.reason,
    required this.evidence,
    required this.issuedAt,
    required this.violationCount,
    required this.nextConsequence,
    this.expiresAt,
    this.appealed = false,
    this.appealState,
  });

  /// 申訴期限為處罰發生起 30 天。
  ///
  /// 取時間一律由呼叫端傳入 —— App 有一個可推進的展示時鐘，
  /// 這裡若自行取系統時間，推進時鐘不會使申訴期限跟著走。
  int appealDaysLeftAt(DateTime now) => 30 - now.difference(issuedAt).inDays;
  bool canAppealAt(DateTime now) => !appealed && appealDaysLeftAt(now) > 0;

  /// 是否已達到期時戳。限期處罰方有到期時戳；
  /// 警告為一次性記錄、永久停權無到期解除，兩者皆為空值。
  bool isExpiredAt(DateTime now) {
    final at = expiresAt;
    return at != null && now.isAfter(at);
  }
}

// --- 獎勵信箱 ---

class MailReward {
  final String source; // 四個來源之一
  final DateTime at;
  bool claimed;

  // 實發數額。**存結構化的值，不存一句字串** ——
  // 只存「金幣 300 ＋ 經驗值 120」這種顯示文字的話，領取時無從得知該發多少，
  // 只能發一個寫死的數字，於是信箱上寫的與實際領到的對不起來。
  final int exp;
  final int coins;
  final int makeupTickets;
  final int aiCredits;

  MailReward({
    required this.source,
    required this.at,
    this.exp = 0,
    this.coins = 0,
    this.makeupTickets = 0,
    this.aiCredits = 0,
    this.claimed = false,
  });

  /// 獎勵內容的顯示文字。**由數額推導**，不另存一份 ——
  /// 存兩份就會有兩份對不起來的事實，而那正是原本的毛病。
  String get content {
    final parts = [
      if (coins > 0) '金幣 $coins',
      if (exp > 0) '經驗值 $exp',
      if (makeupTickets > 0) '補簽券 ×$makeupTickets',
      if (aiCredits > 0) 'AI 點數 $aiCredits',
    ];
    return parts.isEmpty ? '無' : parts.join(' ＋ ');
  }

  bool get isEmpty =>
      exp == 0 && coins == 0 && makeupTickets == 0 && aiCredits == 0;
}

// --- 補簽 ---

/// 簽到方式。〈每日簽到紀錄 Aggregate〉的欄位，
/// **不可省略** —— 補簽頁日曆須據以區分真實簽到日與補簽日。
enum CheckInMethod { real, makeup }

const checkInMethodNames = <CheckInMethod, String>{
  CheckInMethod.real: '真實簽到',
  CheckInMethod.makeup: '補簽',
};

/// 補簽頁日曆上一格的狀態。**由〈每日簽到紀錄〉推導**，不另存一份：
/// 查得到紀錄者依其簽到方式為 signed / madeUp，查無此筆即 missed。
enum MakeupDayState { signed, missed, madeUp }

MakeupDayState makeupStateOf(CheckInMethod? m) => switch (m) {
      CheckInMethod.real => MakeupDayState.signed,
      CheckInMethod.makeup => MakeupDayState.madeUp,
      null => MakeupDayState.missed,
    };

class MakeupDay {
  final DateTime date;
  MakeupDayState state;
  MakeupDay(this.date, this.state);
}


// --- 金幣儲值 ---

/// 儲值 SKU 共 4 檔，基本換算為「售價 × 5 金幣」，另依檔次加贈。
/// 加贈幅度刻意保守（0–12%）：金幣儲值非主要營收，
/// 過廉會使使用者選擇「買金幣解鎖」而非訂閱，兩條營收線互相打架。
class CoinPack {
  final int price; // NT$
  final int coins; // 實得金幣（含加贈）
  final int bonusPercent;
  final String? badge;
  const CoinPack(this.price, this.coins, this.bonusPercent, {this.badge});

  /// 基本量 ＝ 售價 × 5
  int get base => price * 5;
  int get bonus => coins - base;
}

const kCoinPacks = <CoinPack>[
  CoinPack(90, 450, 0),
  CoinPack(330, 1700, 3, badge: '最熱門'),
  CoinPack(990, 5400, 9),
  CoinPack(1690, 9500, 12, badge: '最超值'),
];


/// 一封已寄出的電子郵件通知。
///
/// 電子郵件為使用者 Aggregate 的**選填**欄位，僅供兩類通知使用：
/// 處罰與申訴結果、帳號刪除排程。寄送在系統邊界外，
/// 此處只記錄「寄了什麼給誰」，否則「另以電子郵件通知」無從驗收。
class EmailNotice {
  final String to;
  final String subject;
  final String body;
  final DateTime at;
  const EmailNotice({
    required this.to,
    required this.subject,
    required this.body,
    required this.at,
  });
}


/// 商品發放的自動重試上限。**3 次**，達上限仍失敗者轉人工處理。
const int kDeliveryMaxRetries = 3;
