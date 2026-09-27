/// 平台級設定（〈平台設定維護〉的 16 個管理員 Command）
///
/// 本檔只承載**納入軟體邊界**者 —— 判準為「該設定改動後，是否會改變使用者
/// 已取得或將取得的實質內容」。值域清單類（健身目標、器材明細、檢舉理由…）
/// 留在系統邊界之外，不建 Command 與 Event。
///
/// 三條貫穿全部 16 個 Command 的規則：
/// 一、Precondition：管理員狀態為生效中，且權限組涵蓋「平台設定」。
/// 二、Event 一律攜帶：所變更的項目識別碼、變更前的值、變更後的值。
/// 三、Postcondition 一律**不追溯既有紀錄**。
library;

/// 一筆設定變更紀錄。
///
/// 既已承諾「調整不追溯既有紀錄」，就須有可稽核的依據記錄「何時改的、改成什麼」——
/// 否則使用者質疑「上個月訓練拿 30 金幣、這個月只有 20」時無從查證。
class SettingChange {
  /// 導致的 Event，例：管理員已設定能力值參數。
  final String event;

  /// 所變更的項目識別碼。
  final String item;
  final String before;
  final String after;
  final DateTime at;

  /// 執行者的管理員 ID。
  final String by;

  const SettingChange({
    required this.event,
    required this.item,
    required this.before,
    required this.after,
    required this.at,
    required this.by,
  });
}

/// 一個可調參數。
class SettingParam {
  final String key;
  final String label;
  final String? unit;
  final String? hint;

  /// 整數參數的輸入與呈現不帶小數。
  final bool isInt;
  num value;

  SettingParam({
    required this.key,
    required this.label,
    required this.value,
    this.unit,
    this.hint,
    this.isInt = true,
  });

  String get display => isInt ? '${value.round()}' : '$value';
}

/// 一組參數 —— 對應一個 Command 與一個 Event。
class SettingGroup {
  final String id;
  final String command;
  final String event;

  /// 該組 Postcondition 的不追溯範圍，逐組明寫。
  final String note;
  final List<SettingParam> params;

  /// 不變條件。回傳非空字串即為違反，畫面擋下儲存。
  final String? Function(Map<String, num>)? invariant;

  SettingGroup({
    required this.id,
    required this.command,
    required this.event,
    required this.note,
    required this.params,
    this.invariant,
  });

  SettingParam param(String key) => params.firstWhere((p) => p.key == key);
  Map<String, num> get values => {for (final p in params) p.key: p.value};
}

/// 六階門檻的預設子節點跨距。每階切三個小節點（X / X+ / X++），
/// 跨距比例取自〈能力值等級〉的分段表，非平均切分。
const _subSpans = <List<int>>[
  [30, 40, 30], // E
  [50, 50, 50], // D
  [65, 70, 65], // C
  [65, 70, 65], // B
  [65, 70, 65], // A
  [50, 50, 50], // S
];

const kMajorGrades = <String>['E', 'D', 'C', 'B', 'A', 'S'];

/// 六階門檻的預設上界。
const kDefaultTierUppers = <int>[99, 249, 449, 649, 849, 999];

class PlatformConfig {
  final List<SettingChange> log = [];

  late final List<SettingGroup> groups = [
    _ability,
    _rank,
    _reward,
    _membership,
    _instructorGate,
    _exam,
    _makeup,
    _taskPool,
    _team,
    _account,
    _commerce,
  ];

