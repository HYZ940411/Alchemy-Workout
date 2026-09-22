/// 訓練調整建議的產生邊界（`[BE-08]`）。
///
/// ## 為什麼要有這一層
///
/// 規格把 LLM 放在軟體邊界**之外**（「AI 為系統呼叫的外部 API」），
/// 只規範呼叫時點、扣點、失敗退點與「AI 僅產出建議、不套用」。
/// 那四件事在 `AppState` 裡早就做好了，缺的一直只是邊界外那一段。
///
/// 這個介面就是那條邊界。**空值代表不接外部 API**，走 `ai_adjust.dart`
/// 的端內規則 —— 既有的一千多條測試全部走這條，一行都不必改。
///
/// ## 為什麼金鑰不在這裡
///
/// 實作端（[CloudAiSuggestionSource]）呼叫的是我們自己的 Cloud Function，
/// 不是 Gemini。金鑰放 Secret Manager，前端連看都看不到 ——
/// Flutter Web 的 `main.dart.js` 會原封不動送到每一位訪客手上，
/// 金鑰寫在裡面等同公開。這是整個 `functions/` 目錄存在的理由。
library;

import '../domain/ai_adjust.dart';
import '../domain/models.dart';

/// 這一份建議是誰產的。
///
/// **兩者都是合法結果**：模型失敗時伺服器會退回規則，使用者照樣拿得到
/// 可用的建議。但分不出來的話，就查不出模型從哪一天開始失常。
enum SuggestionOrigin { gemini, rule }

class RemoteSuggestion {
  final SuggestionOrigin origin;
  final AdjustSuggestion suggestion;

  /// 模型沒能產出時的原因。**空值代表這一次是模型產的。**
  ///
  /// 有值仍然會附上一份可用的建議（伺服器退回規則引擎）—— 但那件事
  /// 一定要講出來。**靜默退回比失敗更難查**：畫面上看起來一切正常，
  /// 只是「AI 變笨了」，而真正的原因（模型退役、金鑰沒權限、配額用盡）
  /// 只存在於一個沒有人會去看的 log 裡。
  final String? error;

  const RemoteSuggestion(this.origin, this.suggestion, {this.error});
}

abstract class AiSuggestionSource {
  /// 依這份課表與方向取得建議。
  ///
  /// [onlyFrom] 之前的動作已經練完了，不送上去也不調整。
  /// 擲出例外代表這一次失敗 —— 呼叫端應走既有的「已扣點後退還」流程。
  ///
  /// [note] 是**使用者自己打的那幾句話**。原樣送給模型當作額外脈絡，
  /// 但它**不能推翻任何驗證規則** —— 伺服器端的逐項驗證在模型回話之後
  /// 才跑，使用者寫什麼都越不過去。
  Future<RemoteSuggestion> suggest({
    required List<PlanExercise> exercises,
    required AdjustIntent intent,
    int onlyFrom = 0,
    String? note,
    AdjustContext? context,

    /// 動作名稱 → 允許替換成的動作。空的代表這一次不換動作。
    Map<String, List<Exercise>> candidates = const {},
  });
}

/// 一位使用者身上與「該怎麼調這份課表」有關的事實。
///
/// **這是 AI 能不能勝過一條規則的全部關鍵。** 在此之前模型只收得到
/// 動作名稱與目標組數 —— 它知道的東西不比 `ai_adjust.dart` 那組規則多，
/// 所以也做不出比它好的事，只能猜一個「降一成」。
///
/// **不送的東西**：暱稱、uid、電子郵件、生日、任何社群內容。
/// 體重與性別有送 —— DOTS 標準化本來就靠它們，少了就算不準。
class AdjustContext {
  final double bodyweightKg;
  final bool isMale;

  /// 經驗級別與健身目標。決定「降一成」對這個人是多還是少。
  final String experience;
  final String goal;

  /// 持有器材。**替換動作的調整依據**（〈02_Aggregate定義〉§持有器材明細）。
  final List<String> equipment;

  /// 動作名稱 → 這個人練它的歷來成績（舊→新，最多取最近幾次）。
  final Map<String, List<({double weight, int reps})>> recent;

  /// 動作名稱 → 可用來替換它的候選動作名稱。
  ///
  /// **候選由前端算好再送**，不把 527 筆動作庫塞進 prompt。模型只能
  /// 從這份清單挑，挑了別的一律丟棄 —— 驗證因此變得簡單且滴水不漏。
  final Map<String, List<String>> candidates;

