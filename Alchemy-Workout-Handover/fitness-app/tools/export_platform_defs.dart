import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/data/platform_data.dart';

/// 把**打包在本地的平台資料**（[BundledPlatformData]）序列化成 JSON 建置產物，
/// 交給 `tools/upload_platform_data.py` 上傳 Firestore，作為上雲的初始種子（[BE-12]）。
///
/// 涵蓋全部五個平台集合：動作庫、訓練計畫、成就定義、每日任務池、平台設定
/// （獎勵定義併入 platform_config 的 reward 群組）。
///
/// **為什麼種子取自 bundle 而非重跑 CSV**：`import_exercises.py` 重跑會因
/// OVERRIDES 的鍵已對不上 CSV 現況，把 15 個被 `ex('squat')` 等硬引用的友善
/// 動作 ID 換成 pNNN、並丟失校準過的相對強度與休息秒數（見 PROGRESS.md 硬性
/// 規則 1 的警告）。committed 的 `.g.dart` 才是正典，且正是 App 離線後備所用。
/// 從 [BundledPlatformData] 匯出可保證**雲端內容與 App 打包、測試夾具三者完全一致**，
/// 並與 App 端的反序列化共用同一組 `*ToMap`／`*FromDoc` 定義。
///
/// `import_exercises.py --upload`／`gen_platform_plans.py --upload` 仍保留
/// 「tools 寫進 Firestore」的能力（使用者指示），供日後 CSV／OVERRIDES 校準後、
/// 以 CSV 為真相來源重跑時使用；當前初始種子請走本程式。
///
/// 用法：
///   cd fitness-app
///   dart run tools/export_platform_defs.dart [輸出路徑]   # 預設 build/platform_defs.json
Future<void> main(List<String> args) async {
  final d = await const BundledPlatformData().load();

  final out = <String, Map<String, dynamic>>{
    'exercises': {for (final e in d.exercises) e.id: exerciseToMap(e)},
    'plans': {for (final s in d.planSpecs) s.id: planSpecToMap(s)},
    'achievement_defs': {
      for (final a in d.achievements) achievementDocId(a): achievementToMap(a),
    },
    'daily_task_pool': {
      for (final t in d.taskPool) t.id: taskPoolItemToMap(t),
    },
    'platform_config': {
      for (final e in d.config.entries) e.key: {'params': e.value},
    },
  };

  final path = args.isNotEmpty ? args.first : 'build/platform_defs.json';
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));

  stdout.writeln('平台資料種子已匯出 → $path');
  for (final e in out.entries) {
    stdout.writeln('  ${e.key}: ${e.value.length} 筆');
  }
}