  // --- 能力值設定 Aggregate ---
  final _ability = SettingGroup(
    id: 'ability',
    command: '設定能力值參數',
    event: '管理員已設定能力值參數',
    note:
        '六階門檻調整後即時生效，全平台使用者的等級同時改變；點數本身不重算。'
        '相對強度係數與體重係數調整不追溯既有點數。'
        '退步參數調整不追溯已發生的退步，僅影響其後的計算。',
    params: [
      // 兩者由〈錨點分佈〉的兩個端點反解而得（2026-08-19 定案）：
      // 以 80kg 男性、槓鈴臥推（相對強度係數 1.0）為基準人，
      // DOTS 係數 0.6895；E 底 0.5× 體重 → 0 點、A 底 1.0× 體重 → 650 點。
      //
      // **校準時兩個一起動**：基準值移動起跑線、映射係數改變放大倍率，
      // 單改其一會使一端跑掉。
      SettingParam(
        key: 'baseline',
        label: '基準值',
        value: 27.6,
        isInt: false,
        hint: '仿射映射的截距。由 E 底反解（40 × 0.6895 ＝ 27.6）—— '
            '未訓練者的 DOTS 分數平移至接近 0。',
      ),
      SettingParam(
        key: 'mapping',
        label: '映射係數',
        value: 23.6,
        isInt: false,
        hint: '仿射映射的斜率，由 A 底反解（650 ÷ (55.16 − 27.58) ＝ 23.6），'
            '對齊六階門檻。',
      ),
      SettingParam(key: 'initial', label: '六維初始值', value: 10, unit: '點'),
      SettingParam(key: 'cap', label: '點數硬截斷上限', value: 999, unit: '點'),
      SettingParam(
        key: 'firstCap',
        label: '首次訓練的封頂點數',
        value: 450,
        unit: '點',
        hint: '該維第一次訓練的點數上限，六維各自計算。',
      ),
      SettingParam(
        key: 'catchUp',
        label: '補格門檻',
        value: 0.80,
        isInt: false,
        hint: '本場實測值達當前點數的此比例以上才補格。',
      ),
      SettingParam(key: 'epley', label: 'Epley 次數上限', value: 10, unit: '下'),
      SettingParam(
        key: 'decayPct',
        label: '退步百分比',
        value: 0.05,
        isInt: false,
        hint: '每滿一個退步間隔未訓練該維，該維退此比例。',
      ),
      SettingParam(
        key: 'decayHours',
        label: '退步間隔',
        value: 240,
        unit: '小時',
        hint: '六維各自獨立計時，自該維最後訓練日的日界起算。'
            '240 小時（10 天）使每週練一次者不觸發退步。',
      ),
      SettingParam(
        key: 'floorDrop',
        label: '退步下限的主階降幅',
        value: 2,
        unit: '主階',
        hint: '下限 ＝ 本次中斷前點數所處節點的主階降此階數、小節點保留之下緣，'
            '且不低於六維初始值。',
      ),
      SettingParam(
        key: 'recover',
        label: '回歸任務回復比例',
        value: 0.50,
        isInt: false,
        hint: '完成回歸任務時，各維各自回復本次中斷累積退步量的此比例。',
      ),
      for (var i = 0; i < 6; i++)
        SettingParam(
          key: 'tier$i',
          label: '${kMajorGrades[i]} 階上界',
          value: kDefaultTierUppers[i],
          unit: '點',
        ),
    ],
    invariant: (v) {
      final t = [for (var i = 0; i < 6; i++) v['tier$i']!.round()];
      // 六階門檻須嚴格遞增。連續無空隙由「前一階上界 +1 即次一階下界」的
      // 推導方式保證（下界不獨立儲存），故此處只驗遞增。
      for (var i = 1; i < 6; i++) {
        if (t[i] <= t[i - 1]) {
          return '六階門檻須嚴格遞增：${kMajorGrades[i]} 階上界須大於 ${kMajorGrades[i - 1]} 階上界。';
        }
      }
      // 每階至少 3 點，否則切不出三個小節點。
      if (t[0] < 2) return 'E 階上界至少為 2（每階須容得下三個小節點）。';
      for (var i = 1; i < 6; i++) {
        if (t[i] - t[i - 1] < 3) {
          return '${kMajorGrades[i]} 階的跨距至少 3 點（須容得下三個小節點）。';
        }
      }
      if (t[5] != v['cap']!.round()) {
        return 'S 階上界須等於點數硬截斷上限（${v['cap']!.round()}）。';
      }
      if (v['initial']! > v['cap']!) return '六維初始值不得高於點數硬截斷上限。';
      if (v['firstCap']! > v['cap']!) return '首次封頂點數不得高於點數硬截斷上限。';
      if (v['mapping']! <= 0) return '映射係數須大於 0。';
      if (v['catchUp']! <= 0 || v['catchUp']! > 1) return '補格門檻須介於 0 與 1 之間。';
      if (v['epley']! < 1) return 'Epley 次數上限須至少為 1。';
      if (v['decayPct']! <= 0 || v['decayPct']! >= 1) {
        return '退步百分比須介於 0 與 1 之間。';
      }
      if (v['decayHours']! < 1) return '退步間隔須至少為 1 小時。';
      if (v['floorDrop']! < 0 || v['floorDrop']! > 5) {
        return '退步下限的主階降幅須介於 0 與 5 之間（共六個主階）。';
      }
      // 回復比例須嚴格小於 1：Postcondition 為「不回復至退步前水準」。
      if (v['recover']! <= 0 || v['recover']! >= 1) {
        return '回歸任務回復比例須介於 0 與 1 之間（不得回復至退步前水準）。';
      }
      return null;
    },
  );

