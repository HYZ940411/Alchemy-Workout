/// 平台課表的資料規格。
///
/// 由《健身計劃.csv》產生（見 tools/gen_platform_plans.py），
/// 與 [WorkoutPlan] 分開是刻意的：
///
/// [WorkoutPlan] 是**訓練時要用的東西** —— 動作、組數、目標值，
/// 進了訓練流程就只需要這些。這裡多帶的是**課表的說明性內容**：
/// 介紹、使用說明、負荷、訓練效果、技術特點、學理依據。
/// 那些是課表詳情頁要呈現的，訓練中一個字都用不到。
/// 合成一個類別的話，`WorkoutPlan` 會被六段長文字撐大，
/// 而每一次訓練都要拖著它們走。
library;

import 'models.dart';

/// [PlanUnit] 定義在 `models.dart` —— 它是「一組怎麼計量」，
/// 訓練流程與畫面都要用，不只是 CSV 的事。從這裡轉出去，
/// 既有的 import 不必跟著改。
export 'models.dart' show PlanUnit;

/// 課表裡的一個動作。
class PlanItemSpec {
  /// 對應 `kPlatformExercises` 的動作 ID。
  final String exerciseId;
  final int sets;

  /// 每組的次數或秒數，依 [unit] 判讀。
  final int amount;
  final PlanUnit unit;
  final int restSeconds;

  /// 目標重量（公斤）。0 代表「不指定」——《健身計劃.csv》那 27 份全部是 0，
  /// 由使用者自己填。
  ///
  /// **2026-09-29 新增。** 原本沒有這一欄，而四份寫死在 `kPlans` 裡的官方
  /// 課表帶著目標重量（臥推 60、深蹲 80…）。要把它們搬上雲、讓後台改得動，
  /// 規格就得裝得下它們現有的內容 —— 否則搬家等於把處方改掉，
  /// 而**訓練處方不是我該替使用者決定的東西**（CLAUDE.md 第 7 條）。
  final double weight;

  const PlanItemSpec(
    this.exerciseId,
    this.sets,
    this.amount,
    this.unit,
    this.restSeconds, {
    this.weight = 0,
  });
}

/// 一份平台課表。
class PlatformPlanSpec {
  final String id;
  final String name;

  /// 學員級 / 戰士級 / 精銳級 / 功能重啟級。
  final String level;

  /// 階級門檻。空值為不設限。
  final int? requiredRank;

  /// 會員權益是否解得開。
  ///
  /// **2026-09-29 新增**，理由同 [unlockCoins]：四份官方課表裡
  /// 「進階：爆發力週期」帶著這個旗標，規格裝不下就等於搬家時弄丟一條
  /// 解鎖途徑。
  final bool memberUnlockable;

  /// 金幣解鎖價格。空值＝不提供這條解鎖方式。
  ///
  /// **2026-09-29 新增（`[BE-12b]`）。** 在此之前這個欄位只活在
  /// [WorkoutPlan] 上，而後台的「設定訓練計畫」改的正是它 ——
  /// 於是那個 Command 的改動無處可存，寫回雲端時會被靜靜丟掉。
  /// 27 份 CSV 課表本身沒有這個資料（來源沒有這一欄），一律為空值；
  /// 它存在的意義是**讓後台改得動的東西存得下來**。
  final int? unlockCoins;

  final String equipmentTier;

  /// 適用經驗與適用目標 —— 訓練計畫推薦的兩個比對維度（`[QA-02l]`）。
  ///
  /// **空集合的意思是「不篩選」，不是「不適用」**：`recommendPlan` 把空集合
  /// 視為全部符合。27 份課表原本兩欄皆空，於是每一份都宣稱適合所有人，
  /// 推薦實際上只靠器材在篩。
  ///
  /// 兩欄的來源不同，見 `tools/gen_platform_plans.py`：
  /// 經驗由級別機械對應；目標依各課表自己寫的「訓練效果」欄判定
  /// （2026-09-18 使用者逐列審核通過）。
  final List<String> suitableExperience;
  final List<String> suitableGoals;

  /// 以下六段為課表詳情頁的內容，原樣取自資料來源。
  final String duration;
  final String intro;
  final String howTo;
  final String load;
  final String effect;
  final String technique;

  /// 學理依據。**這一欄不可為空** —— 一份說得出依據的課表與一份
  /// 憑空編的課表，對使用者是兩件不同的東西。
  final String reference;

  final List<PlanItemSpec> items;

  const PlatformPlanSpec({
    required this.id,
    required this.name,
    required this.level,
    required this.requiredRank,
    this.unlockCoins,
    this.memberUnlockable = false,
    required this.equipmentTier,
    this.suitableExperience = const [],
    this.suitableGoals = const [],
    required this.duration,
    required this.intro,
    required this.howTo,
    required this.load,
    required this.effect,
    required this.technique,
    required this.reference,
    required this.items,
  });

  /// 套用後台「設定訓練計畫」改得動的那兩個欄位。
  ///
  /// **兩個都是必填的具名參數**，不是 `copyWith` 那種選填 ——
  /// 這兩欄都可以被設成空值（階級留空＝不設限、價格留空＝不提供該解鎖
  /// 方式），選填參數分不出「沒給」與「設成空值」，那正是會把
  /// 「使用者把價格清掉」默默吃掉的寫法。
  PlatformPlanSpec withConfig({
    required int? requiredRank,
    required int? unlockCoins,
  }) =>
      PlatformPlanSpec(
        id: id,
        name: name,
        level: level,
        requiredRank: requiredRank,
        unlockCoins: unlockCoins,
        memberUnlockable: memberUnlockable,
        equipmentTier: equipmentTier,
        suitableExperience: suitableExperience,
        suitableGoals: suitableGoals,
        duration: duration,
        intro: intro,
        howTo: howTo,
        load: load,
        effect: effect,
        technique: technique,
        reference: reference,
        items: items,
      );
}
