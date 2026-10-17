// ignore_for_file: subtype_of_sealed_class
// 平台資料的本機快取（QA-08，2026-10-17）。
//
// 平台資料約 675 筆，幾乎不會變，卻每次登入都整份重讀；Firestore 免費方案每天 5 萬次讀取，
// 一次載入約 900 次，不到 60 次載入就用光，用光之後連交易的讀取都被拒絕（見 PROGRESS 3AN）。
//
// 做法：雲端放一份小的版本文件（`platform_config/_meta` 的 `rev`），載入時只讀它；
// 跟本機快取的版本一樣就直接用快取，不一樣才整份重讀。後台改了平台資料就換版本。
//
// 「有沒有真的沒讀」這件事用**偷改雲端資料但不換版本**來證明：命中快取時，讀到的會是舊值。

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentReference, DocumentSnapshot, GetOptions, QuerySnapshot, SetOptions;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/platform_cache.dart';
import 'package:fitness_app/data/platform_data.dart';
import 'package:fitness_app/data/platform_data_firestore.dart';
import 'package:fitness_app/data/store.dart';

void main() {
  late PlatformData bundle;
  late FakeFirebaseFirestore db;
  late MemoryPlatformCache cache;

  Future<void> seedCloud({String? rev}) async {
    final asJson =
        jsonDecode(jsonEncode(platformSeedMap(bundle))) as Map<String, dynamic>;
    for (final c in asJson.entries) {
      for (final doc in (c.value as Map<String, dynamic>).entries) {
        await db
            .collection(c.key)
            .doc(doc.key)
            .set(doc.value as Map<String, dynamic>);
      }
    }
    if (rev != null) {
      await db.collection('platform_config').doc('_meta').set({'rev': rev});
    }
  }

  FirestorePlatformData src({PlatformCache? c}) =>
      FirestorePlatformData(firestore: db, cache: c ?? cache);

  /// 雲端那筆動作的係數（用來看「讀到的是不是新值」）。
  double ri(PlatformData d, String id) =>
      d.exercises.firstWhere((e) => e.id == id).relativeIntensity;

  setUp(() async {
    bundle = await const BundledPlatformData().load();
    db = FakeFirebaseFirestore();
    cache = MemoryPlatformCache();
  });

  group('命中與未命中', () {
    test('雲端沒有版本標記 → 照舊整份讀，也不存快取（沒辦法驗證它是不是還新鮮）', () async {
      await seedCloud();
      final got = await src().load();
      expect(got.exercises.length, bundle.exercises.length);
      expect(cache.writes, 0);
    });

    test('有版本、快取是空的 → 整份讀，並存進快取', () async {
      await seedCloud(rev: 'r1');
      final got = await src().load();
      expect(got.exercises.length, bundle.exercises.length);
      expect(cache.writes, 1);
      expect((await cache.read())!.rev, 'r1');
    });

    test('版本一樣 → 用快取，**不重讀那幾百筆**（偷改雲端但不換版本，讀到的仍是舊值）', () async {
      await seedCloud(rev: 'r1');
      final first = await src().load();
      final id = first.exercises.first.id;
      final old = ri(first, id);

      // 雲端偷偷改了，但版本沒換。
      await db
          .collection('exercises')
          .doc(id)
          .update({'relativeIntensity': old + 5});

      final second = await src().load();
      expect(ri(second, id), old,
          reason: '讀到新值代表它又整份重讀了，快取就沒有省到任何東西');
    });

    test('版本換了 → 重讀拿到新值，並更新快取', () async {
      await seedCloud(rev: 'r1');
      final first = await src().load();
      final id = first.exercises.first.id;
      final old = ri(first, id);

      await db
          .collection('exercises')
          .doc(id)
          .update({'relativeIntensity': old + 5});
      await db.collection('platform_config').doc('_meta').set({'rev': 'r2'});

      final second = await src().load();
      expect(ri(second, id), old + 5);
      expect((await cache.read())!.rev, 'r2');
      expect(ri((await cache.read())!.data, id), old + 5);
    });

    test('讀版本失敗 → 當作不知道，整份重讀（不拿快取賭）', () async {
      await seedCloud(rev: 'r1');
      await src().load(); // 存進快取
      // 版本文件整個消失（等於讀不到版本）。
      await db.collection('platform_config').doc('_meta').delete();
      final id = (await cache.read())!.data.exercises.first.id;
      await db.collection('exercises').doc(id).update({'relativeIntensity': 99.0});

      final got = await src().load();
      expect(ri(got, id), 99.0);
    });

    test('快取讀不出來（壞掉）→ 當作沒有，整份重讀', () async {
      await seedCloud(rev: 'r1');
      final broken = MemoryStore()..failWith = const StoreLoadException('壞了');
      final got = await src(c: StorePlatformCache(broken)).load();
      expect(got.exercises.length, bundle.exercises.length);
    });

    test('沒有傳快取 → 行為跟以前一樣', () async {
      await seedCloud(rev: 'r1');
      final got = await FirestorePlatformData(firestore: db).load();
      expect(got.exercises.length, bundle.exercises.length);
    });
  });

  group('不能存壞的東西', () {
    test('商品讀失敗退回打包資料時，不存快取（不然後備資料被當成這個版本的內容）', () async {
      await seedCloud(rev: 'r1');
      final bad = _ProductsFailDb(db);
      final got = await FirestorePlatformData(firestore: bad, cache: cache).load();
      expect(got.exercises.length, bundle.exercises.length);
      expect(cache.writes, 0);
    });

    test('教官題庫不進快取，每次都讀（它的說明文件只有管理員讀得到）', () async {
      await seedCloud(rev: 'r1');
      await db.collection('exam_questions').doc('q-new').set({
        'text': '新題目',
        'options': ['甲', '乙'],
        'answer': 0,
        'deleted': false,
      });
      await src().load(); // 存進快取
      final cached = await cache.read();
      expect(cached!.data.examQuestions, isEmpty, reason: '快取裡不該有題庫');
      final seed = platformDataToSeed(cached.data);
      expect(seed.containsKey('exam_questions'), isFalse);
      expect(seed.containsKey('exam_notes'), isFalse);
    });
  });

  group('後台改了就換版本', () {
    Future<String?> readRev() async =>
        (await db.collection('platform_config').doc('_meta').get())
            .data()?['rev'] as String?;

    test('改動作庫 → 版本換了', () async {
      await seedCloud(rev: 'r1');
      await src().put('exercises', 'x1', {'name': '新動作'});
      final r = await readRev();
      expect(r, isNotNull);
      expect(r, isNot('r1'));
    });

    test('改商品、課表、成就、任務池、設定 → 版本都會換', () async {
      for (final c in [
        'products',
        'plans',
        'achievement_defs',
        'daily_task_pool',
        'platform_config',
      ]) {
        await db.collection('platform_config').doc('_meta').set({'rev': 'r1'});
        await src().put(c, 'doc-$c', {'v': 1});
        expect(await readRev(), isNot('r1'), reason: c);
      }
    });

    test('刪每日任務池的一筆 → 版本也換', () async {
      await seedCloud(rev: 'r1');
      final id = bundle.taskPool.first.id;
      await src().remove('daily_task_pool', id);
      expect(await readRev(), isNot('r1'));
    });

    test('改教官題庫 → 不換版本（它不在快取裡）', () async {
      await seedCloud(rev: 'r1');
      await src().put('exam_questions', 'q1', {'text': 'x'});
      await src().put('exam_notes', 'q1', {'note': 'x'});
      expect(await readRev(), 'r1');
    });

    test('寫版本文件本身不會再換版本（不然沒完沒了）', () async {
      await db.collection('platform_config').doc('_meta').set({'rev': 'r1'});
      await src().put('platform_config', '_meta', {'rev': 'r1'});
      expect(await readRev(), 'r1');
    });

    test('資料寫上去了但換版本失敗 → 要說出來', () async {
      final bad = _MetaFailDb(db);
      await expectLater(
        FirestorePlatformData(firestore: bad, cache: cache)
            .put('exercises', 'x1', {'name': '新動作'}),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('版本標記沒有更新'))),
      );
      expect((await db.collection('exercises').doc('x1').get()).exists, isTrue,
          reason: '資料本身已經寫進去了');
    });
  });

  group('ensureRev（管理員補第一份版本）', () {
    test('沒有就補', () async {
      await src().ensureRev();
      final r = (await db.collection('platform_config').doc('_meta').get())
          .data()?['rev'];
      expect(r, isA<String>());
      expect((r as String).isNotEmpty, isTrue);
    });

    test('已經有就不動（不能每次登入都換版本）', () async {
      await db.collection('platform_config').doc('_meta').set({'rev': 'r1'});
      await src().ensureRev();
      final r = (await db.collection('platform_config').doc('_meta').get())
          .data()?['rev'];
      expect(r, 'r1');
    });
  });

  group('快取往返', () {
    test('整份平台資料存成 JSON 再讀回來，內容一樣', () async {
      final seed = jsonDecode(jsonEncode(platformDataToSeed(bundle))) as Map;
      final back = platformDataFromSeed(seed);
      expect(back.exercises.length, bundle.exercises.length);
      expect(back.planSpecs.length, bundle.planSpecs.length);
      expect(back.achievements.length, bundle.achievements.length);
      expect(back.taskPool.length, bundle.taskPool.length);
      expect(back.products.length, bundle.products.length);
      expect(jsonEncode(platformDataToSeed(back)),
          jsonEncode(platformDataToSeed(bundle)),
          reason: '逐筆逐欄一樣，不是只有筆數對');
    });

    test('存在 Store 裡再讀回來', () async {
      final store = MemoryStore();
      final c = StorePlatformCache(store);
      await c.write('r9', bundle);
      final got = await c.read();
      expect(got!.rev, 'r9');
      expect(got.data.exercises.length, bundle.exercises.length);
    });

    test('版本格式不對、舊版格式 → 當作沒有快取', () async {
      final store = MemoryStore();
      await store.save({'v': 99, 'rev': 'r1', 'data': {}});
      expect(await StorePlatformCache(store).read(), isNull);
      await store.save({'v': 1, 'rev': '', 'data': {}});
      expect(await StorePlatformCache(store).read(), isNull);
    });

    test('寫不進去不丟例外（快取是盡力而為）', () async {
      final c = StorePlatformCache(_FailingSaveStore());
      await c.write('r1', bundle); // 不炸就算過
    });
  });

  test('main 與上傳腳本都接上了：換版本不只靠 App', () {
    // 上傳了卻不換版本，已經有快取的裝置會一直拿舊的。
    final py = File('../tools/upload_platform_data.py').readAsStringSync();
    expect(py, contains('platform_config'));
    expect(py, contains('_meta'));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('StorePlatformCache(platformCacheStore())'));
  });
}