  // --- 階級門檻 ---
  final _rank = SettingGroup(
    id: 'rank',
    command: '設定階級門檻',
    event: '管理員已設定階級門檻',
    note: '階級單調遞增、永不下降 —— 門檻調升不使既有階級回退。',
    params: [
      SettingParam(
        key: 'fullExp',
        label: '滿階累計經驗值',
        value: 8340,
        unit: 'EXP',
        hint: '99 階所需的累計經驗值，即公式的係數。',
      ),
      SettingParam(
        key: 'exponent',
        label: '曲線指數',
        value: 2.0,
        isInt: false,
        hint: 'C(n) ＝ 滿階經驗值 × ((n−1)／98) 的此次方。',
      ),
    ],
    invariant: (v) {
      if (v['fullExp']! <= 0) return '滿階累計經驗值須大於 0。';
      if (v['exponent']! <= 0) return '曲線指數須大於 0。';
      return null;
    },
  );

  // --- 獎勵定義 ---
  final _reward = SettingGroup(
    id: 'reward',
    command: '設定獎勵定義',
    event: '管理員已設定獎勵定義',
    note: '獎勵定義調整不改動既有發放紀錄。',
    params: [
      SettingParam(
        key: 'trainExp',
        label: '訓練獎勵經驗值',
        value: 30,
        unit: 'EXP',
        hint: '當日僅發一次。',
      ),
      SettingParam(key: 'trainCoin', label: '訓練獎勵金幣基底', value: 30, unit: '金幣'),
      SettingParam(key: 'checkInExp', label: '簽到獎勵經驗值', value: 10, unit: 'EXP'),
      SettingParam(key: 'checkInCoin', label: '簽到獎勵金幣', value: 10, unit: '金幣'),
      SettingParam(
        key: 'returnExp',
        label: '回歸任務獎勵經驗值',
        value: 50,
        unit: 'EXP',
        hint: '約為單次訓練獎勵的 1.67 倍 —— 比日常訓練更有感，作為「歡迎回來」的誠意。',
      ),
      SettingParam(key: 'returnCoin', label: '回歸任務獎勵金幣', value: 50, unit: '金幣'),
      SettingParam(
        key: 'returnCredit',
        label: '回歸任務獎勵 AI 點數',
        value: 1,
        unit: '點',
      ),
      SettingParam(key: 'noviceExp', label: '新手任務獎勵經驗值', value: 100, unit: 'EXP'),
      SettingParam(key: 'noviceCoin', label: '新手任務獎勵金幣', value: 100, unit: '金幣'),
      SettingParam(
        key: 'rankCut',
        label: '排行獎勵名次門檻',
        value: 10,
        unit: '名',
        hint: '組內名次在此之內者才發放排行獎勵。四個排行榜共用同一張獎勵表。',
      ),
      SettingParam(key: 'rank1Coin', label: '排行第 1 名金幣', value: 300, unit: '金幣'),
      SettingParam(key: 'rank1Exp', label: '排行第 1 名經驗值', value: 120, unit: 'EXP'),
      SettingParam(key: 'rank2Coin', label: '排行第 2 名金幣', value: 200, unit: '金幣'),
      SettingParam(key: 'rank2Exp', label: '排行第 2 名經驗值', value: 80, unit: 'EXP'),
      SettingParam(key: 'rank3Coin', label: '排行第 3 名金幣', value: 120, unit: '金幣'),
      SettingParam(key: 'rank3Exp', label: '排行第 3 名經驗值', value: 50, unit: 'EXP'),
      SettingParam(key: 'rankRestCoin', label: '排行其餘名次金幣', value: 60, unit: '金幣'),
      SettingParam(key: 'rankRestExp', label: '排行其餘名次經驗值', value: 25, unit: 'EXP'),
      // 互動獎勵**只發經驗值，不發金幣**。四項上限為模型明訂的數字，
      // 經驗值數額模型未給，此處取一組不會讓互動蓋過訓練的值。
      SettingParam(key: 'capPost', label: '發文獎勵每日上限', value: 1, unit: '次'),
      SettingParam(key: 'capShare', label: '分享獎勵每日上限', value: 3, unit: '次'),
      SettingParam(key: 'capLike', label: '按讚獎勵每日上限', value: 10, unit: '次'),
      SettingParam(key: 'capComment', label: '留言獎勵每日上限', value: 5, unit: '次'),
      SettingParam(key: 'postExp', label: '發文獎勵經驗值', value: 10, unit: 'EXP'),
      SettingParam(key: 'shareExp', label: '分享獎勵經驗值', value: 10, unit: 'EXP'),
      SettingParam(key: 'likeExp', label: '按讚獎勵經驗值', value: 2, unit: 'EXP'),
      SettingParam(key: 'commentExp', label: '留言獎勵經驗值', value: 5, unit: 'EXP'),
      SettingParam(
        key: 'noviceAi',
        label: '新手任務獎勵 AI 點數',
        value: 3,
        unit: '點',
        hint: '永久點數，不重置不過期。掛在新手任務完成而非註冊當下 ——'
            '註冊獎勵已有金幣可換單次 AI 使用權限。',
      ),
    ],
    invariant: (v) {
      if (v.values.any((x) => x < 0)) return '獎勵數額不得為負。';
      if (v['rankCut']! < 1) return '排行獎勵名次門檻至少為 1。';
      // 名次愈前獎勵不得愈少，否則使用者會希望自己名次掉下去。
      if (v['rank1Coin']! < v['rank2Coin']! ||
          v['rank2Coin']! < v['rank3Coin']! ||
          v['rank3Coin']! < v['rankRestCoin']!) {
        return '排行獎勵須隨名次遞減。';
      }
      return null;
    },
  );

