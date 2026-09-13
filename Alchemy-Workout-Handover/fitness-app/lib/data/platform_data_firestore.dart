import 'package:cloud_firestore/cloud_firestore.dart';

import 'platform_data.dart';

/// Firestore 版的平台資料來源（[BE-12]）。
///
/// 與 [BundledPlatformData] 分成兩個檔：序列化邏輯與 [PlatformData]／
/// [BundledPlatformData] 留在 `platform_data.dart`（不依賴 cloud_firestore，
/// 因此 `tools/export_platform_defs.dart` 能以 `dart run` 重用那些序列化函式）；
/// 唯一碰 cloud_firestore 的是本檔。
///
/// 平行讀五個平台集合，逐筆反序列化。**任一類讀不到或格式不符，該類單獨
/// 退回本地後備**（而非整份失敗）—— 離線能用、半上線也能用，與動作庫
/// 「隨 App 打包、離線可用」的既有設計一致。
class FirestorePlatformData implements PlatformDataSource {
  final FirebaseFirestore _db;

  /// 讀不到時的後備來源。預設為打包在本地的那份。
  final PlatformDataSource fallback;

  FirestorePlatformData({
    FirebaseFirestore? firestore,
    this.fallback = const BundledPlatformData(),
  }) : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Future<PlatformData> load() async {
    final bundle = await fallback.load();
    try {
      final fetched = await Future.wait([
        _db.collection('exercises').get(),
        _db.collection('plans').get(),
        _db.collection('achievement_defs').get(),
        _db.collection('daily_task_pool').get(),
        _db.collection('platform_config').get(),
      ]);
      return PlatformData(
        exercises: _listOr(fetched[0], exerciseFromDoc, bundle.exercises),
        planSpecs: _listOr(fetched[1], planSpecFromDoc, bundle.planSpecs),
        achievements:
            _listOr(fetched[2], achievementFromDoc, bundle.achievements),
        taskPool: _listOr(fetched[3], taskPoolItemFromDoc, bundle.taskPool),
        config: _configOr(fetched[4], bundle.config),
      );
    } catch (_) {
      // 連線或權限層級的整體失敗：整份退回後備，不擋使用者進場。
      return bundle;
    }
  }

  /// 空集合或逐筆解析全失敗時退回 [bundle]；否則回傳解析成功的那些。
  List<T> _listOr<T>(QuerySnapshot<Map<String, dynamic>> snap,
      T Function(String id, Map<String, dynamic>) parse, List<T> bundle) {
    if (snap.docs.isEmpty) return bundle;
    final out = <T>[];
    for (final d in snap.docs) {
      try {
        out.add(parse(d.id, d.data()));
      } catch (_) {
        // 單筆壞掉略過即可，不拖垮整類。
      }
    }
    return out.isEmpty ? bundle : out;
  }

  Map<String, Map<String, num>> _configOr(
      QuerySnapshot<Map<String, dynamic>> snap,
      Map<String, Map<String, num>> bundle) {
    if (snap.docs.isEmpty) return bundle;
    final out = <String, Map<String, num>>{};
    for (final d in snap.docs) {
      final params = d.data()['params'];
      if (params is! Map) continue;
      out[d.id] = {
        for (final e in params.entries)
          if (e.value is num) e.key as String: e.value as num,
      };
    }
    return out.isEmpty ? bundle : out;
  }
}
