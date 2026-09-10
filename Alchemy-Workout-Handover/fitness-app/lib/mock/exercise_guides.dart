import 'dart:convert';

import 'package:flutter/services.dart';

/// 動作的教學文字。由 tools/import_exercises.py 自 CSV 產生，
/// 再由 tools/guides_zh.py 逐筆中譯（527 / 527）。
///
/// 與結構化欄位分開存放：清單頁只需要名稱、肌群、器材，且那些要能同步取用；
/// 教學文字很長（211KB）且只有動作詳情頁用得到，做成資產延遲載入。
class ExerciseGuide {
  final String setup;
  final String howto;
  final String tips;
  const ExerciseGuide({required this.setup, required this.howto, required this.tips});

  bool get isEmpty => setup.isEmpty && howto.isEmpty && tips.isEmpty;
}

Map<String, ExerciseGuide>? _cache;

/// 首次呼叫時載入並快取；之後同步取用。
Future<Map<String, ExerciseGuide>> loadGuides() async {
  if (_cache != null) return _cache!;
  final raw = await rootBundle.loadString('assets/data/exercise_guides.zh.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  _cache = json.map((k, v) => MapEntry(
        k,
        ExerciseGuide(
          setup: (v['setup'] ?? '') as String,
          howto: (v['howto'] ?? '') as String,
          tips: (v['tips'] ?? '') as String,
        ),
      ));
  return _cache!;
}

ExerciseGuide? guideOf(String id) => _cache?[id];