  // --- 會員權益 ---
  final _membership = SettingGroup(
    id: 'membership',
    command: '設定會員權益',
    event: '管理員已設定會員權益',
    note: '調整不影響已生效的訂閱 —— 既有訂閱於當期到期前維持原權益與原價。',
    params: [
      SettingParam(key: 'monthly', label: '月訂價格', value: 190, unit: 'NT\$'),
      SettingParam(key: 'yearly', label: '年訂價格', value: 1790, unit: 'NT\$'),
      SettingParam(
        key: 'credits',
        label: '每月 AI 點數配額',
        value: 20,
        unit: '點',
        hint: '同月不重複配發。',
      ),
    ],
    invariant: (v) {
      if (v['monthly']! <= 0 || v['yearly']! <= 0) return '訂閱價格須大於 0。';
      if (v['yearly']! >= v['monthly']! * 12) {
        return '年訂價格須低於月訂價格 ×12，否則年訂無誘因。';
      }
      if (v['credits']! < 0) return 'AI 點數配額不得為負。';
      return null;
    },
  );

  // --- 教官初審設定 Aggregate ---
  final _instructorGate = SettingGroup(
    id: 'instructorGate',
    command: '設定教官初審門檻',
    event: '管理員已設定教官初審門檻',
    note: '設定調整不追溯既有申請 —— 已通過或已駁回者不因門檻變動而改判。',
    params: [
      SettingParam(key: 'rank', label: '需求階級', value: 20, unit: '階'),
      SettingParam(key: 'workouts', label: '需求累積訓練次數', value: 50, unit: '次'),
      SettingParam(
        key: 'qualityPass',
        label: '品質分通過門檻',
        value: 60,
        unit: '分',
        hint: 'AI 訓練品質評分的加權平均須達此值。',
      ),
      SettingParam(
        key: 'qualityDiscount',
        label: '品質分折抵門檻',
        value: 80,
        unit: '分',
        hint: '達此值者，需求累積訓練次數改用下一列；階級門檻不折抵。',
      ),
      SettingParam(key: 'discounted', label: '折抵後的需求次數', value: 30, unit: '次'),
      SettingParam(
        key: 'veto',
        label: '紀錄合理性一票否決門檻',
        value: 40,
        unit: '分',
        hint: '該單項低於此值即駁回，不論加權平均為何。',
      ),
      // 三維權重（規格明訂為平台級可調參數，但沒給初始值）。
      //
      // **合理性壓重，是因為評分改由 Gemini 產出**（使用者裁決 2026-09-25）。
      // 模型看到「數字漂亮」的紀錄很容易把完成率與規律性給高，
      // 而合理性抓的是造假 —— 那是唯一「做錯會讓不該當教官的人當上」的維度。
      SettingParam(
          key: 'wCompletion', label: '權重：訓練完成率', value: 25, unit: '%'),
      SettingParam(
          key: 'wConsistency', label: '權重：訓練規律性', value: 25, unit: '%'),
      SettingParam(
          key: 'wSanity', label: '權重：紀錄合理性', value: 50, unit: '%'),
    ],
    invariant: (v) {
      if (v['discounted']! > v['workouts']!) {
        return '折抵須為放寬：折抵後的需求次數不得高於需求累積訓練次數。';
      }
      if (v['qualityDiscount']! <= v['qualityPass']!) {
        return '品質分折抵門檻須高於品質分通過門檻。';
      }
      if (v['rank']! < 1) return '需求階級至少為 1。';
      // 權重全為 0 的話加權平均永遠是 0，每個人都會被品質分門檻擋下 ——
      // 那不是「調參數」，是把整條路關掉，而且沒有人看得出為什麼。
      if (v['wCompletion']! + v['wConsistency']! + v['wSanity']! <= 0) {
        return '三維權重不得全為 0。';
      }
      return null;
    },
  );

