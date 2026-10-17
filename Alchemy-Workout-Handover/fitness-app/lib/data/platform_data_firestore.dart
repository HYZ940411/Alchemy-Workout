import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../domain/task_pool.dart';
import '../mock/mock_admin.dart';
import 'http_error.dart';
import 'platform_cache.dart';
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
class FirestorePlatformData implements PlatformDataSource, PlatformRevisioned {
  final FirebaseFirestore _db;

  /// 本機快取。空值＝不用快取，每次整份重讀（既有行為）。
  final PlatformCache? cache;

  /// 版本文件：`platform_config/_meta` 的 `rev`。放在 `platform_config` 底下，
  /// 是因為那個集合「登入者可讀、管理員可寫」，不必動安全規則。
  static const metaDoc = '_meta';

  /// 換了就要換版本的集合 —— 快取裡存的那幾個。教官題庫不在快取裡（見 platform_cache.dart），所以不算。
  static const _versioned = {
    'exercises',
    'plans',
    'achievement_defs',
    'daily_task_pool',
    'platform_config',
    'products',
  };

  /// 讀不到時的後備來源。預設為打包在本地的那份。
  final PlatformDataSource fallback;

  FirestorePlatformData({
    FirebaseFirestore? firestore,
    this.fallback = const BundledPlatformData(),
    this.cache,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> put(
      String collection, String docId, Map<String, dynamic> data) async {
    await _db.collection(collection).doc(docId).set(data);
    await _bumpRev(collection, docId);
  }

  @override
  Future<void> remove(String collection, String docId) async {
    await _db.collection(collection).doc(docId).delete();
    await _bumpRev(collection, docId);
  }

  DocumentReference<Map<String, dynamic>> get _meta =>
      _db.collection('platform_config').doc(metaDoc);

  String _newRev() => DateTime.now().microsecondsSinceEpoch.toString();

  /// 讀版本與重置代數（同一份文件，**一次讀取**）。**沒有、讀不到、格式不對一律回空值**
  /// （版本空值＝呼叫端當作「不知道版本」，整份重讀；代數空值＝不動目前的代數）。
  Future<({String? rev, int? epoch})> _readMeta() async {
    try {
      final d = (await _meta.get()).data();
      final r = d?['rev'];
      final e = d?['timedEpoch'];
      return (
        rev: r is String && r.isNotEmpty ? r : null,
        epoch: e is num ? e.round() : 0,
      );
    } catch (_) {
      return (rev: null, epoch: null);
    }
  }

  Future<String?> _readRev() async => (await _readMeta()).rev;

  /// 換一個重置代數。用現在的秒數：不必先讀再加，而且永遠比上一次大。
  /// 只改 `timedEpoch`（merge），**不動 `rev`** —— 平台資料沒變，不該讓所有人重讀快取。
  @override
  Future<int> resetTimedTask() async {
    final e = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _meta.set({'timedEpoch': e}, SetOptions(merge: true));
    return e;
  }

  /// 後台改了會進快取的集合，就換一個新版本，其他裝置下次載入才會重讀。
  ///
  /// 資料已經寫進去了才換版本；換版本失敗要**說出來** —— 否則管理員以為存好了，
  /// 其他人卻會一直拿著舊的快取。
  Future<void> _bumpRev(String collection, String docId) async {
    if (!_versioned.contains(collection)) return;
    if (collection == 'platform_config' && docId == metaDoc) return;
    try {
      // merge：不能把同一份文件裡的 timedEpoch（限時任務重置代數）蓋掉。
      await _meta.set({'rev': _newRev(), 'at': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    } catch (e) {
      throw StateError('已寫入，但版本標記沒有更新，其他人要等下次更新才看得到'
          '（${describeError(e)}）');
    }
  }

  /// 雲端還沒有版本標記就補一份（只有管理員寫得進去）。
  ///
  /// 沒有版本標記，所有裝置都只能整份重讀；補上之後第一次載入會寫入各自的快取，
  /// 之後才開始省讀取。已經有就不動 —— 不能每次登入都換版本，那等於沒有快取。
  @override
  Future<void> ensureRev() async {
    if (await _readRev() != null) return;
    await _meta.set({'rev': _newRev(), 'at': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
  }

  @override
  Future<PlatformData> load() async {
    final bundle = await fallback.load();
    try {
      // **先讀版本，再讀資料。** 反過來的話，讀完資料到讀版本之間若有人改了，
      // 會把新版本標在舊資料上，下次就永遠不重讀。先讀版本最壞只是多重讀一次。
      final meta = await _readMeta();
      final rev = meta.rev;
      final hit = rev == null ? null : await cache?.read();
      PlatformData core;
      if (hit != null && hit.rev == rev) {
        core = hit.data; // 版本一樣：不讀那 600 多筆
      } else {
        final (data, complete) = await _fetchCore(bundle);
        core = data;
        // 只有**每一類都真的讀自雲端**才存。某一類讀失敗退回了打包資料的話，
        // 把它存起來就是把後備資料當成這個版本的內容。
        if (rev != null && complete) await cache?.write(rev, core);
      }
      // 題庫每次都讀：它有只有管理員讀得到的說明文件，不進共用的裝置快取。
      final exam = await loadExamBank(
        questions: () => _db.collection('exam_questions').get(),
        notes: () => _db.collection('exam_notes').get(),
        bundle: bundle.examQuestions,
      );
      return PlatformData(
        exercises: core.exercises,
        planSpecs: core.planSpecs,
        achievements: core.achievements,
        taskPool: core.taskPool,
        config: core.config,
        products: core.products,
        examQuestions: exam,
        timedEpoch: meta.epoch,
      );
    } catch (_) {
      // 連線或權限層級的整體失敗：整份退回後備，不擋使用者進場。
      return bundle;
    }
  }

  /// 讀五個平台集合與商品。回傳 (資料, 是不是每一類都讀自雲端)。
  Future<(PlatformData, bool)> _fetchCore(PlatformData bundle) async {
    final fetched = await Future.wait([
      _db.collection('exercises').get(),
      _db.collection('plans').get(),
      _db.collection('achievement_defs').get(),
      _db.collection('daily_task_pool').get(),
      _db.collection('platform_config').get(),
    ]);
    // 商品單獨讀、單獨失敗：安全規則還沒放行 `products`（或這一類單獨出事）時，
    // 不能把前面五類一起拖回後備 —— 那會讓所有使用者的動作庫、課表整份退回打包版。
    var complete = true;
    List<AdminProduct> products;
    try {
      products = _mergeProducts(
          await _db.collection('products').get(), bundle.products);
    } catch (_) {
      products = bundle.products;
      complete = false;
    }
    return (
      PlatformData(
        exercises: _listOr(fetched[0], exerciseFromDoc, bundle.exercises),
        planSpecs: _listOr(fetched[1], planSpecFromDoc, bundle.planSpecs),
        achievements:
            _listOr(fetched[2], achievementFromDoc, bundle.achievements),
        taskPool: _listOr(fetched[3], taskPoolItemFromDoc, bundle.taskPool),
        config: _configOr(fetched[4], bundle.config),
        products: products,
      ),
      complete,
    );
  }

  /// 題庫：內建當底，雲端按 id 蓋上去；墓碑（`deleted`）把那題拿掉；
  /// 雲端獨有的接在後面。說明性欄位（理由、細則、追問）來自 [notes]，
  /// 讀不到時沿用內建同 id 那題的，沒有就留空。
  /// 題目與說明各自讀、各自失敗：非管理員讀不到說明文件是正常的，
  /// 不能因此連題目都拿不到；題目整類讀不到才退回內建。
  @visibleForTesting
  static Future<List<ExamQuestion>> loadExamBank({
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() questions,
    required Future<QuerySnapshot<Map<String, dynamic>>> Function() notes,
    required List<ExamQuestion> bundle,
  }) async {
    try {
      final q = await questions();
      QuerySnapshot<Map<String, dynamic>>? n;
      try {
        n = await notes();
      } catch (_) {
        n = null;
      }
      return _mergeExam(q, n, bundle);
    } catch (_) {
      return bundle;
    }
  }

  static List<ExamQuestion> _mergeExam(
      QuerySnapshot<Map<String, dynamic>> questions,
      QuerySnapshot<Map<String, dynamic>>? notes,
      List<ExamQuestion> bundle) {
    final noteDocs = {
      if (notes != null)
        for (final d in notes.docs) d.id: d.data(),
    };
    final cloud = <String, ExamQuestion?>{}; // null＝墓碑
    for (final d in questions.docs) {
      final m = d.data();
      if (m['deleted'] == true) {
        cloud[d.id] = null;
        continue;
      }
      try {
        cloud[d.id] = examQuestionFromDocs(d.id, m, noteDocs[d.id]);
      } catch (_) {
        // 單筆壞掉略過，沿用內建的那一題。
      }
    }
    final out = <ExamQuestion>[];
    for (final b in bundle) {
      if (!cloud.containsKey(b.id)) {
        out.add(b);
        continue;
      }
      final c = cloud.remove(b.id);
      if (c == null) continue; // 墓碑
      // 讀不到說明文件（非管理員）時，說明性欄位留空，不拿內建的補 ——
      // 內建那份的細則可能已經被管理員改掉了。
      out.add(c);
    }
    for (final c in cloud.values) {
      if (c != null) out.add(c);
    }
    return out;
  }

  /// 商品：內建的當底，雲端的按 id 蓋上去（被下架的也算數），雲端獨有的接在後面。
  ///
  /// 不用「雲端非空就整份取代」（其他平台資料的做法）：管理員第一次只改了其中一件商品，
  /// 雲端就只有一份文件，整份取代的話商城會只剩那一件。
  List<AdminProduct> _mergeProducts(
      QuerySnapshot<Map<String, dynamic>> snap, List<AdminProduct> bundle) {
    final cloud = <String, AdminProduct>{};
    for (final d in snap.docs) {
      try {
        cloud[d.id] = productFromDoc(d.id, d.data());
      } catch (_) {
        // 單筆壞掉略過，沿用內建的那一件。
      }
    }
    return [
      for (final b in bundle) cloud.remove(b.id) ?? b,
      ...cloud.values,
    ];
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
