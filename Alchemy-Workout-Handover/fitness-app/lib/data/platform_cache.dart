import 'platform_data.dart';
import 'store.dart';

/// 本機存的一份平台資料，連同它對應的**版本**。
class CachedPlatform {
  final String rev;
  final PlatformData data;
  const CachedPlatform(this.rev, this.data);
}

/// 平台資料的本機快取。
///
/// ## 為什麼要有
///
/// 平台資料（動作庫 527、成就 99、課表 31、任務池 7、設定 11、商品…）共約 675 筆以上，
/// 幾乎不會變，卻**每次登入或重新整理都整份重讀**。Firestore 免費方案每天只有 5 萬次讀取，
/// 一次載入約 900 次，其中四分之三是這份 —— 一天不到 60 次載入就用光，
/// 用光之後連交易的讀取都被伺服器拒絕（2026-10-17，見 PROGRESS 3AN）。
///
/// ## 怎麼用
///
/// 雲端有一份很小的版本文件（`platform_config/_meta` 的 `rev`）。載入時只讀它這 1 筆：
/// 跟本機快取的版本一樣就直接用快取，不一樣才整份重讀並更新快取。
/// 後台改了平台資料就同時換版本（見 `FirestorePlatformData.put`）。
///
/// **快取是盡力而為**：讀不到、壞掉、寫不進去都不該影響使用，一律當作沒有快取、照舊整份重讀。
abstract class PlatformCache {
  Future<CachedPlatform?> read();
  Future<void> write(String rev, PlatformData data);
}

/// 測試用。
class MemoryPlatformCache implements PlatformCache {
  CachedPlatform? _c;
  int writes = 0;

  @override
  Future<CachedPlatform?> read() async => _c;

  @override
  Future<void> write(String rev, PlatformData data) async {
    writes++;
    _c = CachedPlatform(rev, data);
  }
}

/// 存在裝置上（手機是檔案，網頁是 localStorage）的快取。
class StorePlatformCache implements PlatformCache {
  final Store _store;
  StorePlatformCache(this._store);

  static const int _version = 1;

  @override
  Future<CachedPlatform?> read() async {
    try {
      final m = await _store.load();
      if (m == null || m['v'] != _version) return null;
      final rev = m['rev'];
      final seed = m['data'];
      if (rev is! String || rev.isEmpty || seed is! Map) return null;
      return CachedPlatform(rev, platformDataFromSeed(seed));
    } catch (_) {
      // 壞掉或讀不出來：當作沒有快取。
      return null;
    }
  }

  @override
  Future<void> write(String rev, PlatformData data) async {
    try {
      await _store.save({
        'v': _version,
        'rev': rev,
        'data': platformDataToSeed(data),
      });
    } catch (_) {
      // 寫不進去（空間不足等）不影響使用，下次照舊整份重讀。
    }
  }
}

/// 快取要存的內容：五個平台集合（與上傳用的種子同一份定義）加商品。
/// **不含教官題庫** —— 題庫的說明文件只有管理員讀得到，存在共用的裝置上，
/// 下一個登入的人就看得到了。
Map<String, Map<String, dynamic>> platformDataToSeed(PlatformData d) => {
      ...platformSeedMap(d),
      'products': {for (final p in d.products) p.id: productToMap(p)},
    };

PlatformData platformDataFromSeed(Map seed) {
  Map<String, dynamic> col(String name) =>
      Map<String, dynamic>.from((seed[name] as Map?) ?? const {});
  return PlatformData(
    exercises: [
      for (final e in col('exercises').entries)
        exerciseFromDoc(e.key, Map<String, dynamic>.from(e.value as Map)),
    ],
    planSpecs: [
      for (final e in col('plans').entries)
        planSpecFromDoc(e.key, Map<String, dynamic>.from(e.value as Map)),
    ],
    achievements: [
      for (final e in col('achievement_defs').entries)
        achievementFromDoc(e.key, Map<String, dynamic>.from(e.value as Map)),
    ],
    taskPool: [
      for (final e in col('daily_task_pool').entries)
        taskPoolItemFromDoc(e.key, Map<String, dynamic>.from(e.value as Map)),
    ],
    config: {
      for (final e in col('platform_config').entries)
        e.key: {
          for (final p in ((e.value as Map)['params'] as Map).entries)
            if (p.value is num) p.key as String: p.value as num,
        },
    },
    products: [
      for (final e in col('products').entries)
        productFromDoc(e.key, Map<String, dynamic>.from(e.value as Map)),
    ],
  );
}