  // --- 教官測驗設定 Aggregate ---
  final _exam = SettingGroup(
    id: 'exam',
    command: '設定教官測驗',
    event: '管理員已設定教官測驗',
    note: '設定調整不改動任何已完成作答的既有測驗結果。',
    params: [
      SettingParam(
        key: 'mcCount',
        label: '選擇題題數',
        value: 20,
        unit: '題',
        hint: '自題庫隨機抽取。',
      ),
      SettingParam(key: 'saCount', label: '簡答題題數', value: 3, unit: '題'),
      SettingParam(
        key: 'mcPass',
        label: '選擇題及格標準',
        value: 80,
        unit: '%',
        hint: '及格採雙門檻：選擇題達此比例，且簡答題全數通過。',
      ),
    ],
    invariant: (v) {
      if (v['mcCount']! < 1 || v['saCount']! < 1) {
        return '兩種題型皆須至少 1 題 —— 簡答題歸零將使人工審核形同虛設。';
      }
      if (v['mcPass']! <= 0 || v['mcPass']! > 100) {
        return '及格標準須介於 1% 與 100% 之間。';
      }
      return null;
    },
  );

  // --- 商品與訂單 ---
  final _commerce = SettingGroup(
    id: 'commerce',
    command: '設定商品資訊',
    event: '管理員已設定商品資訊',
    note: '預扣保留時間調整不影響已成立的訂單 —— 每筆訂單於確認購買當下即鎖定自己的到期時點。',
    params: [
      SettingParam(
          key: 'holdMinutes',
          label: '庫存預扣保留時間',
          value: 15,
          unit: '分鐘',
          hint: '確認購買時預扣庫存，逾時未付款自動釋放。'),
      SettingParam(
          key: 'coinsPerNtd',
          label: '金幣對法幣比率',
          value: 5,
          unit: '金幣／元',
          hint: '金幣不足時的補差額試算依此換算；訂單成立時鎖定當時比率。'),
      SettingParam(
          key: 'customPlanBase',
          label: '自訂訓練名額初始值',
          value: 2,
          unit: '份',
          hint: '初始為 2 而非 1：AI 調整落地的自訂訓練共用同一名額，'
              '只有 1 個時新使用者第一次遇到器材不合就被佔滿。'),
      SettingParam(
          key: 'customPlanMax',
          label: '自訂訓練名額上限',
          value: 5,
          unit: '份',
          hint: '非會員的上限。會員不受名額限制。'),
      SettingParam(
          key: 'planUnlockCoins',
          label: '進階訓練計畫解鎖價格',
          value: 600,
          unit: '金幣',
          hint: '統一定價，不逐計畫區分；調整不追溯已購買的訂單，'
              '不補差額亦不退款。'),
    ],
    invariant: (v) {
      if (v['holdMinutes']! <= 0) return '預扣保留時間須大於 0。';
      if (v['coinsPerNtd']! <= 0) return '金幣對法幣比率須大於 0。';
      if (v['planUnlockCoins']! <= 0) return '進階訓練計畫解鎖價格須大於 0。';
      if (v['customPlanBase']! < 1) return '自訂訓練名額初始值須至少為 1。';
      if (v['customPlanMax']! < v['customPlanBase']!) {
        return '自訂訓練名額上限不得低於初始值。';
      }
      return null;
    },
  );

