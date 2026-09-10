/// 新手任務
///
/// 執行畫面**形似一次訓練，但不是一次訓練** —— 差別在於它不產生任何下游資料：
/// 不走訓練紀錄流程、不產生訓練紀錄與訓練量、不計入排行榜分數、
/// 累積訓練次數與連續訓練天數，也不引入快照、進度條、組間休息與逾時中斷判定。
library;

import 'ability.dart';
import 'platform_config.dart';

/// 一個候選任務項目。由管理員於後台維護的新手任務範本提供。
///
/// 共用〈課表內容結構（共用）〉的三層結構（動作 → 組 → 每組目標），
/// 但**該次執行為單一動作、單一組**，故此處只留一組的目標。
class NoviceTaskItem {
  final String id;
  final String name;
  final Dim dim;
  final String equipment;

  /// 目標量。次數或秒數，由 [inSeconds] 區分。
  final int target;
  final bool inSeconds;

  const NoviceTaskItem({
    required this.id,
    required this.name,
    required this.dim,
    required this.equipment,
    required this.target,
    this.inSeconds = false,
  });

  /// 「腿 · 無需器材 · 1 組 × 12 次」
  String get summary =>
      '${dimNames[dim]} · $equipment · 1 組 × $target ${inSeconds ? '秒' : '次'}';
}

/// 新手任務範本的三個候選動作。**三選一**，非全部完成 ——
/// 目的為讓使用者完整走過一次「選擇 → 執行 → 完成 → 領獎」，做三次只是重複同一段引導。
const kNoviceTemplate = <NoviceTaskItem>[
  NoviceTaskItem(
    id: 'n_squat',
    name: '徒手深蹲',
    dim: Dim.legs,
    equipment: '無需器材',
    target: 12,
  ),
  NoviceTaskItem(
    id: 'n_pushup',
    name: '伏地挺身',
    dim: Dim.chest,
    equipment: '無需器材',
    target: 10,
  ),
  NoviceTaskItem(
    id: 'n_plank',
    name: '棒式',
    dim: Dim.core,
    equipment: '無需器材',
    target: 30,
    inSeconds: true,
  ),
];

// 獎勵內容屬〈獎勵定義 Aggregate〉，由管理員維護。
int get kNoviceExp => platformConfig.i('reward', 'noviceExp');
int get kNoviceCoin => platformConfig.i('reward', 'noviceCoin');

/// 永久 AI 點數，不重置不過期。
int get kNoviceAiCredits => platformConfig.i('reward', 'noviceAi');
