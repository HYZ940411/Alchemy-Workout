import 'dart:math' as math;

import 'adjust_volume.dart';
import 'models.dart';

/// 調整的意圖。對應 AI 追問「要怎麼調」的幾個答案。
enum AdjustIntent {
  /// 整體降強度：重量下修、次數上調，維持訓練量但降低單組負荷。
  easier,

  /// 整體升強度：重量上調。
  harder,

  /// 減量：砍掉每個動作的最後一組。
  trim,

  /// 替換動作 —— 把做不了的動作換成同肌群、且器材做得到的另一個。
  ///
  /// **這是規格早就定義的 Command**（`01_Command清單.md`〈替換動作〉→
  /// Event「AI 已替換動作」，攜帶原動作 ID、替換後動作 ID、替換原因），
  /// 以「持有器材明細」為調整依據（`02_Aggregate定義.md` §1324）。
  /// 在此之前沒有任何呼叫端 —— 連 [PlanExercise.replacedFrom] 這個欄位
  /// 都已經存在，只是從來沒有人寫進去過。
  swap,
}

const adjustIntentNames = <AdjustIntent, String>{
  AdjustIntent.easier: '整體降強度',
  AdjustIntent.harder: '整體升強度',
  AdjustIntent.trim: '減少組數',
  AdjustIntent.swap: '替換做不了的動作',
};

/// 一個動作的一項變更。**AI 只產出建議，不套用** —— 故建議是一份
/// 可讀、可逐條檢視的資料，不是一段已經改好的課表。
class AdjustChange {
  /// 該動作在課表中的索引。套用時以索引對位，不用名稱。
  final int exerciseIndex;
  final String exerciseName;

  /// 調整後的逐組目標。空清單代表整個動作被移除（本版不產生）。
  final List<PlannedSet> after;

  /// 調整前的逐組目標，供畫面對照。
  final List<PlannedSet> before;

  /// 替換後的動作。**空值代表這一筆只改強度，沒換動作。**
  ///
  /// 有值時 [after] 是換過去之後的逐組目標 —— 換了動作，原本的重量
  /// 多半不適用，模型要一併給新的。
  final Exercise? replacement;

  /// 這一筆為什麼這樣調。**空值代表這一次沒有理由可說** ——
  /// 端內規則產的建議就是這種：它只會算，說不出所以然。
  ///
  /// 有了它，建議才不只是一組數字。使用者自己也會把 60 改成 55，
  /// 他需要的是「為什麼是 55 不是 50」。
  final String? reason;

  /// **這一筆是新加的動作**（2026-10-04 裁決：AI 可在訓練中加動作）。
  ///
  /// 有值時 [exerciseIndex] 為 -1、[before] 為空 —— 它不在原課表裡。
  /// 套用不走 [applySuggestion]（索引對位會跳過它），走規格的
  /// 「加入動作至本次訓練」，與使用者手動加動作同一條路。
  final Exercise? addition;

  const AdjustChange({
    required this.exerciseIndex,
    required this.exerciseName,
    required this.before,
    required this.after,
    this.replacement,
    this.reason,
    this.addition,
  });

  /// 一個新加的動作。
  const AdjustChange.addition(Exercise this.addition, this.after, {this.reason})
      : exerciseIndex = -1,
        exerciseName = '',
        before = const [],
        replacement = null;

  bool get setsChanged => before.length != after.length;