  // --- 補簽設定 Aggregate ---
  // --- 每日任務池（同時承載限時任務）---
  final _taskPool = SettingGroup(
    id: 'taskPool',
    command: '設定每日任務池',
    event: '管理員已設定每日任務池',
    note: '任務池調整不改動任何使用者當日已指派的任務。',
    params: [
      SettingParam(
        key: 'drawCount',
        label: '每日抽取數量',
        value: 3,
        unit: '項',
        hint: '每日重置時自任務池隨機抽取這麼多項指派給個人。'
            '允許與前一日重複，不做去重；池子不足時抽出全部。',
      ),
    ],
    invariant: (v) =>
        v['drawCount']! < 1 ? '每日抽取數量至少為 1。' : null,
  );

  // --- 團隊 ---
  final _team = SettingGroup(
    id: 'team',
    command: '設定團隊參數',
    event: '管理員已設定團隊參數',
    note: '調整不追溯已在冷卻中的使用者 —— 其剩餘時間依退出當時的長度計算。',
    params: [
      SettingParam(
        key: 'cooldownHours',
        label: '換隊冷卻期',
        value: 12,
        unit: '小時',
        hint: '職責僅為避免同一日內反覆進出造成的成員名單與分數抖動，'
            '不負責防止月底跳槽蹭排行獎勵。',
      ),
      SettingParam(
        key: 'graceHours',
        label: '無懲罰退出窗口',
        value: 3,
        unit: '小時',
        hint: '**加入**團隊後這段時間內退出不觸發冷卻期。誤入團隊是真實情境，'
            '冷卻期不應懲罰誤觸；自己建立的團隊不適用（那不是誤入）。',
      ),
    ],
    invariant: (v) {
      if (v['cooldownHours']! < 1) return '換隊冷卻期至少 1 小時。';
      if (v['graceHours']! < 0) return '無懲罰退出窗口不得為負。';
      if (v['graceHours']! >= v['cooldownHours']!) {
        return '無懲罰退出窗口須短於換隊冷卻期，否則冷卻期形同不存在。';
      }
      return null;
    },
  );

