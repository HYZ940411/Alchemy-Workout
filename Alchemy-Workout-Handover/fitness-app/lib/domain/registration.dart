// 註冊流程的資料（〈註冊流程〉）
//
// 10 項個人資料全數填畢，方可發生「使用者已完成註冊」。
// 未填完即離開 → 註冊資料填寫已中斷；下次登入自未完成的欄位續填，已填資料不清空。

import 'clock.dart';

enum SignUpEntry { phone, thirdParty }

/// 健身目標分兩類：動機類（選填，最多 1 項）與常見目標類（必填，1 項），合計最多 2 項。
const kMotiveGoals = ['健康陪伴家人', '堅持夢想', '自信外型', '紓壓'];
const kCommonGoals = ['增肌', '減重', '培養運動習慣', '提升體能'];

/// 分級以訓練年資的月數界定，不以未量化的形容詞界定。
const kExperience = ['新手（未滿 6 個月）', '中階（6 個月–2 年）', '進階（2 年以上）'];

/// 每次健身時長為區間列舉 —— 使用者無法精確估計單次時長。
/// 本值域寫死、不開放調整。
const kDurations = ['30 分鐘以下', '30–60 分鐘', '60–90 分鐘', '90 分鐘以上'];

/// 註冊維持 3 級器材、必填；細項為選填，於設定頁填寫，不進註冊流程。
const kEquipmentTiers = ['健身房（全器材）', '居家器材（彈力繩、小啞鈴等）', '徒手'];

const int kMinAge = 13;

/// 暱稱長度上限。社群列表、隊伍成員列、排行榜名次列共用同一欄寬。
const int kNicknameMaxLength = 12;

/// 暱稱是否合格：去除前後空白後不得為空，且不超過上限。
///
/// **不檢查全平台唯一。** 暱稱是顯示名稱，不是識別碼 —— 系統內一律以 uid
/// 識別（見 `AppState.nameByUid`），唯一性檢查只會在註冊漏斗上多一道
/// 會失敗的關卡。
bool isValidNickname(String v) {
  final t = v.trim();
  // 用 runes 而不是 length：length 數的是 UTF-16 碼元，表情符號會算成兩個字。
  return t.isNotEmpty && t.runes.length <= kNicknameMaxLength;
}

/// 簡訊驗證碼位數與重新發送的冷卻秒數。
const int kSmsCodeLength = 6;
const int kSmsResendSeconds = 60;

/// 手機號碼格式：09 開頭的 10 位數字。
bool isValidPhone(String v) =>
    RegExp(r'^09\d{8}$').hasMatch(v.replaceAll(RegExp(r'[\s-]'), ''));

/// 註冊獎勵：金幣 100 ＋ 補簽券 ×1；**無經驗值**。
const int kSignUpCoins = 100;
const int kSignUpMakeupTickets = 1;

/// 服務條款與隱私權政策的條文。
///
/// **不寫死在畫面裡**：條文會改版，而改版要連帶更新版本號
/// （[SignUpDraft.termsVersion]）。分開放，改的時候不必翻 widget 樹。
///
/// 兩處刻意與使用者提供的草稿不同，理由記在這裡以免日後被「修回去」：
///
/// 一、**年齡下限寫 13 歲，不是 16 歲。** 草稿寫 16，但〈註冊流程〉
///     2026-08-19 有一條 `[決策]` 明確駁回 16 歲（會排除 13–15 歲使用者，
///     並作廢〈13 歲沿用 14 歲的係數〉），且 `kMinAge` 就是 13。
///     條款與程式不能各說一套（2026-09-18 使用者裁決：條款改 13）。
///
/// 二、**審核不寫具體時數。** 草稿寫「24 小時內」，但〈審核時限設定〉的
///     初始值是檢舉 7 天、申訴 72 小時，而且那四項時限是**後台可調參數** ——
///     條款寫死一個數字，等於承諾了平台做不到、而且隨時會變的事。
/// 現行條款版本。**改 [kTermsSections] 的條文就要動這個數字。**
///
/// 規格三處都寫著「條款改版後，既有使用者於下次登入時須重新同意」
/// （〈註冊流程〉、〈01_Command清單〉、〈02_Aggregate定義〉的「已同意條款版本」）。
/// 那套機制唯一的觸發條件就是這個字串跟使用者存檔裡那個對不上 ——
/// **忘了改這裡，改版就不會要求任何人重新同意，而且沒有任何跡象。**
///
/// 2026-09-18 條文由 v3.2 改為 v4.0 時，這個機制還不存在，
/// 所以那一次沒有任何既有使用者被要求重新同意（PROGRESS.md 第 5 節 0b）。
const String kTermsVersion = 'v4.0';

