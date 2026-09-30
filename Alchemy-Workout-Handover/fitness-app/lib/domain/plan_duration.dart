import 'models.dart';

/// 預估訓練時長。
///
/// 使用者回報「課表都沒有預估訓練時間」—— 挑課表的時候要先知道這一份
/// 要花多久，那是選或不選的主要依據之一。
///
/// ## 為什麼是算出來的，不是讀資料欄位
///
/// `PlatformPlanSpec.duration` 本來就有一欄時長，取自《健身計劃.csv》，
/// 而它**不能直接顯示**：
///
/// - 格式各寫各的：`30min`、`約 20–35 分鐘`、`10–15 分鐘`、`120min`
/// - 有幾筆是整段落，含暖身與伸展的逐項拆解，長達兩百字
/// - 有三筆在產生時被引號截斷，落地成 `30 min (含熱身5'`
/// - **自訂訓練根本沒有這一欄** —— 使用者自己編的課表一樣要有預估
///
/// 一份課表的時長本來就是它自己的組數、次數與休息決定的。從那三者算，
/// 每一份課表（含自訂的）都給得出答案，而且格式一致。
/// 原始那段文字留在課表詳情頁的「依據」裡，那是課表作者的說法。
///
/// ## 一下算幾秒
///
/// [kSecondsPerRep] 取 5 秒，不是憑感覺 —— 是拿資料來源**自己寫的**
/// 逐動作時長回頭校準的。《健身計劃.csv》有幾份課表把每個動作花多久
/// 都寫了出來，用 `組數 × (每組工作 + 組間休息)` 去對：
///
/// | 動作 | 處方 | 休息 | 算出來 | CSV 自己寫的 |
/// |---|---|---|---|---|
/// | 深蹲 | 5 組 × 12 下 | 60 秒 | 10.0 分 | 約 10 分鐘 |
/// | 外展臀橋 | 5 組 × 12 下 | 60 秒 | 10.0 分 | 約 10 分鐘 |
/// | 站姿側彎 | 5 組 × 11 下 | 55 秒 | 9.0 分 | 約 8–9 分鐘 |
/// | 臥姿抬膝 | 5 組 × 11 下 | 60 秒 | 9.6 分 | 約 9–10 分鐘 |
/// | 登山者式 | 6 組 × 30 秒 | 30 秒 | 6.0 分 | 約 6 分鐘 |
/// | 拳擊小碎步 | 6 組 × 30 秒 | 30 秒 | 6.0 分 | 約 6 分鐘 |
///
/// 六個動作獨立對上，其中兩個是時間型（不受這個係數影響，驗的是公式本身）。
///
/// **休息乘的是組數，不是組數減一。** 最後一組做完 App 照樣起休息計時
/// （見 `AppState.restSecondsFor` 的呼叫點），而那段時間實際上就是走到
/// 下一個動作的轉場。上表用 `× 組數` 才對得上 CSV。
const kSecondsPerRep = 5;

/// 暖身與收操**不計入**。
///
/// CSV 裡寫得最完整的那幾份把總時長拆成「暖身 10 分 + 主訓練 90–100 分
/// + 伸展 10 分」，而 `items` 只有主訓練那一段。這裡估的是
/// **App 會帶使用者做的那些組**，不替他加上一段 App 沒有安排的暖身 ——
/// 那會讓畫面上的數字比他實際在 App 裡花的時間長。
///
/// [restSecondsOf] 由呼叫端提供，因為休息秒數有三層取值優先序
/// （課表指定 → 動作預設 → 全站預設），而那個順序的唯一權威是
/// `AppState.restSecondsFor`。在這裡自己再寫一次，就是同一個決定
/// 寫在兩個地方。
///
/// 回傳空值代表**估不出來**：空白課表還沒有任何動作。
/// 空值要顯示成「—」之類的東西，不可以顯示成 0 分鐘。
Duration? estimatePlanDuration(
  WorkoutPlan plan, {
  required int Function(PlanExercise) restSecondsOf,
}) {
  if (plan.exercises.isEmpty) return null;
  var total = 0;
  for (final pe in plan.exercises) {
    final rest = restSecondsOf(pe);
    for (final set in pe.planned) {
      final work = pe.isTimed ? set.targetReps : set.targetReps * kSecondsPerRep;
      total += work + rest;
    }
  }
  return Duration(seconds: total);
}

/// 取到 5 分鐘的倍數 —— 這是估的，不是量的。說「37 分鐘」會讓人
/// 以為那個 7 有意義。不足 5 分鐘的課表算 5 分鐘，不是 0。
int planDurationMinutes(Duration d) {
  final rounded = (d.inSeconds / 60 / 5).round() * 5;
  return rounded < 5 ? 5 : rounded;
}

/// 給畫面的文字。
String planDurationLabel(Duration d) => '約 ${planDurationMinutes(d)} 分鐘';

/// 這份課表落在註冊問卷「每次想練多久？」的哪一個級距。
///
/// 使用者回報預估時長「應該要跟註冊時詢問的健身時長有關」——
/// 他在註冊時回答的是四個級距之一，所以挑課表時要能用同一套說法去篩：
/// 「我今天只有 30 分鐘」對應得到哪幾份。
///
/// **算的是 [planDurationMinutes]，不是原始秒數。** 卡片上寫「約 60 分鐘」
/// 而級距卻歸到「60–90 分鐘」（因為實際估出來是 61 分）的話，
/// 兩個數字當著使用者的面互相矛盾。
///
/// 邊界值歸**較短**的那一級：60 分鐘算「30–60 分鐘」。
/// 說「我只有 60 分鐘」的人，一份剛好 60 分鐘的課表他做得完。
String planDurationBucket(Duration d, List<String> buckets) {
  final m = planDurationMinutes(d);
  if (m < 30) return buckets[0];
  if (m <= 60) return buckets[1];
  if (m <= 90) return buckets[2];
  return buckets[3];
}