  // --- 帳號生命週期 ---
  final _account = SettingGroup(
    id: 'account',
    command: '設定帳號生命週期參數',
    event: '管理員已設定帳號生命週期參數',
    note: '冷靜期長度調整不影響已在冷靜期中的申請 —— 其剩餘天數依申請當時的長度計算。',
    params: [
      SettingParam(
        key: 'coolingDays',
        label: '刪除冷靜期',
        value: 30,
        unit: '天',
        hint: '自刪除申請時戳起算；期間帳號停用、資料全數保留、不執行任何刪除。'
            'Apple 要求於申請當下明確告知需時多久。',
      ),
    ],
    invariant: (v) =>
        v['coolingDays']! < 1 ? '冷靜期至少為 1 天。' : null,
  );

  final _makeup = SettingGroup(
    id: 'makeup',
    command: '設定補簽回補範圍',
    event: '管理員已設定補簽回補範圍',
    note: '回補範圍調整不追溯既有補簽 —— 已完成的補簽不因範圍縮小而撤銷。',
    params: [
      SettingParam(
        key: 'days',
        label: '回補範圍',
        value: 7,
        unit: '天',
        hint: '判定式為「距今天數 ≤ 回補範圍」，含端點。',
      ),
      SettingParam(
        key: 'ticketCap',
        label: '補簽券持有上限',
        value: 5,
        unit: '張',
        hint: '無有效期限。達上限後不再入手，已持有者不受影響。',
      ),
      SettingParam(
        key: 'ticketPrice',
        label: '補簽券售價',
        value: 150,
        unit: '金幣',
        hint: '訂定基準為四天份的簽到金幣（4 × 10）＋ 四天份的訓練金幣（4 × 30）。',
      ),
    ],
    invariant: (v) {
      if (v['days']! <= 0) return '回補範圍須大於 0。';
      if (v['ticketCap']! <= 0) return '補簽券持有上限須大於 0。';
      // 不變條件：售價須高於單日簽到獎勵的金幣數 ——
      // 否則形成「買券 → 補簽 → 拿回更多金幣」的套利迴圈。
      final checkIn = platformConfig.i('reward', 'checkInCoin');
      if (v['ticketPrice']! <= checkIn) {
        return '補簽券售價須高於單日簽到獎勵的 $checkIn 金幣，'
            '否則形成「買券 → 補簽 → 拿回更多金幣」的套利迴圈。';
      }
      return null;
    },
  );

  /// 出廠預設值 —— 於建構時複製一份，供還原使用。
  late final Map<String, Map<String, num>> _defaults = {
    for (final g in groups) g.id: {...g.values}
  };

  /// 還原全部參數至出廠預設，並清空異動紀錄。
  void reset() {
    for (final g in groups) {
      for (final p in g.params) {
        p.value = _defaults[g.id]![p.key]!;
      }
    }
    log.clear();
  }

  SettingGroup group(String id) => groups.firstWhere((g) => g.id == id);
  num v(String groupId, String key) => group(groupId).param(key).value;
  int i(String groupId, String key) => v(groupId, key).round();
  double d(String groupId, String key) => v(groupId, key).toDouble();

  /// 六階門檻的上界，依序為 E…S。
  List<int> get tierUppers => [
    for (var n = 0; n < 6; n++) i('ability', 'tier$n'),
  ];
}

/// 換隊冷卻期。平台級可調參數。
Duration get kTeamSwitchCooldown =>
    Duration(hours: platformConfig.i('team', 'cooldownHours'));