const kTermsSections = <(String, String)>[
  (
    '',
    '感謝您選擇健金術 Alchemy Workout（以下簡稱「本平台」）。'
        '為了保障您的權益，請於註冊成為會員前詳閱以下條款。'
        '當您註冊成功或開始使用服務，即視為您已閱讀、瞭解並同意接受'
        '本約定條款之全部內容。',
  ),
  (
    '一、帳號註冊與安全性',
    '1. 年齡限制：本平台不開放予未滿 13 歲之人使用。'
        '未滿 18 歲之用戶，應在法定代理人陪同下閱讀並同意本條款。\n\n'
        '2. 帳號保管：用戶應妥善保管密碼與第三方登入憑證。'
        '任何經由正確憑證登入後所執行之行為，均視為用戶本人之行為。'
        '若發現帳號遭冒用，應立即通知本平台。',
  ),
  (
    '二、醫療與健身風險免責聲明',
    '1. 非醫療建議：本平台提供之訓練計畫、能力值與生理數據分析'
        '（如消耗卡路里、估算 1RM）僅供參考，'
        '不構成醫療診斷、處方或治療建議。\n\n'
        '2. 免責範圍涵蓋五條路徑：\n'
        '　（一）教官的回答\n'
        '　（二）師徒任務的內容\n'
        '　（三）其他使用者公開的課表\n'
        '　（四）AI 訓練建議（微調／調整／自動優化／替換動作，'
        '含快照的預帶重量）\n'
        '　（五）平台動作示範內容\n'
        '上述內容僅供參考，不構成醫療或專業訓練建議。'
        '請依自身狀況調整強度，必要時諮詢專業人員。\n\n'
        '3. 自主評估：進行任何運動前應諮詢專業醫師。'
        '若您在運動中感到眩暈、胸悶或劇烈疼痛，應立即停止並尋求醫療協助。\n\n'
        '4. 風險承擔：用戶瞭解運動具有潛在風險，'
        '同意自行承擔因使用本平台建議而產生之任何身體傷害；'
        '本平台除因故意或重大過失外，不負賠償責任。',
  ),
  (
    '三、社群規範與內容管理',
    '1. 禁止行為：嚴禁發布色情、霸凌、歧視、非法廣告、'
        '虛假健身資訊或侵犯他人隱私之內容。\n\n'
        '2. 審核與處分：本平台設有檢舉與封鎖機制。'
        '收到檢舉後將依內部審核流程處理，'
        '並得對違規用戶採取警告、社群功能停權或終止服務之處分。'
        '處分級距依累計違規次數認定。\n\n'
        '3. 內容授權：您於社群分享之內容，'
        '視為授予本平台在全球範圍內非獨佔、免費之平台展示權，'
        '範圍以提供本服務所必要者為限。',
  ),
  (
    '四、隱私權政策',
    '1. 我們收集什麼：註冊時填寫的暱稱、生日、性別、身高、體重、'
        '健身目標、健身經驗、每週天數、每次時長與持有器材；'
        '第三方登入帶入的電子郵件；'
        '以及您使用服務所產生的訓練紀錄、簽到紀錄、能力值、'
        '成就、金幣與訂單、社群貼文與留言、私訊、AI 對話。\n\n'
        '2. 存在哪裡：資料儲存於 Google Firebase（Authentication 與 '
        'Cloud Firestore）。本平台不將您的個人資料出售或出租給第三方。\n\n'
        '3. 誰看得到：暱稱、階級與綜合能力等級為社群功能所需，'
        '對其他用戶可見；六維能力值與綜合等級可於「我的檔案」'
        '自行關閉對外顯示。擔任教官者，其能力值與聲望一律公開 ——'
        '學徒需據此判斷是否拜師。\n\n'
        '4. 保留多久：帳號存續期間持續保留。'
        '訓練紀錄、簽到紀錄與能力值日快照為長期保存，'
        '因其為能力值與成就判定的依據。\n\n'
        '5. 怎麼刪：您可於「我的 → 帳號與安全」申請刪除帳號。'
        '申請後有 30 天冷靜期，期間可隨時取消；'
        '期滿即刪除上述所有個人資料與您產生的內容（含貼文與留言）。\n\n'
        '6. 刪除的例外：已成案且處理中的檢舉或申訴，'
        '其所需的最小證據暫留至該案件結案，結案後一併清除；'
        '已付款未出貨的實體訂單，其收貨資訊暫留至出貨完成。'
        '兩者皆會在刪除流程中告知您。'
        '另，排行榜的歷史名次紀錄不含個人資料，一經結算即不可修改，'
        '不隨帳號刪除而變動。',
  ),
  (
    '五、服務中止、條款變更與管轄',
    '1. 條款變更：本平台保有隨時修改或變更本條款之權利，'
        '變更將於 App 內公告後生效；'
        '條款改版後，既有用戶於下次登入時須重新同意。\n\n'
        '2. 準據法：本條款之解釋與適用悉依中華民國法律定之。\n\n'
        '3. 管轄法院：若因本服務產生爭議涉訟時，'
        '以臺灣臺北地方法院為第一審管轄法院。',
  ),
];

