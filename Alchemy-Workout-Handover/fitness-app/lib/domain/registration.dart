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
  String termsVersion = 'v3.2';

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
  final myTier = equipment == null ? null : _tierOf[equipment];
  final runnable = myTier == null ? null : _covers[myTier];

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
