/// 社群的關係型 Aggregate 與通知
///
/// 關注與封鎖同屬**無擁有者的關係型 Aggregate**，故各自獨立建模，
/// 不掛在使用者或對話之下 —— 可封鎖從未與其對話過的對象。
library;

/// 社群裡的一個人。名稱在本專案即為識別碼。
class SocialUser {
  final String name;

  /// 雲端身分。**示範資料的假使用者沒有 uid，所以可以是空值。**
  ///
  /// 名稱在示範資料裡當識別碼用，但**暱稱可以改** —— 要拿去查對方
  /// 現在的階級與六維時一律用這個，查不到才退回用名稱。
  final String? uid;

  /// **這不是要顯示的值**，只在查不到他的公開檔案時墊底。
  final int rank;
  final String grade; // 綜合能力等級
  const SocialUser({
    required this.name,
    required this.rank,
    required this.grade,
    this.uid,
  });
}

/// 一筆封鎖。單向關係，唯一鍵為 封鎖者 ID ＋ 被封鎖者 ID。
/// 一個人在「以人為鍵」的集合裡長什麼樣（暱稱重構）。
///
/// **有 uid 就是 uid。** 沒有的（示範資料、還沒發布公開檔案的人）退回
/// 暱稱並加上前綴 —— 加前綴是為了不可能跟某個真實 uid 撞值，
/// Firebase 的 uid 不含冒號。
///
/// 關注名單、他人的粉絲數、團隊貢獻、限時任務完成名單、學徒評分次數
/// 都用這個鍵。`AppState.personKeyOf` 是它加上「暱稱反查 uid」的版本。
String personKey(String name, String? uid) => uid ?? 'name:$name';

/// 這個鍵是不是「沒有 uid」的那一種。
bool isNamePersonKey(String key) => key.startsWith('name:');

class BlockedUser {
  final String name;

  /// 對方的雲端身分。**示範資料的假使用者沒有，所以可以是空值。**
  ///
  /// 理由同 [SocialUser.uid]。封鎖的後置條件是「解除雙方的關注關係」，
  /// 而關注名單以 uid 為鍵 —— 只留暱稱的話，對方改名之後解不掉，
  /// 也擋不住他在下一次登入時從雲端回到我的粉絲名單。
  final String? uid;
  final DateTime at;
  const BlockedUser(this.name, this.at, {this.uid});
}

/// 通知的兩類。**只有推播類受同日總量上限約束。**
///
/// 判準是「不看會不會失去東西」：
/// 推播類 ＝ 不看就失去（天數歸零、申請逾期、能力值退步）；
/// App 內通知類 ＝ 東西不會跑掉（獎勵在信箱等、成就解鎖即為己有）。
enum NotifyKind { push, inApp }

const notifyKindNames = <NotifyKind, String>{
  NotifyKind.push: '推播',
  NotifyKind.inApp: 'App 內通知',
};

/// 推播的優先序（由高至低 1 → 3）。同日超出總量上限時，
/// **依優先序由低至高捨棄** —— 先丟例行提醒，不丟期限即將失效的那些。
enum NotifyPriority { expiring, guidance, routine }

const notifyPriorityNames = <NotifyPriority, String>{
  NotifyPriority.expiring: '期限即將失效',
  NotifyPriority.guidance: '行動引導',
  NotifyPriority.routine: '例行提醒',
};

class AppNotification {
  final String id;

  /// 觸發本則通知的 Event —— 通知本身不是新的業務事實，
  /// 它是既有 Event 的 Postcondition。
  final String sourceEvent;
  final String title;
  final String body;
  final DateTime at;
  final NotifyKind kind;

  /// 僅推播類有優先序；App 內通知類不排序也不受上限約束。
  final NotifyPriority? priority;
  bool read;

  AppNotification({
    required this.id,
    required this.sourceEvent,
    required this.title,
    required this.body,
    required this.at,
    required this.kind,
    this.priority,
    this.read = false,
  });
}

/// 同日推播總量上限。平台級可調參數，存於〈通知設定 Aggregate〉。
const int kDailyPushLimit = 3;

/// 依同日總量上限挑出「實際會送出」的推播。
///
/// 超出上限者**依優先序由低至高捨棄**；同優先序內取較早的那些
/// —— 後來的例行提醒不該擠掉稍早同級的。
List<AppNotification> pushesWithinLimit(
  List<AppNotification> all,
  DateTime day, {
  int limit = kDailyPushLimit,
}) {
  bool sameDay(DateTime a) =>
      a.year == day.year && a.month == day.month && a.day == day.day;

  final todays = all
      .where((n) => n.kind == NotifyKind.push && sameDay(n.at))
      .toList()
    ..sort((a, b) {
      final p = a.priority!.index.compareTo(b.priority!.index);
      return p != 0 ? p : a.at.compareTo(b.at);
    });
  return todays.take(limit).toList();
}

/// 粉絲成就的門檻。
const kFollowerMilestones = [10, 50, 100, 300, 500, 1000, 3000, 5000, 10000];

/// 粉絲數對應已解鎖的門檻數。
///
/// 只增不減：**粉絲數下降不撤銷任何已解鎖的粉絲成就** ——
/// 承「成就解鎖紀錄為單調遞增」的既有原則；粉絲取消關注是他人的行為，
/// 成就不該因他人的舉動被拿走。
int followerMilestonesReached(int peak) =>
    kFollowerMilestones.where((m) => peak >= m).length;
