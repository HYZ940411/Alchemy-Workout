// 真的那一份快照，Firestore 收不收得下（2026-09-24）。
//
// ## 這條測試是從一次我自己造成的線上事故來的
//
// 2026-09-24 我把偏好訓練時段補進存檔，形狀寫成「七天各一個陣列」：
//
//     'preferredTimes': [[{from,to}], [], [], ...]
//
// 那是**陣列包陣列，而 Firestore 不收**。關鍵在於它不是「丟掉那個
// 欄位」——**整份寫入被拒**。而 `AppState.saveNow()` 對寫入失敗是
// 靜默吞掉的，所以症狀是「從那一刻起這個帳號什麼都存不起來」，
// 沒有任何錯誤訊息。使用者回報的樣子是「填了、刷新還是未填寫」。
//
// **當時所有測試都是綠的。** `persistence_test` 用的是 MemoryStore 與
// FileStore，兩者都是純 JSON，收得下巢狀陣列；`store_firestore_test`
// 有一條「落地時不可以有巢狀陣列」，但它**寫死只看訓練歷史的 sets**，
// 因為那是當時唯一踩過這個坑的欄位。
//
// 所以這一條改成反過來驗：**拿真的 `AppState.toSnapshot()` 走一次真的
// `FirestoreStore.save()`，然後把寫進去的每一份文件整個走一遍。**
// 以後任何人加任何欄位，形狀不合都會在這裡紅。
//
// `fake_cloud_firestore` 自己不擋巢狀陣列（真的 Firestore 會），
// 所以不能靠「它有沒有丟例外」—— 必須自己走一遍寫進去的東西。

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/store.dart';
import 'package:fitness_app/data/store_firestore.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/novice_wrapup.dart';
import 'package:fitness_app/state/app_state.dart';

/// 走遍一份文件，回報第一個「陣列裡還有陣列」的位置。
String? findNestedArray(Object? v, String path) {
  if (v is List) {
    for (var i = 0; i < v.length; i++) {
      final e = v[i];
      if (e is List) return '$path[$i]';
      final deeper = findNestedArray(e, '$path[$i]');
      if (deeper != null) return deeper;
    }
  } else if (v is Map) {
    for (final e in v.entries) {
      final deeper = findNestedArray(e.value, '$path.${e.key}');
      if (deeper != null) return deeper;
    }
  }
  return null;
}

/// 這個帳號寫進 Firestore 的每一份文件。
Future<Map<String, Map<String, dynamic>>> storedDocs(
    FakeFirebaseFirestore db, String uid) async {
  final out = <String, Map<String, dynamic>>{};
  final root = db.collection('users').doc(uid);
  final snap = await root.get();
  if (snap.exists) out['users/$uid'] = snap.data()!;
  for (final col in const [
    'ability',
    'streaks',
    'wallet',
    'membership',
    'history'
  ]) {
    for (final d in (await root.collection(col).get()).docs) {
      out['$col/${d.id}'] = d.data();
    }
  }
  return out;
}

/// 一個**填滿東西**的帳號 —— 空的帳號驗不到形狀。
AppState populated() {
  final s = AppState()
    ..displayName = '阿健'
    ..coins = 500
    ..totalExp = 12000;

  // 這一組正是那次事故的欄位。
  s.setPreferredTimes(PreferredTimes([
    [const TimeRange(6 * 60, 8 * 60), const TimeRange(19 * 60, 21 * 60)],
    [],
    [const TimeRange(7 * 60, 9 * 60)],
    [], [], [],
    [const TimeRange(10 * 60, 12 * 60)],
  ]));
  s.rateExperience(RatingTarget.noviceTask, kNoviceTaskId, 4,
      feedback: '動作說明清楚');

  s.points[Dim.chest] = 320;
  s.pending[Dim.legs] = 40;
  return s;
}