/// 無懲罰退出窗口。**只給「加入」**，不給自己建立的團隊。
Duration get kTeamLeaveGrace =>
    Duration(hours: platformConfig.i('team', 'graceHours'));

/// 帳號刪除的冷靜期長度（天）。平台級可調參數。
int get kDeletionCoolingDays => platformConfig.i('account', 'coolingDays');

/// 全站唯一的平台設定。六階門檻調整後即時生效，故為可變的全域狀態。
final platformConfig = PlatformConfig();

/// 依當前六階門檻推導 18 個小節點的區間。
///
/// 每階切三個小節點，跨距按 [_subSpans] 的比例分配 —— 非平均切分，
/// 以求預設門檻下重現〈能力值等級〉的分段表。
List<List<int>> subNodeBounds() {
  final uppers = platformConfig.tierUppers;
  final out = <List<int>>[];
  var lower = 0;
  for (var t = 0; t < 6; t++) {
    final upper = uppers[t];
    final span = upper - lower + 1;
    final w = _subSpans[t];
    final total = w[0] + w[1] + w[2];
    final c1 = lower + (span * w[0] / total).round() - 1;
    final c2 = lower + (span * (w[0] + w[1]) / total).round() - 1;
    out
      ..add([lower, c1])
      ..add([c1 + 1, c2])
      ..add([c2 + 1, upper]);
    lower = upper + 1;
  }
  return out;
}

/// 教官資格初審的判定結果（〈教官初審設定 Aggregate〉）。
///
/// 兩條門檻須同時成立；品質分折抵僅折抵累積訓練次數，階級門檻不折抵；
/// 紀錄合理性的一票否決獨立於加權平均，兩者並存。
class InstructorGate {
  final int requiredRank;
  final int requiredWorkouts;
  final bool discounted;
  final bool rankOk;
  final bool workoutsOk;
  final bool qualityOk;
  final bool vetoed;

  const InstructorGate({
    required this.requiredRank,
    required this.requiredWorkouts,
    required this.discounted,
    required this.rankOk,
    required this.workoutsOk,
    required this.qualityOk,
    required this.vetoed,
  });

  /// **按得下「申請教官資格」的條件** —— 只看階級與累積訓練次數。
  ///
  /// 品質評分**不在這裡**。規格的順序是
  /// 「使用者已申請教官權限」→ 系統初審 → 系統「分析歷史訓練品質」
  /// （〈教官申請流程〉，2026-09-26 使用者糾正過一次）——
  /// 評分發生在申請**之後**，而且屬於那一筆申請
  /// （請求識別碼 ＝ 使用者 ID ＋ 教官申請 ID）。
  ///
  /// 在此之前申請鍵讀的是 [passed]，那包含 `qualityOk` 與 `vetoed`。
  /// 還沒申請的人 `quality` 是空值 → 分數當 0 → `qualityOk` 為假、
  /// 一票否決成立 —— **於是門檻達標了也永遠按不下申請鍵**。
  /// 使用者回報「階級次數有達標，但是無法申請」。
  bool get canApply => rankOk && workoutsOk;

  /// 完整的初審結果。**申請之後**才判得出來（要有品質評分）。
  bool get passed => canApply && qualityOk && !vetoed;
}

InstructorGate evaluateInstructorGate({
  required int rank,
  required int workouts,
  required int quality,
  required int sanity,
}) {
  final c = platformConfig;
  final discounted = quality >= c.i('instructorGate', 'qualityDiscount');
  final needWorkouts = discounted
      ? c.i('instructorGate', 'discounted')
      : c.i('instructorGate', 'workouts');
  return InstructorGate(
    requiredRank: c.i('instructorGate', 'rank'),
    requiredWorkouts: needWorkouts,
    discounted: discounted,
    rankOk: rank >= c.i('instructorGate', 'rank'),
    workoutsOk: workouts >= needWorkouts,
    qualityOk: quality >= c.i('instructorGate', 'qualityPass'),
    vetoed: sanity < c.i('instructorGate', 'veto'),
  );
}