class SignUpDraft {
  SignUpEntry? entry;

  /// 手機註冊者的號碼。第三方登入者為空值。
  String? phone;

  /// 手機簡訊驗證是否已通過。第三方登入者不需驗證，直接為真。
  bool phoneVerified = false;

  /// 電子郵件為**選填**：第三方登入於授權時帶入，手機註冊者不強制填寫，
  /// 可於設定頁自願補填。僅供出貨、處罰與申訴結果、帳號刪除排程三類通知使用。
  String? email;

  bool termsAgreed = false;

  /// 這份草稿要同意的條款版本。**一律取 [kTermsVersion]，不另外寫死** ——
  /// 兩個地方各寫一個版本號的話，改條文時只改到一個，那套「改版要重新
  /// 同意」的機制就會安靜地不觸發。
  String termsVersion = kTermsVersion;

  /// 入口已完成 —— 手機須驗證通過，第三方須授權完成。
  bool get entryDone =>
      entry == SignUpEntry.thirdParty ||
      (entry == SignUpEntry.phone && phoneVerified);

  // 10 項必填
  /// 暱稱。社群、隊伍、私訊、排行榜看到的都是它。
  String? nickname;

  double? heightCm; // 50–250
  double? weightKg; // 20–300
  String? gender; // 男 / 女
  DateTime? birthday; // 須滿 13 歲
  String? motiveGoal; // 選填
  String? commonGoal; // 必填
  String? experience;
  int? daysPerWeek; // 1–7
  String? duration;
  final Set<String> equipment = {}; // 可複選，無數量上限

  /// 逐欄位建模，供註冊漏斗流失率分析。
  List<bool> get filled => [
        nickname != null,
        heightCm != null,
        weightKg != null,
        gender != null,
        birthday != null,
        commonGoal != null,
        experience != null,
        daysPerWeek != null,
        duration != null,
        equipment.isNotEmpty,
      ];

  int get filledCount => filled.where((f) => f).length;
  static const int total = 10;
  bool get complete => filledCount == total;

  /// 續填的起點：第一個未填的欄位。
  int get resumeIndex => filled.indexWhere((f) => !f).clamp(0, total - 1);