void main() {
  test('走遍寫進 Firestore 的每一份文件，沒有陣列包陣列', () async {
    final db = FakeFirebaseFirestore();
    final s = populated();

    await FirestoreStore(uid: 'u1', firestore: db).save(s.toSnapshot());

    final docs = await storedDocs(db, 'u1');
    expect(docs, isNotEmpty, reason: '什麼都沒寫進去＝這條測試沒在驗東西');

    final offences = <String>[];
    for (final e in docs.entries) {
      final hit = findNestedArray(e.value, e.key);
      if (hit != null) offences.add(hit);
    }

    expect(
      offences,
      isEmpty,
      reason: 'Firestore 不收陣列包陣列，而且是**整份寫入被拒**，'
          '不是只丟掉那個欄位。\n'
          'saveNow() 靜默吞掉寫入失敗，所以症狀會是「這個帳號從此什麼都'
          '存不起來」，沒有任何錯誤訊息。\n'
          '把它攤平成一維，或在存的時候轉成物件（見 _historyToDoc）：\n'
          '${offences.join('\n')}',
    );
  });

  test('偏好時段存進去是攤平的，且存讀一輪不走樣', () async {
    final db = FakeFirebaseFirestore();
    final s = populated();
    await FirestoreStore(uid: 'u1', firestore: db).save(s.toSnapshot());

    final root = (await db.collection('users').doc('u1').get()).data()!;
    final rows = root['preferredTimes'] as List;
    expect(rows, hasLength(4), reason: '四段區間攤平成四筆');
    expect(rows.first, isA<Map>(), reason: '不可以是陣列');

    final back = AppState();
    expect(back.applySnapshot((await FirestoreStore(uid: 'u1', firestore: db)
        .load())!), isTrue);

    expect(back.preferredTimes.filledDays, 3);
    expect(back.preferredTimes.byDay[0], hasLength(2));
    expect(back.preferredTimes.byDay[0].first.startMin, 6 * 60);
    expect(back.preferredTimes.byDay[6].single.startMin, 10 * 60);
  });

  test('體驗評分也走得完整趟', () async {
    final db = FakeFirebaseFirestore();
    await FirestoreStore(uid: 'u1', firestore: db).save(populated().toSnapshot());

    final back = AppState();
    back.applySnapshot(
        (await FirestoreStore(uid: 'u1', firestore: db).load())!);

    expect(back.noviceRating?.stars, 4);
    expect(back.noviceRating?.feedback, '動作說明清楚');
  });

  _saveFailureIsVisible();

  test('壞掉的那一筆不會打翻整份時段', () async {
    // 手改過的資料、或以後改了形狀的舊存檔。
    final s = AppState();
    final snap = s.toSnapshot();
    snap['preferredTimes'] = [
      {'day': 0, 'from': 360, 'to': 480},
      {'day': 99, 'from': 0, 'to': 60}, // 不存在的星期
      {'day': 1}, // 缺欄位
      'not a map',
    ];

    final back = AppState();
    expect(back.applySnapshot(snap), isTrue);
    expect(back.preferredTimes.byDay[0].single.startMin, 360);
    expect(back.preferredTimes.filledDays, 1);
  });
}

/// 寫入一律失敗的 Store。
class _BrokenStore implements Store {
  @override
  Future<Map<String, dynamic>?> load() async => AppState().toSnapshot();
  @override
  Future<void> save(Map<String, dynamic> data) async =>
      throw StateError('Invalid argument: nested arrays are not supported');
  @override
  Future<void> clear() async {}
}

void _saveFailureIsVisible() {
  group('存檔失敗要留下痕跡', () {
    test('失敗時記下原因與連續次數', () async {
      final s = AppState();
      await s.hydrate(_BrokenStore());
      expect(s.saveError, isNull, reason: '前提：還沒存過');

      await s.saveNow();
      expect(s.saveError, contains('nested arrays'));
      expect(s.consecutiveSaveFailures, 1);

      await s.saveNow();
      expect(s.consecutiveSaveFailures, 2, reason: '連續次數要累加');
    });

    test('存檔失敗不往外丟 —— 不中斷使用者正在做的事', () async {
      final s = AppState();
      await s.hydrate(_BrokenStore());
      await expectLater(s.saveNow(), completes);
    });

    test('成功之後把痕跡清掉', () async {
      final s = AppState();
      await s.hydrate(_BrokenStore());
      await s.saveNow();
      expect(s.saveError, isNotNull);

      // 換成一個正常的 Store 再存。
      await s.hydrate(MemoryStore()..save(s.toSnapshot()));
      await s.saveNow();

      expect(s.saveError, isNull);
      expect(s.consecutiveSaveFailures, 0);
    });
  });
}