  static String _w(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  /// 這一筆改了什麼都沒有。表格用它把沒動的那幾列降一階呈現 ——
  /// 一份建議裡多半有一半是「維持不變」，它們不該跟真正的改動一樣搶眼。
  bool get unchanged =>
      addition == null &&
      replacement == null &&
      !setsChanged &&
      before.first.targetWeight == after.first.targetWeight &&
      before.first.targetReps == after.first.targetReps;

  /// 表格第一欄：動作。換了動作就是「原動作 → 新動作」。
  String get title => addition != null
      ? '＋ ${addition!.name}（新動作）'
      : replacement == null
          ? exerciseName
          : '$exerciseName → ${replacement!.name}';

  /// 表格第二欄：調整成什麼。
  ///
  /// **與 [title] 分開兩個 getter，[summary] 由兩者組出來。**
  /// 原本只有 `summary`，動作名與調整內容用一個全形空格黏在一起 ——
  /// 表格要分欄就得把那個字串再切開，而「用分隔符切字串」是個
  /// 遲早會遇到動作名裡剛好有全形空格的做法。
  String get change {
    final r = replacement ?? addition;
    if (r != null) {
      final a = after.first;
      final load = a.targetWeight == 0
          ? '${a.targetReps} 下'
          : '${_w(a.targetWeight)}kg × ${a.targetReps} 下';
      return '$load × ${after.length} 組';
    }
    if (setsChanged) return '${before.length} 組 → ${after.length} 組';
    if (unchanged) return '維持不變';
    final b = before.first;
    final a = after.first;
    if (b.targetWeight == 0 && a.targetWeight == 0) {
      return '${b.targetReps} 下 → ${a.targetReps} 下';
    }
    return '${_w(b.targetWeight)}kg × ${b.targetReps} 下'
        ' → ${_w(a.targetWeight)}kg × ${a.targetReps} 下';
  }

  /// 一行人話。純文字的對話紀錄用它。
  String get summary => '$title　$change';

  /// 畫面上這一筆的完整文字：一行數字，有理由就再一行。
  ///
  /// **理由縮排一格**，讀起來才分得出「改什麼」與「為什麼」。
  /// 筆與筆之間的空行由呼叫端加（見 `AppState` 組訊息那兩處）——
  /// 這裡只負責一筆。
  String get detail => reason == null ? summary : '$summary\n　　$reason';
}

/// 每個調整方向的依據。**規則引擎也要講得出為什麼。**
///
/// 使用者自己就會把 60 改成 55 —— 他需要的是「為什麼是 55 不是 50」。
/// 模型沒接上時至少要說得出這一條規則的訓練學依據，
/// 而不是丟三行數字就結束。
///
/// **措辭不假裝是分析**：這是一條固定規則，不是看著這個人的紀錄算的。
const adjustRationale = <AdjustIntent, String>{
  AdjustIntent.easier: '重量降一成、每組多兩下 —— 總反覆量維持不變，'
      '降的是單組負荷。狀況不好時先保住動作品質，比硬撐重量有意義。',
  AdjustIntent.harder: '重量加半成、次數不變 —— 漸進超負荷的幅度刻意取小，'
      '每次一小步比偶爾一大步更不容易受傷，也更容易連續達成。',
  AdjustIntent.trim: '砍掉每個動作的最後一組，前面幾組的重量與次數不動 —— '
      '縮短的是總時間，不是強度。時間不夠時，減組數比減重量划算。',
  AdjustIntent.swap: '把做不了的動作換成同肌群、器材做得到的另一個，'
      '並依新動作重算重量。',
};

/// 一份建議。
class AdjustSuggestion {
  final AdjustIntent intent;
  final List<AdjustChange> changes;

  /// 這份建議整體的依據。空值代表逐筆的 [AdjustChange.reason] 已經講夠了
  /// —— 模型會針對每個動作各給一條理由，那比一句通則有用。
  final String? rationale;

  /// 這份建議同時處理的方向。第一個就是 [intent]。
  ///
  /// **一句話可以有兩個要求**（2026-10-04 裁決）：「加動作而且加強度」、
  /// 「累了而且只剩 20 分鐘」。在此之前分類器一看到兩個方向就整句判不出來。
  final List<AdjustIntent>? _intents;

  const AdjustSuggestion({
    required this.intent,
    required this.changes,
    this.rationale,
    List<AdjustIntent>? intents,
  })
      // 私有欄位不能當具名參數，只能這樣接。
      // ignore: prefer_initializing_formals
      : _intents = intents;

  List<AdjustIntent> get intents => _intents ?? [intent];

  /// 標題：「整體升強度＋替換做不了的動作」。
  String get title => intents.map((i) => adjustIntentNames[i]!).join('＋');

  /// 新加的動作。
  Iterable<AdjustChange> get additions =>
      changes.where((c) => c.addition != null);