  const AdjustContext({
    required this.bodyweightKg,
    required this.isMale,
    required this.experience,
    required this.goal,
    this.equipment = const [],
    this.recent = const {},
    this.candidates = const {},
  });

  Map<String, dynamic> toJson() => {
        'bodyweightKg': bodyweightKg,
        'isMale': isMale,
        'experience': experience,
        'goal': goal,
        'equipment': equipment,
        'recent': {
          for (final e in recent.entries)
            e.key: [
              for (final r in e.value) {'weight': r.weight, 'reps': r.reps},
            ],
        },
        if (candidates.isNotEmpty) 'candidates': candidates,
      };
}

/// 送出去的形狀。
///
/// **仍然不送身分**：沒有暱稱、沒有 uid、沒有電子郵件。送的是
/// 「這份課表長什麼樣」與「這個人練起來是什麼水準」。
Map<String, dynamic> encodePlan(
  List<PlanExercise> exercises,
  int onlyFrom, {
  AdjustContext? context,
}) =>
    {
      'exercises': [
        for (var i = onlyFrom; i < exercises.length; i++)
          {
            'name': exercises[i].exercise.name,
            'sets': [
              for (final s in exercises[i].planned)
                {'weight': s.targetWeight, 'reps': s.targetReps},
            ],
          },
      ],
      if (context != null) 'context': context.toJson(),
    };

/// 把回來的東西接回本機的型別。
///
/// **索引要加回 [onlyFrom]**：送上去的是切過的清單，伺服器回的 index
/// 是那份切片裡的位置，而 `applySuggestion` 對的是原始課表的位置。
/// 這裡沒加回去的話，訓練中調整會把建議套到已經練完的動作上。
/// [candidates] 為「動作名稱 → 允許替換成的動作」。**這是第二道驗證** ——
/// 伺服器已經比對過一次，這裡再比一次；模型回一個不在清單裡的動作，
/// 或呼叫端根本沒給候選，就當作沒有替換，只收強度調整。
AdjustSuggestion decodeSuggestion(
  Map<String, dynamic> data,
  List<PlanExercise> exercises,
  AdjustIntent intent,
  int onlyFrom, {
  Map<String, List<Exercise>> candidates = const {},
}) {
  final raw = (data['changes'] as List?) ?? const [];
  final changes = <AdjustChange>[];

  for (final item in raw) {
    final m = (item as Map).cast<String, dynamic>();
    final i = (m['index'] as num).toInt() + onlyFrom;
    if (i < 0 || i >= exercises.length) continue;
    final pe = exercises[i];
    // 名稱對不上就不要 —— 伺服器已經驗過一次，這裡是第二道。
    if (m['name'] != pe.exercise.name) continue;

    final after = [
      for (final s in (m['after'] as List))
        PlannedSet(
          ((s as Map)['weight'] as num).toDouble(),
          (s['reps'] as num).toInt(),
        ),
    ];
    if (after.isEmpty) continue;

    // 替換後的動作。只認候選清單裡的 —— 模型回別的一律當作沒換。
    Exercise? replacement;
    final rn = m['replacement'];
    if (rn is String && rn.isNotEmpty) {
      for (final c in candidates[pe.exercise.name] ?? const <Exercise>[]) {
        if (c.name == rn) {
          replacement = c;
          break;
        }
      }
      if (replacement == null) continue; // 說要換卻換不出來，整筆不要
    }

    final reason = m['reason'];
    changes.add(AdjustChange(
      exerciseIndex: i,
      exerciseName: pe.exercise.name,
      before: [...pe.planned],
      after: after,
      replacement: replacement,
      // 只收字串，而且要有內容 —— 模型回個空字串不該變成畫面上的空行。
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
    ));
  }
  return AdjustSuggestion(intent: intent, changes: changes);
}

SuggestionOrigin originOf(Map<String, dynamic> data) =>
    data['source'] == 'gemini' ? SuggestionOrigin.gemini : SuggestionOrigin.rule;

/// 伺服器回報的失敗原因。沒有就回空值。
String? errorOf(Map<String, dynamic> data) {
  final e = data['error'];
  return e is String && e.trim().isNotEmpty ? e.trim() : null;
}