/// 讀取 `products` 一律失敗的資料庫（其餘照假資料庫）。
class _ProductsFailDb extends FakeFirebaseFirestore {
  final FakeFirebaseFirestore inner;
  _ProductsFailDb(this.inner);

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      path == 'products'
          ? _FailGetCollection(inner.collection(path))
          : inner.collection(path);
}

class _FailGetCollection implements CollectionReference<Map<String, dynamic>> {
  final CollectionReference<Map<String, dynamic>> inner;
  _FailGetCollection(this.inner);

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      Future.error(StateError('products 讀不到'));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// 寫 `platform_config/_meta` 一律失敗的資料庫（其餘照假資料庫）。
class _MetaFailDb extends FakeFirebaseFirestore {
  final FakeFirebaseFirestore inner;
  _MetaFailDb(this.inner);

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      path == 'platform_config'
          ? _MetaFailCollection(inner.collection(path))
          : inner.collection(path);
}

class _MetaFailCollection implements CollectionReference<Map<String, dynamic>> {
  final CollectionReference<Map<String, dynamic>> inner;
  _MetaFailCollection(this.inner);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      path == '_meta' ? _MetaFailDoc(inner.doc(path)) : inner.doc(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _MetaFailDoc implements DocumentReference<Map<String, dynamic>> {
  final DocumentReference<Map<String, dynamic>> inner;
  _MetaFailDoc(this.inner);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      Future.error(StateError('權限不足'));

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      inner.get(options);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FailingSaveStore extends MemoryStore {
  @override
  Future<void> save(Map<String, dynamic> data) async => throw StateError('空間不足');
}