  int? get age {
    final b = birthday;
    if (b == null) return null;
    final now = appNow();
    var a = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) a--;
    return a;
  }

  bool get ageValid => (age ?? 0) >= kMinAge;
}

// ---------------------------------------------------------------------------
// 訓練計畫推薦（〈註冊流程〉：訓練計畫已推薦）
// ---------------------------------------------------------------------------

/// 註冊問卷的 3 級器材 → 訓練計畫的器材層級。
const _tierOf = <String, String>{
  '健身房（全器材）': '健身房',
  '居家器材（彈力繩、小啞鈴等）': '居家',
  '徒手': '徒手',
};

/// 器材為硬約束：健身房可執行全部；居家可執行居家與徒手；徒手只能徒手。
const _covers = <String, Set<String>>{
  '健身房': {'健身房', '居家', '徒手'},
  '居家': {'居家', '徒手'},
  '徒手': {'徒手'},
};

/// 帶著某個器材條件的人能執行哪些課表級別 —— 空值代表不限（全部）。
///
/// 課表篩選與訓練計畫推薦必須是同一套語意：選「居家器材」的人要看到
/// 居家**與徒手**兩種課表，不是只有標著「居家」的那幾份。器材是硬約束，
/// 而硬約束的定義只能有一份 —— [recommendPlan] 也走這一支。
///
/// [equipment] 取註冊問卷的值域（[kEquipmentTiers]）；課表上的
/// `equipmentTier` 是短標（健身房／居家／徒手），兩者不同字串，
/// 靠 [_tierOf] 對上。
Set<String>? runnablePlanTiers(String? equipment) {
  if (equipment == null) return null;
  final tier = _tierOf[equipment];
  return tier == null ? null : _covers[tier];
}

/// 一份計畫對某位使用者的比對結果。
///
/// 比對維度三項：器材、經驗、常見目標；**動機類不參與比對**
/// —— 它與課表內容無對應關係，參與比對只會製造雜訊。
class PlanMatch {
  final int index; // 建立順序，供同分時取最早者
  final bool equipmentOk;
  final bool experienceOk;
  final bool goalOk;
  const PlanMatch({
    required this.index,
    required this.equipmentOk,
    required this.experienceOk,
    required this.goalOk,
  });

  /// 比對優先序：器材 → 經驗 → 常見目標，前一維度符合者優先，同層再比下一維度。
  /// 依「違反後果的嚴重程度」排定：器材不符即完全無法執行；經驗不符有受傷風險；
  /// 常見目標不符仍是一份有效訓練，僅不夠對症。
  int get score =>
      (equipmentOk ? 4 : 0) + (experienceOk ? 2 : 0) + (goalOk ? 1 : 0);
}

/// 依經驗／目標／器材，自既有計畫中推薦一份。
///
/// 推薦為**單向指派**，使用者不可拒絕，無拒絕分支 —— 故只回傳一份。
/// 找不到任何計畫時回傳空值（呼叫端須自行處理，不得假裝推薦成功）。
T? recommendPlan<T>(
  List<T> plans, {
  required String? equipment,
  required String? experience,
  required String? commonGoal,
  required String Function(T) tierOf,
  required Set<String> Function(T) experienceOf,
  required Set<String> Function(T) goalsOf,
}) {
  if (plans.isEmpty) return null;
  final runnable = runnablePlanTiers(equipment);

  T? best;
  var bestScore = -1;
  for (var i = 0; i < plans.length; i++) {
    final p = plans[i];
    final m = PlanMatch(
      index: i,
      equipmentOk: runnable == null || runnable.contains(tierOf(p)),
      experienceOk:
          experienceOf(p).isEmpty || experienceOf(p).contains(experience),
      goalOk: goalsOf(p).isEmpty || goalsOf(p).contains(commonGoal),
    );
    // 同分者取建立時間最早 —— 不採隨機取一：同樣條件的兩個使用者
    // 會拿到不同計畫，且無法重現與除錯。
    if (m.score > bestScore) {
      bestScore = m.score;
      best = p;
    }
  }
  return best;
}