  /// 這份建議等於什麼都沒改。
  ///
  /// **換了動作就不算空的**，即使逐組目標一模一樣 —— 把做不了的動作
  /// 換成做得到的，本身就是改動。漏掉這一項的話，一次成功的替換會被
  /// 當成「沒有可調的空間」擋下來。新加的動作同理。
  bool get isEmpty => changes.every((c) =>
      c.addition == null &&
      c.replacement == null &&
      !c.setsChanged &&
      c.before.first.targetWeight == c.after.first.targetWeight &&
      c.before.first.targetReps == c.after.first.targetReps);
}

/// 場館的槓片以 2.5kg 為級距，推到小數點沒有意義。
double _round(double kg) => (kg / 2.5).round() * 2.5;

/// 自體重（重量 0）或計時動作，強度只能動在次數（秒數）上。
///
/// **2026-10-04 修正兩個方向相反的錯：**
/// - 降強度原本是「重量 ×0.9、次數 +2」—— 重量 0 的動作只剩「次數 +2」，
///   伏地挺身越降越難
/// - 加強度原本只動重量 —— 重量 0 的動作什麼都不會發生
///
/// 幅度取兩成、至少一下（一秒），與有重量動作的「降一成重量、多兩下」
/// 量級相當。
int _repsStep(int reps) => math.max(1, (reps * 0.2).round());

/// 依**當前課表**產生建議。
///
/// 這是本專案端內模擬的「AI」：模型把 LLM 放在軟體邊界之外，
/// 只規定呼叫時點、扣點、失敗退點、以及「AI 僅產出建議、不套用」。
/// 建議的內容本身不是模型的規範對象，故此處以一組明確的規則產生 ——
/// **重點是它讀的是使用者眼前這份課表**，而非一段與課表無關的固定文字。
///
/// [onlyFrom] 為起始索引，訓練中調整用它把已完成的動作排除在外。
///
/// [intents] 為同時處理的方向（空值＝只有 [intent]）；[volume] 為時間預算
/// 決定的組數安排（見 `adjust_volume.dart`）。沒給 [volume] 時沿用不看時間的
/// 舊規則：加強度只加重量、減組數每個動作砍一組。
///
/// **規則不挑新動作** —— [VolumePlan.newExerciseSets] 在這裡被忽略。
/// 要加新動作得從候選裡挑一個適合這個人的，那不是一條公式算得出來的；
/// 模型沒能回應時，呼叫端應改用不加新動作的那一份安排。
AdjustSuggestion buildSuggestion(
  List<PlanExercise> exercises,
  AdjustIntent intent, {
  int onlyFrom = 0,
  List<AdjustIntent>? intents,
  VolumePlan? volume,
}) {
  final all = intents ?? [intent];
  final easier = all.contains(AdjustIntent.easier);
  final harder = all.contains(AdjustIntent.harder);
  final trim = all.contains(AdjustIntent.trim);
  // 加強度要不要動重量：沒有時間預算時一律動；有預算時只在「不夠加一組」時動。
  final raiseLoad = harder && (volume == null || volume.weightOnly);

  final changes = <AdjustChange>[];
  for (var i = onlyFrom; i < exercises.length; i++) {
    final pe = exercises[i];
    if (pe.planned.isEmpty) continue;
    final before = [...pe.planned];
    var after = [...before];

    if (easier) {
      after = [
        for (final s in after)
          s.targetWeight == 0
              ? PlannedSet(0, math.max(1, s.targetReps - _repsStep(s.targetReps)))
              // 降重量 10%、次數 +2：維持總反覆量，降低單組負荷。
              : PlannedSet(math.max(2.5, _round(s.targetWeight * 0.9)),
                  s.targetReps + 2),
      ];
    }
    if (raiseLoad) {
      after = [
        for (final s in after)
          s.targetWeight == 0
              ? PlannedSet(0, s.targetReps + _repsStep(s.targetReps))
              : PlannedSet(_round(s.targetWeight * 1.05), s.targetReps),
      ];
    }
    // 組數：先砍後加。加的組照抄這個動作的最後一組。
    final cut = volume == null
        ? (trim && after.length > 1 ? 1 : 0)
        : (volume.cutSets[i] ?? 0);
    if (cut > 0) after = after.sublist(0, math.max(1, after.length - cut));
    final add = volume?.addSets[i] ?? 0;
    if (add > 0) after = [...after, for (var k = 0; k < add; k++) after.last];
    // **規則引擎不換動作。** 挑替代動作要看肌群、器材與這個人的
    // 水準，那不是一條 ×0.9 算得出來的東西。

    changes.add(AdjustChange(
      exerciseIndex: i,
      exerciseName: pe.exercise.name,
      before: before,
      after: after,
    ));
  }
  return AdjustSuggestion(
    intent: all.first,
    intents: all,
    changes: changes,
    // 規則產的建議逐筆說不出話（它只會算），但整條規則的依據講得出來。
    rationale: volume == null
        ? (all.length == 1
            ? adjustRationale[all.first]
            : all.map((i) => adjustRationale[i]).join('\n'))
        : volumeRationale(all, volume),
  );
}

/// 有時間預算時的依據。**講的是這一次的數字**，不是一條通則。
String volumeRationale(List<AdjustIntent> intents, VolumePlan v) {
  final lines = <String>[];
  final have = v.minutes;
  final need = minutesOf(v.remainingSeconds);
  if (intents.contains(AdjustIntent.easier)) {
    lines.add(adjustRationale[AdjustIntent.easier]!);
  }
  if (intents.contains(AdjustIntent.trim)) {
    if (have == null) {
      lines.add(adjustRationale[AdjustIntent.trim]!);
    } else if (v.cutSetCount == 0) {
      lines.add('剩下的組約 $need 分鐘，在你的 $have 分鐘內做得完，不用減。');
    } else {
      lines.add('剩下的組約 $need 分鐘、你有 $have 分鐘 —— '
          '從排在後面的動作開始砍了 ${v.cutSetCount} 組，前面的主項保留。'
          '${v.overSeconds > 0 ? '每個動作都只剩一組了，仍會超出約 ${minutesOf(v.overSeconds)} 分鐘。' : ''}');
    }
  }
  if (intents.contains(AdjustIntent.harder)) {
    if (v.weightOnly) {
      lines.add(have == null || intents.contains(AdjustIntent.trim)
          ? adjustRationale[AdjustIntent.harder]!
          : '剩下的組約 $need 分鐘、你有 $have 分鐘，多出的時間不夠再做一組 —— '
              '所以只加重量（自體重動作加次數），不加量。');
    } else {
      final extra = minutesOf(v.budgetSeconds ?? 0);
      final onExisting = v.addSets.values.fold(0, (a, b) => a + b);
      lines.add('剩下的組約 $need 分鐘、你有 $have 分鐘，多出約 $extra 分鐘 —— '
          '${v.newExerciseSets > 0 ? '加一個新動作 ${v.newExerciseSets} 組' : ''}'
          '${v.newExerciseSets > 0 && onExisting > 0 ? '，' : ''}'
          '${onExisting > 0 ? '在前面的主項加 $onExisting 組' : ''}'
          '，重量與次數不變。');
    }
  }
  if (intents.contains(AdjustIntent.swap)) {
    lines.add(adjustRationale[AdjustIntent.swap]!);
  }
  return lines.join('\n');
}

/// 把建議套進一份課表，回傳新的動作清單。**不就地修改傳入的清單。**
///
/// 以索引對位：課表在建議產出後若被改動（加入動作），超出範圍者略過，
/// 不硬套到別的動作上。
List<PlanExercise> applySuggestion(
  List<PlanExercise> exercises,
  AdjustSuggestion s,
) {
  final out = [...exercises];
  for (final c in s.changes) {
    if (c.exerciseIndex < 0 || c.exerciseIndex >= out.length) continue;
    final pe = out[c.exerciseIndex];
    if (pe.exercise.name != c.exerciseName) continue; // 對位不上就不套
    final r = c.replacement;
    out[c.exerciseIndex] = PlanExercise(
      exercise: r ?? pe.exercise,
      planned: c.after,
      // **換動作時記下原動作。** 規格要求訓練進行中頁標示「已替換」
      // 並可展開檢視原動作，還原入口也在那裡
      //（`04_ReadModel清單.md` §1858、`01_Command清單.md`〈還原被替換的動作〉）。
      // 已經是替換結果的再換一次，原動作仍指向最初那一個 ——
      // 使用者要還原的是他本來選的課表，不是中間某一版。
      replacedFrom: r != null ? (pe.replacedFrom ?? pe.exercise) : pe.replacedFrom,
      replacedPlanned:
          r != null ? (pe.replacedPlanned ?? [...pe.planned]) : pe.replacedPlanned,
      restSeconds: pe.restSeconds,
    );
  }
  return out;
}
